#!/bin/bash
set -euo pipefail
VELOX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VELOX_BUILD="${VELOX_BUILD_DIR:-$VELOX_ROOT/.build}"
mkdir -p "$VELOX_BUILD/cache" "$VELOX_BUILD/config" "$VELOX_BUILD/security" "$VELOX_BUILD/modules"
export CLANG_MODULE_CACHE_PATH="$VELOX_BUILD/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$VELOX_BUILD/modules"
swift build -c release --package-path "$VELOX_ROOT" --scratch-path "$VELOX_BUILD" --cache-path "$VELOX_BUILD/cache" --config-path "$VELOX_BUILD/config" --security-path "$VELOX_BUILD/security" --disable-sandbox
VELOX_BIN="$(swift build -c release --package-path "$VELOX_ROOT" --scratch-path "$VELOX_BUILD" --show-bin-path)"
VELOSHIFT_OUTPUT="${VELOSHIFT_OUTPUT_DIR:-$VELOX_ROOT/dist}"
VELOX_APP="$VELOSHIFT_OUTPUT/Veloshift.app"
mkdir -p "$VELOX_APP/Contents/MacOS" "$VELOX_APP/Contents/Resources"
cp "$VELOX_BIN/Veloshift" "$VELOX_APP/Contents/MacOS/Veloshift"
strip -S "$VELOX_APP/Contents/MacOS/Veloshift"
cp "$VELOX_ROOT/scripts/Info.plist" "$VELOX_APP/Contents/Info.plist"
if [ -f "$VELOX_ROOT/scripts/AppIcon.icns" ]; then cp "$VELOX_ROOT/scripts/AppIcon.icns" "$VELOX_APP/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign - "$VELOX_APP"
codesign --verify --deep --strict "$VELOX_APP"
printf '\nBuilt: %s\n' "$VELOX_APP"
