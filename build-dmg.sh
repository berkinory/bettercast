#!/bin/bash
# Build a release DMG. Usage: ./build-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

IDENTITY="${DEVELOPER_ID_IDENTITY:-Developer ID Application}"
TEAM_ID="${DEVELOPMENT_TEAM:-Z66C58Z3RC}"
NOTARY_PROFILE="${NOTARY_PROFILE:-bettercast-notary}"
DERIVED="build/DerivedData"
SKIP_SIGNING="${SKIP_SIGNING:-0}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"
VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\([^"]*\)".*/\1/p' project.yml | head -n1)"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: project.yml must define MARKETING_VERSION as x.y.z; got '$VERSION'" >&2
    exit 1
fi

if [[ "$SKIP_SIGNING" == "1" ]]; then
    echo "▸ Building unsigned Bettercast.app (Release)…"
    SKIP_NOTARIZATION=1
    BUILD_SETTINGS=(
        CODE_SIGNING_ALLOWED=NO
        CODE_SIGN_STYLE=Manual
    )
else
    if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
        echo "error: '$IDENTITY' code-signing identity not found — create it in the Apple Developer portal." >&2
        exit 1
    fi
    echo "▸ Building Developer ID-signed Bettercast.app (Release)…"
    BUILD_SETTINGS=(
        CODE_SIGNING_ALLOWED=YES
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="$IDENTITY"
        DEVELOPMENT_TEAM="$TEAM_ID"
        OTHER_CODE_SIGN_FLAGS="--timestamp"
    )
fi

xcodebuild -project Bettercast.xcodeproj -scheme Bettercast -configuration Release \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$VERSION" \
    "${BUILD_SETTINGS[@]}" \
    build

APP="$DERIVED/Build/Products/Release/Bettercast.app"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
DMG="build/Bettercast-${VERSION}.dmg"

if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
    codesign --verify --deep --strict --verbose=2 "$APP"
    echo "▸ Submitting app for notarization…"
    ZIP="$STAGE/Bettercast-${VERSION}.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 1h
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
else
    echo "⚠ signing or notarization skipped; do not distribute this artifact"
fi

echo "▸ Packaging ${DMG}"
rm -f "$DMG"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
diskutil image create from "$STAGE" --format UDZO --volumeName "Bettercast" "$DMG" >/dev/null

if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
    spctl --assess --type execute --verbose=4 "$APP"
fi

echo "✓ $DMG"
