#!/bin/bash
#
# Builds LampBoard.app from the SwiftPM executable.
#
# The bundle isn't an affectation: macOS grants the Accessibility and Automation
# permissions to a bundle identity, not to a bare binary. Without a signed .app
# the user would have to re-authorize the app on every rebuild.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP_NAME="LampBoard"
BUNDLE_ID="com.lampboard.app"
# The version comes from the release script when there is one, so a disk
# image cannot carry a number no tag ever had.
VERSION="${LAMPBOARD_VERSION:-0.1.0}"

BUILD_DIR="$ROOT/.build/$CONFIGURATION"
APP_DIR="$ROOT/dist/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

echo "▸ Building ($CONFIGURATION)…"
cd "$ROOT"
swift build -c "$CONFIGURATION" --product LampBoardApp

echo "▸ Assembling the bundle…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/LampBoardApp" "$MACOS_DIR/lampboard"

# The icon is committed, not generated here: a build should not depend on
# Python being present. Scripts/make-icon.py redraws it when the design changes.
# Keeps Spotlight out of the build directory.
#
# `.build` is around 700 MB and every object in it is rewritten on each build.
# Indexed, that is a background process re-reading hundreds of megabytes each
# time somebody compiles, and the cost lands as disk queue rather than CPU:
# the load average climbs while the processor looks idle, and the compositor
# starts missing frames. Measured on this machine at a load average of 87 on
# eight cores, with the processor at 40 per cent.
#
# One empty file, and Spotlight skips the whole tree.
touch "$ROOT/.build/.metadata_never_index" 2>/dev/null || true

ICON="$ROOT/Resources/$APP_NAME.icns"
if [ -f "$ICON" ]; then
    cp "$ICON" "$RESOURCES_DIR/$APP_NAME.icns"
else
    echo "  ⚠ Resources/$APP_NAME.icns is missing: the bundle gets the generic icon."
    echo "     Rebuild it with: python3 Scripts/make-icon.py"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>lampboard</string>
    <key>CFBundleIconFile</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>

    <!-- No Dock icon: it's a widget, not an application you keep open. -->
    <key>LSUIElement</key>
    <true/>

    <!-- Required to drive System Events and bring the VS Code window to the
         front. Without this key macOS blocks the AppleScript. -->
    <key>NSMicrophoneUsageDescription</key>
    <string>lampboard uses the microphone only while you hold the dictation button, to turn what you say into the message you are writing. Nothing is recorded and nothing leaves the Mac.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>lampboard transcribes your dictation on this Mac, using the on-device speech model. No audio is sent anywhere.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>lampboard uses system events to bring the Visual Studio Code window matching the traffic light you clicked to the front.</string>

    <key>NSHumanReadableCopyright</key>
    <string>lampboard</string>
</dict>
</plist>
PLIST

# If a stable signing identity exists, use it: the TCC authorizations survive
# rebuilds, because the requirement hooks onto the identity and not onto the
# binary's hash. Otherwise fall back to the ad-hoc signature, which invalidates
# the permissions on every build (see Scripts/create-signing-identity.sh).
SIGNING_IDENTITY="lampboard Local Signing"

SIGNED_STABLY=0

if security find-certificate -c "$SIGNING_IDENTITY" >/dev/null 2>&1; then
    echo "▸ Signing with the stable identity “${SIGNING_IDENTITY}”…"

    # The signing has to be attempted with a deadline. If the private key isn't
    # authorized for codesign, the command doesn't fail: it hangs waiting for a
    # macOS dialog. A build that never returns is worse than a build that falls
    # back, because it says nothing.
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_DIR" \
        >/dev/null 2>&1 &
    SIGN_PID=$!

    for _ in $(seq 1 20); do
        kill -0 "$SIGN_PID" 2>/dev/null || break
        sleep 1
    done

    if kill -0 "$SIGN_PID" 2>/dev/null; then
        kill "$SIGN_PID" 2>/dev/null || true
        echo "  ⏳ codesign was left waiting on a dialog: falling back to ad-hoc."
        echo "     Look for the macOS window asking for access to the key and"
        echo "     press “Always Allow”, then rebuild."
    elif wait "$SIGN_PID"; then
        SIGNED_STABLY=1
    else
        echo "  ✗ Signing with the stable identity failed: falling back to ad-hoc."
    fi
fi

if [ "$SIGNED_STABLY" = "0" ]; then
    echo "▸ Ad-hoc signing…"
    codesign --force --sign - --timestamp=none "$APP_DIR" 2>/dev/null
fi

echo
echo "✓ $APP_DIR"
echo
echo "  Launch:         open '$APP_DIR'"
echo "  From terminal:  '$MACOS_DIR/lampboard' help"
echo
if [ "$SIGNED_STABLY" = "1" ]; then
    echo "  Stable signature: the Accessibility and Automation authorizations"
    echo "  survive this rebuild and the next ones."
else
    echo "  MIND THE PERMISSIONS: the ad-hoc signature changes on every build, so macOS"
    echo "  treats this as a different app from the one you already authorized."
    echo "  If clicking the traffic lights stops raising the right window:"
    echo
    echo "    System Settings › Privacy & Security › Accessibility"
    echo "      → select lampboard, press '−', then add it back from dist/"
    echo "    System Settings › Privacy & Security › Automation"
    echo "      → lampboard → System Events"
    echo
    echo "  To never do this again:  ./Scripts/create-signing-identity.sh"
fi
echo
echo "  Remember to restart the app: a new bundle does not replace the process"
echo "  that is already running."
echo "    pkill -x lampboard; sleep 1; open '$APP_DIR'"
echo
echo "  Check:  '$MACOS_DIR/lampboard' status"
