#!/usr/bin/env bash
# Creates a self-signed code-signing certificate and imports it into the login keychain.
#
# Why: macOS ties a granted permission to the binary's code signature. An unsigned or
# ad-hoc-signed binary is identified by its hash, which changes on every rebuild, so the
# system treats each build as a new application and asks for folder access again. A
# certificate that stays put makes the signature stable, and the grant survives rebuilds.
set -euo pipefail

CN="herdr Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if security find-certificate -c "$CN" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Certificate \"$CN\" already exists — nothing to do."
  exit 0
fi

echo "==> Generating a self-signed certificate with EKU=codeSigning"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
  -subj "/CN=$CN" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

P12PASS="herdr"
# Legacy algorithms (SHA1/3DES): the macOS keychain cannot read a PKCS12 written by
# OpenSSL 3 with its modern defaults.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/cert.p12" -passout "pass:$P12PASS" -name "$CN" \
  -legacy -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES

echo "==> Importing into the login keychain, allowing codesign to use it"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$P12PASS" \
  -T /usr/bin/codesign -A

echo "==> Marking the certificate as trusted for code signing"
# This may open a dialog asking for your account password.
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" 2>/dev/null \
  || echo "  (could not set trust automatically — local signing works without it)"

echo
echo "Done. Check:"
security find-identity -p codesigning "$KEYCHAIN" | grep "$CN" || true
echo
echo "On the first signing macOS may ask whether codesign may use the key."
echo "Choose \"Always Allow\", otherwise every build stops on that dialog."
