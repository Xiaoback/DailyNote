#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/swift-environment.sh"
SWIFT_FLAGS+=(-D DAILYNOTE_STANDALONE)
python3 "$PROJECT_DIR/Scripts/download-fonts.py"
xcrun swiftc "${SWIFT_FLAGS[@]}" -parse-as-library \
    "$PROJECT_DIR"/Sources/Shared/*.swift \
    "$PROJECT_DIR/Sources/App/NoteTextView.swift" "$PROJECT_DIR/Sources/App/NoteViewModel.swift" \
    "$PROJECT_DIR/Sources/App/QuickNoteLayout.swift" \
    "$PROJECT_DIR/Sources/App/HotCornerState.swift" \
    "$PROJECT_DIR/Sources/App/HoverDismissState.swift" \
    "$PROJECT_DIR/Tests/CoreTests.swift" -o "$BUILD_DIR/CoreTests"
"$BUILD_DIR/CoreTests"
