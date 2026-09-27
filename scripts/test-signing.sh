#!/bin/bash
# Prove that different binaries share a certificate-bound designated requirement.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
check_dir="$(mktemp -d "$PWD/.build/signing-test.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
for version in 1 2; do
    app="$check_dir/version-$version.app"
    mkdir -p "$app/Contents/MacOS"
    cp scripts/Info.plist "$app/Contents/Info.plist"
    printf 'int main(void) { return %s; }\n' "$version" > "$check_dir/main.c"
    xcrun clang -arch arm64 -mmacosx-version-min=14.0 "$check_dir/main.c" -o "$app/Contents/MacOS/VoiceInput"
    ./scripts/sign-app.sh "$app"
done
first="$check_dir/version-1.app"
second="$check_dir/version-2.app"
requirement="$(codesign -d -r- "$first" 2>&1 | sed -n 's/^designated => //p')"
second_requirement="$(codesign -d -r- "$second" 2>&1 | sed -n 's/^designated => //p')"
[ -n "$requirement" ] && [ "$requirement" = "$second_requirement" ]
first_hash="$(codesign -dvv "$first" 2>&1 | sed -n 's/^CDHash=//p')"
second_hash="$(codesign -dvv "$second" 2>&1 | sed -n 's/^CDHash=//p')"
[ -n "$first_hash" ] && [ "$first_hash" != "$second_hash" ]
codesign --verify --strict -R "=$requirement" "$second"
# Same bundle ID with an unrelated ad-hoc signature must NOT satisfy the identity.
codesign --force --sign - "$second" >/dev/null 2>&1
if codesign --verify -R "=$requirement" "$second" >/dev/null 2>&1; then
    echo 'FAIL: unrelated signature accepted' >&2; exit 1
fi
printf 'PASS: different binaries share one certificate-bound identity; unrelated signature rejected\n'
