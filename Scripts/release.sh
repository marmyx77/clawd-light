#!/bin/bash
#
# Builds the disk image you hand to somebody else.
#
# The script has three honest outcomes and never pretends to have reached a
# better one than it did:
#
#   no certificate      → a disk image that Gatekeeper refuses, useful only to
#                         a tester who knows how to answer it
#   Developer ID        → a signed disk image, still refused on a Mac that has
#                         never seen it: notarization is what lifts that
#   Developer ID + key  → signed, notarized, stapled: it opens with a double
#                         click on a Mac that has never heard of us
#
# Both secrets come from the environment, because this file is public:
#
#   export CLAWD_LIGHT_SIGNING_IDENTITY='Developer ID Application: … (TEAMID)'
#   export CLAWD_LIGHT_NOTARY_PROFILE='clawd-light'
#
# The notarization profile is created once, and lives in the keychain:
#
#   xcrun notarytool store-credentials clawd-light \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific>
#
# An app-specific password is made at appleid.apple.com in two minutes and is
# enough; an App Store Connect API key (--key/--key-id/--issuer) works too and
# is the one to use from a machine nobody logs into.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClawdLight"

# The bundle that gets released is a copy, never the one in dist/. A Developer
# ID signature is a different identity from the local one, and macOS grants
# Accessibility and Automation to an identity: signing dist/ in place would
# silently revoke the permissions of the app you are running right now.
BUILT="$ROOT/dist/$APP_NAME.app"
APP_DIR="$ROOT/.build/release-app/$APP_NAME.app"

# The number travels from the git tag, so a disk image cannot claim a version
# that no commit carries. An explicit argument wins, for a dry run.
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
VERSION="${VERSION:-0.1.0}"

DMG="$ROOT/dist/$APP_NAME-$VERSION.dmg"
IDENTITY="${CLAWD_LIGHT_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${CLAWD_LIGHT_NOTARY_PROFILE:-}"

# How long Apple gets before we call it a failure.
#
# `--wait` on its own waits for ever, and that is not a theoretical problem:
# measured once, a disk image submission printed "initiating connection to the
# Apple notary service" and then held the terminal for two and a half hours,
# never reaching the queue — the submission does not even appear in
# `notarytool history`. Notarization normally takes one to five minutes, so
# twenty is generous and a hang stops looking like patience.
NOTARY_DEADLINE="${CLAWD_LIGHT_NOTARY_TIMEOUT:-20m}"

# One Developer ID in the keychain is unambiguous, so we use it without being
# told. Several are a choice that belongs to the person releasing, not to us.
if [ -z "$IDENTITY" ]; then
    MATCHES="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep 'Developer ID Application' || true)"
    COUNT="$(printf '%s' "$MATCHES" | grep -c . || true)"
    if [ "$COUNT" = "1" ]; then
        IDENTITY="$(printf '%s\n' "$MATCHES" | sed -n 's/.*"\(.*\)".*/\1/p')"
    elif [ "$COUNT" -gt 1 ]; then
        echo "▸ Several Developer ID certificates are installed:"
        printf '%s\n' "$MATCHES"
        echo
        echo "  Say which one:  export CLAWD_LIGHT_SIGNING_IDENTITY='Developer ID Application: …'"
        exit 1
    fi
fi

echo "▸ clawd-light $VERSION"
echo

CLAWD_LIGHT_VERSION="$VERSION" "$ROOT/Scripts/build-app.sh" release >/dev/null
rm -rf "$ROOT/.build/release-app"
mkdir -p "$ROOT/.build/release-app"
cp -R "$BUILT" "$APP_DIR"
echo "▸ Bundle built and copied aside."

# ---------------------------------------------------------------------------
# Signature
# ---------------------------------------------------------------------------
#
# Two entitlements, and no more. The hardened runtime is what notarization
# requires, and by default it takes away exactly the two things this app does
# for a living: talking to other applications and listening to the microphone.
ENTITLEMENTS="$ROOT/.build/clawd-light.entitlements"
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Raising the window of the session you clicked: AppleScript towards
         Terminal, iTerm2, Ghostty, System Events. Without this the hardened
         runtime denies every Apple Event and the click does nothing. -->
    <key>com.apple.security.automation.apple-events</key>
    <true/>

    <!-- Dictation, held down on the button. The Info.plist string explains it
         to the user; this entitlement is what lets the runtime allow it. -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
PLIST

if [ -n "$IDENTITY" ]; then
    echo "▸ Signing with “${IDENTITY}”…"
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_DIR"
    codesign --verify --deep --strict "$APP_DIR"
else
    echo "▸ No Developer ID certificate: the local signature stays on."
fi

# ---------------------------------------------------------------------------
# Notarization of the app
# ---------------------------------------------------------------------------
#
# The app is notarized before the disk image and stapled on its own, so that
# the copy dragged out of the image carries its own ticket and opens even on a
# Mac that is offline.
NOTARIZED=0
if [ -n "$IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
    ZIP="$ROOT/.build/$APP_NAME-$VERSION.zip"
    ditto -c -k --keepParent "$APP_DIR" "$ZIP"
    echo "▸ Notarizing the app (Apple takes a few minutes)…"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" \
        --wait --timeout "$NOTARY_DEADLINE"
    xcrun stapler staple "$APP_DIR"
    rm -f "$ZIP"
    NOTARIZED=1
fi

# ---------------------------------------------------------------------------
# Disk image
# ---------------------------------------------------------------------------
STAGE="$ROOT/.build/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "▸ Building the disk image…"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
fi

if [ "$NOTARIZED" = "1" ]; then
    echo "▸ Notarizing the disk image…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" \
        --wait --timeout "$NOTARY_DEADLINE"
    xcrun stapler staple "$DMG"
fi

# ---------------------------------------------------------------------------
# What Gatekeeper actually says
# ---------------------------------------------------------------------------
#
# Not our opinion of the signature: the verdict of the same service that will
# decide on somebody else's Mac, asked here before the file leaves.
echo
echo "▸ Gatekeeper, asked here:"
spctl -a -vvv -t exec "$APP_DIR" 2>&1 | sed 's/^/    app: /' || true
spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 \
    | sed 's/^/    dmg: /' || true

echo
echo "✓ $DMG"
echo
if [ "$NOTARIZED" = "1" ]; then
    echo "  Notarized and stapled: it opens with a double click on any Mac."
    echo "  Publish:  gh release create v$VERSION '$DMG' --title 'clawd-light $VERSION'"
elif [ -n "$IDENTITY" ]; then
    echo "  Signed but not notarized: on a Mac that has never seen it, macOS"
    echo "  will still refuse the first launch. Set the profile and run again:"
    echo "    export CLAWD_LIGHT_NOTARY_PROFILE='clawd-light'"
else
    echo "  Signed locally only. On somebody else's Mac this image is refused;"
    echo "  the way through, for a tester who accepts it knowingly, is"
    echo "  right-click on the app › Open, then Open again in the dialog."
    echo "  For a public release you need a Developer ID certificate:"
    echo "    export CLAWD_LIGHT_SIGNING_IDENTITY='Developer ID Application: … (TEAMID)'"
fi
echo
