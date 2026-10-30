#!/bin/bash
set -euo pipefail

VELOSHIFT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VELOSHIFT_DIST="${VELOSHIFT_OUTPUT_DIR:-$VELOSHIFT_ROOT/dist}"
export VELOSHIFT_OUTPUT_DIR="$VELOSHIFT_DIST"
bash "$VELOSHIFT_ROOT/scripts/build-app.sh"

VELOSHIFT_BUILD="${VELOX_BUILD_DIR:-$VELOSHIFT_ROOT/.build}"
VELOSHIFT_BIN="$(swift build -c release --package-path "$VELOSHIFT_ROOT" --scratch-path "$VELOSHIFT_BUILD" --show-bin-path)"
"$VELOSHIFT_BIN/VeloxChecks"

VELOSHIFT_APP="$VELOSHIFT_DIST/Veloshift.app"
VELOSHIFT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$VELOSHIFT_APP/Contents/Info.plist")"
VELOSHIFT_ARCH="$(lipo -archs "$VELOSHIFT_APP/Contents/MacOS/Veloshift")"
case "$VELOSHIFT_ARCH" in
    arm64|x86_64) ;;
    *) printf 'Expected a native arm64 or x86_64 build; got: %s\n' "$VELOSHIFT_ARCH" >&2; exit 1 ;;
esac

VELOSHIFT_STAGE="$(mktemp -d "$VELOSHIFT_BUILD/release-stage.XXXXXX")"
trap 'rm -rf "$VELOSHIFT_STAGE"' EXIT
mkdir -p "$VELOSHIFT_STAGE/Veloshift"
ditto "$VELOSHIFT_APP" "$VELOSHIFT_STAGE/Veloshift/Veloshift.app"
cat > "$VELOSHIFT_STAGE/Veloshift/INSTALL.txt" <<'INSTALL'
Veloshift preview — macOS 14 or newer

Quit any older Velox or Veloshift instance. Move Veloshift.app to Applications.
Open the app, connect the KICKR v5 and Click 2, and start the bridge. In Zwift,
pair Veloshift KICKR v5 with the network icon for Power, Resistance and Cadence.
Both apps must run on the same Mac. Allow Bluetooth and Local Network access.

This preview is locally ad-hoc signed, not Developer ID signed or notarized.
If macOS blocks it, review Apple's instructions and use the per-app Open Anyway
option in System Settings > Privacy & Security only if you trust this download:
https://support.apple.com/en-us/102445

Default keyboard controls: [ easier / ] harder; optional J / K in rider settings.
Keyboard keys are reserved in the Zwift game, including chat, while enabled.
Click 2 may need unlocking in official Zwift; the right-only fallback uses B/+.
Commands are limited to 1,000 W. Use the bridge only on a trusted local network.
This is an independent experimental project with limited hardware testing.
Read the repository README and release notes for setup and remaining limits.
INSTALL
if [ -f "$VELOSHIFT_ROOT/LICENSE" ]; then
    cp "$VELOSHIFT_ROOT/LICENSE" "$VELOSHIFT_STAGE/Veloshift/LICENSE"
fi
if [ -f "$VELOSHIFT_ROOT/NOTICE.md" ]; then
    cp "$VELOSHIFT_ROOT/NOTICE.md" "$VELOSHIFT_STAGE/Veloshift/NOTICE.md"
fi

VELOSHIFT_ZIP="Veloshift-$VELOSHIFT_VERSION-macOS-$VELOSHIFT_ARCH.zip"
ditto -c -k --sequesterRsrc --keepParent "$VELOSHIFT_STAGE/Veloshift" "$VELOSHIFT_DIST/$VELOSHIFT_ZIP"
(cd "$VELOSHIFT_DIST" && shasum -a 256 "$VELOSHIFT_ZIP" > "$VELOSHIFT_ZIP.sha256")
printf '\nRelease: %s/%s\n' "$VELOSHIFT_DIST" "$VELOSHIFT_ZIP"
