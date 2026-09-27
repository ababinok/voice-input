#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(uname -m)" != arm64 ]; then
    echo 'This release build requires an Apple Silicon Mac.' >&2
    exit 1
fi
app_dir="$PWD/dist/Voice Input.app"
# Replacing a running executable breaks the process's code-signing identity.
if pgrep -f -x "$app_dir/Contents/MacOS/VoiceInput" >/dev/null; then
    echo 'Close Voice Input before rebuilding it. The installed app was not changed.' >&2
    exit 1
fi
swift build -c release -j 4
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p .build dist
staging_root="$(mktemp -d "$PWD/.build/app-package.XXXXXX")"
trap 'rm -rf "$staging_root"' EXIT
staged_app="$staging_root/Voice Input.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/VoiceInput" "$staged_app/Contents/MacOS/VoiceInput"
# SwiftPM resource bundles must remain next to the executable.
for bundle in "$binary_dir/"*.bundle; do
    [ -d "$bundle" ] && ditto "$bundle" "$staged_app/Contents/MacOS/$(basename "$bundle")"
done
cp assets/AppIcon.icns "$staged_app/Contents/Resources/AppIcon.icns"
cp scripts/Info.plist "$staged_app/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md "$staged_app/Contents/Resources/THIRD_PARTY_NOTICES.md"
./scripts/sign-app.sh "$staged_app"
# Prepare everything before replacing the previous, working package.
ditto -c -k --sequesterRsrc --keepParent "$staged_app" "$staging_root/Voice-Input-macOS-arm64.zip"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)"
dmg_name="Voice-Input-$version-arm64.dmg"
./scripts/build-dmg.sh "$staged_app" "$staging_root/$dmg_name"
if [ -d "$app_dir" ]; then mv "$app_dir" "$staging_root/previous.app"; fi
if ! mv "$staged_app" "$app_dir"; then
    [ ! -d "$staging_root/previous.app" ] || mv "$staging_root/previous.app" "$app_dir"
    exit 1
fi
mv -f "$staging_root/Voice-Input-macOS-arm64.zip" "$PWD/dist/Voice-Input-macOS-arm64.zip"
mv -f "$staging_root/$dmg_name" "$PWD/dist/$dmg_name"
printf 'Built: %s\n' "$app_dir"
