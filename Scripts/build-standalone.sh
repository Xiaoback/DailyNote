#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
python3 "$PROJECT_DIR/Scripts/download-fonts.py"
RELEASE_DIR="$PROJECT_DIR/build/standalone"
APP_DIR="$RELEASE_DIR/DailyNote.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/Fonts" "$RELEASE_DIR/module-cache"
SOURCES=()
for SOURCE_FILE in "$PROJECT_DIR"/Sources/Shared/*.swift; do
    if [[ "$(basename "$SOURCE_FILE")" != "NoteIntents.swift" ]]; then
        SOURCES+=("$SOURCE_FILE")
    fi
done
SOURCES+=("$PROJECT_DIR"/Sources/App/*.swift)
for ARCHITECTURE in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -O -parse-as-library -D DAILYNOTE_STANDALONE \
        -sdk "$(xcrun --show-sdk-path)" -target "$ARCHITECTURE-apple-macosx14.0" \
        -module-cache-path "$RELEASE_DIR/module-cache" -module-name DailyNote \
        "${SOURCES[@]}" -o "$RELEASE_DIR/DailyNote-$ARCHITECTURE"
done
xcrun lipo -create "$RELEASE_DIR/DailyNote-arm64" "$RELEASE_DIR/DailyNote-x86_64" -output "$APP_DIR/Contents/MacOS/DailyNote"
python3 "$PROJECT_DIR/Scripts/make-standalone-plist.py" "$APP_DIR"
cp "$PROJECT_DIR"/Resources/Fonts/*.ttf "$PROJECT_DIR/Resources/Fonts/OFL.txt" "$APP_DIR/Contents/Resources/Fonts/"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP_DIR"
codesign --verify --strict "$APP_DIR"
xcrun lipo -archs "$APP_DIR/Contents/MacOS/DailyNote"
printf 'Standalone application: %s\n' "$APP_DIR"
