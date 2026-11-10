#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-Waifu2x}"
OUT="${2:-$ROOT/dist/screenshot.png}"

WINDOW_ID="$(swift "$ROOT/Scripts/window-id.swift" "$NAME")" || {
    echo "Window not found for '$NAME'. Launch the app first." >&2
    exit 1
}

mkdir -p "$(dirname "$OUT")"
# Capture only the app window, never the whole screen.
screencapture -x -o -l"$WINDOW_ID" "$OUT"
echo "$OUT"
