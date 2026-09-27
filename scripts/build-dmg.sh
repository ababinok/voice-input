#!/bin/bash
# Package an already signed application. No installer or privileged operations.
set -euo pipefail
cd "$(dirname "$0")/.."
app_path="${1:-$PWD/dist/Voice Input.app}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
output_path="${2:-$PWD/dist/Voice-Input-$version-arm64.dmg}"
codesign --verify --deep --strict "$app_path"
mkdir -p .build "$(dirname "$output_path")"
# Build-only dependencies live in the ignored build directory, never in the app.
tools_dir="$PWD/.build/dmg-tools"
if [ ! -x "$tools_dir/bin/python" ]; then python3 -m venv "$tools_dir"; fi
if [ ! -f "$tools_dir/requirements.txt" ] || ! cmp -s scripts/dmg-requirements.txt "$tools_dir/requirements.txt"; then
    "$tools_dir/bin/python" -m pip install --disable-pip-version-check -r scripts/dmg-requirements.txt
    cp scripts/dmg-requirements.txt "$tools_dir/requirements.txt"
fi
staging="$(mktemp -d "$PWD/.build/dmg.XXXXXX")"
verification_mount="$staging/verify"
mounted=false
cleanup() {
    if [ "$mounted" = true ]; then
        hdiutil detach "$verification_mount" -quiet || return
    fi
    rm -rf "$staging"
}
trap cleanup EXIT
swift scripts/make-dmg-background.swift "$staging"
"$tools_dir/bin/dmgbuild" -s scripts/dmg-settings.py \
    -D "app=$app_path" -D "background=$staging/background.png" \
    'Voice Input' "$staging/Voice Input.dmg"
hdiutil verify "$staging/Voice Input.dmg"
# Finder metadata must never alter the signed application bundle.
mkdir "$verification_mount"
hdiutil attach "$staging/Voice Input.dmg" -readonly -nobrowse -noautoopen \
    -mountpoint "$verification_mount" -quiet
mounted=true
codesign --verify --deep --strict "$verification_mount/Voice Input.app"
[ "$(readlink "$verification_mount/Программы")" = /Applications ]
hdiutil detach "$verification_mount" -quiet
mounted=false
mv -f "$staging/Voice Input.dmg" "$output_path"
printf 'DMG: %s\n' "$output_path"
