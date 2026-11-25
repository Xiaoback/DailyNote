# Sourced by the build/check scripts. Never changes the installed toolchain.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
mkdir -p "$BUILD_DIR/module-cache"
export DAILYNOTE_FONT_DIR="$PROJECT_DIR/Resources/Fonts"
SWIFT_FLAGS=(-swift-version 5 -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$BUILD_DIR/module-cache")
TOOLCHAIN_INCLUDE="$(dirname "$(dirname "$(xcrun --find swiftc)")")/include/swift"
if [[ -f "$TOOLCHAIN_INCLUDE/module.modulemap" && -f "$TOOLCHAIN_INCLUDE/bridging.modulemap" ]] && \
   /usr/bin/grep -q 'module SwiftBridging' "$TOOLCHAIN_INCLUDE/module.modulemap"; then
    printf '// Old duplicate SwiftBridging module hidden in this build only.\n' > "$BUILD_DIR/empty.modulemap"
    python3 "$PROJECT_DIR/Scripts/make-overlay.py" "$TOOLCHAIN_INCLUDE/module.modulemap" "$BUILD_DIR"
    SWIFT_FLAGS+=(-vfsoverlay "$BUILD_DIR/toolchain-overlay.json" -Xcc -ivfsoverlay -Xcc "$BUILD_DIR/toolchain-overlay.json")
fi
