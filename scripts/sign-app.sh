#!/bin/bash
# A persistent certificate, not a per-build cdhash, identifies this app to macOS TCC.
set -euo pipefail
umask 077
if [ "$#" -ne 1 ] || [ ! -d "$1/Contents" ]; then
    echo 'Usage: scripts/sign-app.sh /path/to/Voice Input.app' >&2
    exit 1
fi
signing_dir="$HOME/Library/Application Support/VoiceInputSigning"
signing_keychain="$signing_dir/signing.keychain-db"
signing_certificate="$signing_dir/certificate.pem"
signing_password="$signing_dir/keychain-password"
mkdir -p "$signing_dir"
chmod 700 "$signing_dir"

# Never silently rotate an existing identity: that would invalidate permissions again.
if [ ! -f "$signing_keychain" ] && [ ! -f "$signing_certificate" ] && [ ! -f "$signing_password" ]; then
    temp_dir="$(mktemp -d "$signing_dir/bootstrap.XXXXXX")"
    trap 'rm -rf "$temp_dir"' EXIT
    /usr/bin/openssl rand -hex 32 > "$signing_password"
    /usr/bin/openssl rand -hex 32 > "$temp_dir/import-password"
    cat > "$temp_dir/certificate.cnf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = Voice Input Local Signing
[extensions]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG
    /usr/bin/openssl req -new -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
        -config "$temp_dir/certificate.cnf" -keyout "$temp_dir/private-key.pem" \
        -out "$signing_certificate" 2> "$temp_dir/openssl.log"
    /usr/bin/openssl pkcs12 -export -inkey "$temp_dir/private-key.pem" \
        -in "$signing_certificate" -name 'Voice Input Local Signing' \
        -out "$temp_dir/identity.p12" -passout "file:$temp_dir/import-password"
    security create-keychain -p "$(cat "$signing_password")" "$signing_keychain"
    security unlock-keychain -p "$(cat "$signing_password")" "$signing_keychain"
    security import "$temp_dir/identity.p12" -k "$signing_keychain" -f pkcs12 \
        -P "$(cat "$temp_dir/import-password")" -x -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
        -k "$(cat "$signing_password")" "$signing_keychain" >/dev/null
    # Only this user's codesign process may trust it, only for code signing.
    security add-trusted-cert -r trustRoot -p codeSign -a /usr/bin/codesign \
        -k "$signing_keychain" "$signing_certificate"
    # Remove the unencrypted staging key immediately; only the Keychain copy survives.
    rm -rf "$temp_dir"
    trap - EXIT
elif [ ! -f "$signing_keychain" ] || [ ! -f "$signing_certificate" ] || [ ! -f "$signing_password" ]; then
    echo "Incomplete signing identity in $signing_dir. Restore it; do not regenerate it." >&2
    exit 1
fi

# Certificate-chain resolution also uses the user's search list (codesign manual).
# Append our private keychain while preserving every existing entry and its order.
python3 - "$signing_keychain" <<'PYLIST'
import shlex, subprocess, sys
items = shlex.split(subprocess.check_output(["security", "list-keychains", "-d", "user"], text=True))
if sys.argv[1] not in items:
    subprocess.run(["security", "list-keychains", "-d", "user", "-s", *items, sys.argv[1]], check=True)
PYLIST

fingerprint="$(/usr/bin/openssl x509 -in "$signing_certificate" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
security unlock-keychain -p "$(cat "$signing_password")" "$signing_keychain"
trap 'security lock-keychain "$signing_keychain" >/dev/null 2>&1 || true' EXIT
requirement="identifier \"local.voiceinput.app\" and certificate leaf = H\"$fingerprint\""
codesign --force --sign "$fingerprint" --keychain "$signing_keychain" --timestamp=none \
    --identifier local.voiceinput.app --requirements "=designated => $requirement" "$1"
codesign --verify --deep --strict --test-requirement "=$requirement" "$1"
