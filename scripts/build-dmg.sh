#!/bin/bash
# Package an already signed application. No installer or privileged operations.
set -euo pipefail
cd "$(dirname "$0")/.."
app_path="${1:-$PWD/dist/Voice Input.app}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
output_path="${2:-$PWD/dist/Voice-Input-$version-arm64.dmg}"
codesign --verify --deep --strict "$app_path"
mkdir -p .build "$(dirname "$output_path")"
staging="$(mktemp -d "$PWD/.build/dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/contents"
ditto "$app_path" "$staging/contents/Voice Input.app"
ln -s /Applications "$staging/contents/Applications"
cp docs/INSTALL.txt "$staging/contents/Как установить.txt"
hdiutil create -volname 'Voice Input' -srcfolder "$staging/contents" -format UDZO -ov "$staging/Voice Input.dmg"
hdiutil verify "$staging/Voice Input.dmg"
mv -f "$staging/Voice Input.dmg" "$output_path"
printf 'DMG: %s\n' "$output_path"
