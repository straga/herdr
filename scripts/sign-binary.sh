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

SELF_SIGNED="herdr Self-Signed"
identity=""
ad_hoc=""

if [ -n "${HERDR_SIGN_IDENTITY:-}" ]; then
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
  echo "==> Signing with: $identity"
fi

codesign "${args[@]}" "$BIN"

echo "==> Signature"
codesign -dv --verbose=2 "$BIN" 2>&1 | grep -E "^(Identifier|Authority)=" | head -3
codesign --verify --strict "$BIN" && echo "signature verifies"
