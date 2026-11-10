#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="$ROOT/dist/Waifu2x.app"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/Waifu2x" "$APP/Contents/MacOS/Waifu2x"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SwiftPM resource bundle (contains Resources/Models).
if [[ -d "$BIN_PATH/Waifu2x_Waifu2x.bundle" ]]; then
    cp -R "$BIN_PATH/Waifu2x_Waifu2x.bundle" "$APP/Contents/Resources/"
fi

if [[ -f "$ROOT/Assets/AppIcon.icns" ]]; then
    cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Localized resources. Missing directories must not fail the build.
if [[ -d "$ROOT/Support/Resources" ]]; then
    find "$ROOT/Support/Resources" -maxdepth 1 -name '*.lproj' -type d -exec cp -R {} "$APP/Contents/Resources/" \;
fi

if [[ -f "$ROOT/THIRD_PARTY_NOTICES.md" ]]; then
    cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
fi

# Ad-hoc signature is enough for a locally built app.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built: $APP"
