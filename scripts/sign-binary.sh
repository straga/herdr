#!/usr/bin/env bash
# Signs a freshly built herdr binary with the most stable identity available.
#
# The identity is chosen in this order:
#   1. $HERDR_SIGN_IDENTITY  — set it to pick a specific one
#   2. a Developer ID Application certificate, if the keychain holds one
#   3. the self-signed certificate from scripts/create-cert.sh
#   4. ad-hoc, with a warning — permissions will be re-asked after every rebuild
#
# $HERDR_SIGN_IDENTIFIER overrides the bundle identifier codesign derives from the file
# name. macOS keys granted permissions by identifier as well, so keep it stable once a
# machine has answered those dialogs.
#
# Signing without a person at the screen. The login keychain unlocks only inside a GUI
# session: from SSH codesign fails with errSecInternalComponent, and from a process with no
# window (a terminal multiplexer's server, an agent) it waits forever for a password dialog
# nobody can see. For those, keep the certificate in a dedicated build keychain with a known
# password and name both in $HERDR_SIGN_KEYCHAIN and $HERDR_SIGN_KEYCHAIN_PASSWORD_FILE, or
# in ${XDG_CONFIG_HOME:-~/.config}/herdr/signing.env, which this script reads by itself:
#
#   HERDR_SIGN_KEYCHAIN=$HOME/Library/Keychains/build.keychain-db
#   HERDR_SIGN_KEYCHAIN_PASSWORD_FILE=$HOME/.config/secrets/build-keychain-password
#
# With a build keychain configured the script unlocks it, signs from it and refuses rather
# than falls back: a silent fallback to the login keychain is exactly the hang it exists to
# avoid.
#
# macOS only. On every other platform the script says so and exits 0, so it can sit in a
# build recipe unconditionally.
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Not macOS — nothing to sign."
  exit 0
fi

BIN="${1:-target/release/herdr}"

if [ ! -f "$BIN" ]; then
  echo "No binary at $BIN — build it first." >&2
  exit 1
fi

SIGNING_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/signing.env"
if [ -z "${HERDR_SIGN_KEYCHAIN:-}" ] && [ -f "$SIGNING_ENV" ]; then
  # shellcheck disable=SC1090
  . "$SIGNING_ENV"
fi
KEYCHAIN="${HERDR_SIGN_KEYCHAIN:-}"
KEYCHAIN_PW="${HERDR_SIGN_KEYCHAIN_PASSWORD_FILE:-}"

SELF_SIGNED="herdr Self-Signed"
identity=""
ad_hoc=""

if [ -n "$KEYCHAIN" ]; then
  [ -f "$KEYCHAIN" ] || { echo "No build keychain at $KEYCHAIN." >&2; exit 1; }
  [ -s "$KEYCHAIN_PW" ] || { echo "No password file for the build keychain at '$KEYCHAIN_PW'." >&2; exit 1; }
  # The password reaches security as an argument and is never printed.
  security unlock-keychain -p "$(cat "$KEYCHAIN_PW")" "$KEYCHAIN" \
    || { echo "The build keychain did not unlock with the stored password." >&2; exit 1; }
  # A keychain that re-locks on a timeout fails in the middle of a signature.
  security set-keychain-settings "$KEYCHAIN"
  if [ -n "${HERDR_SIGN_IDENTITY:-}" ]; then
    identity="$HERDR_SIGN_IDENTITY"
  else
    identity="$(security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null \
      | grep -m1 "Developer ID Application" \
      | sed -E 's/.*"(.*)".*/\1/' || true)"
  fi
  [ -n "$identity" ] || { echo "No Developer ID Application identity in $KEYCHAIN." >&2; exit 1; }
elif [ -n "${HERDR_SIGN_IDENTITY:-}" ]; then
  identity="$HERDR_SIGN_IDENTITY"
elif security find-identity -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
  identity="$(security find-identity -p codesigning 2>/dev/null \
    | grep -m1 "Developer ID Application" \
    | sed -E 's/.*"(.*)".*/\1/')"
elif security find-identity -p codesigning 2>/dev/null | grep -q "$SELF_SIGNED"; then
  identity="$SELF_SIGNED"
else
  identity="-"
  ad_hoc=1
fi

args=(--force --sign "$identity")
if [ -n "${HERDR_SIGN_IDENTIFIER:-}" ]; then
  args+=(-i "$HERDR_SIGN_IDENTIFIER")
fi

if [ -n "$ad_hoc" ]; then
  echo "==> No stable certificate found — signing ad-hoc."
  echo "    macOS will ask for folder access again after every rebuild."
  echo "    To stop that: ./scripts/create-cert.sh"
else
  echo "==> Signing with: $identity${KEYCHAIN:+ (from $KEYCHAIN)}"
fi

if [ -n "$KEYCHAIN" ]; then
  # The same identity may also live in the login keychain, and codesign --keychain does not
  # scope the lookup: it can still pick the login copy and fail on its unreachable private key.
  # The search list is narrowed to the build keychain for the signature only and restored
  # whatever happens; verification below runs with the normal list, because narrowing hides
  # the system keychain that holds the rest of the certificate chain.
  saved="$( { security list-keychains -d user || true; } | tr -d '" ' | tr '\n' ' ')"
  [ -n "$saved" ] || { echo "Cannot read the keychain search list; refusing to change it." >&2; exit 1; }
  # shellcheck disable=SC2064
  trap "security list-keychains -d user -s $saved >/dev/null 2>&1" EXIT
  security list-keychains -d user -s "$KEYCHAIN" >/dev/null
  codesign "${args[@]}" --keychain "$KEYCHAIN" "$BIN"
  # shellcheck disable=SC2086
  security list-keychains -d user -s $saved >/dev/null
  trap - EXIT
else
  codesign "${args[@]}" "$BIN"
fi

echo "==> Signature"
codesign -dv --verbose=2 "$BIN" 2>&1 | grep -E "^(Identifier|Authority)=" | head -3
codesign --verify --strict "$BIN" && echo "signature verifies"
