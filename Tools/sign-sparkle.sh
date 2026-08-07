#!/bin/bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "usage: $0 <app-path> <code-sign-identity>" >&2
    exit 1
fi

APP="$1"
IDENTITY="$2"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
VERSIONED="$FRAMEWORK/Versions/B"
INSTALLER="$VERSIONED/XPCServices/Installer.xpc"
DOWNLOADER="$VERSIONED/XPCServices/Downloader.xpc"
AUTOUPDATE="$VERSIONED/Autoupdate"
UPDATER="$VERSIONED/Updater.app"

for component in "$INSTALLER" "$DOWNLOADER" "$AUTOUPDATE" "$UPDATER" "$FRAMEWORK" "$APP"; do
    if [[ ! -e "$component" ]]; then
        echo "error: missing release component: $component" >&2
        exit 1
    fi
done

codesign --force --sign "$IDENTITY" --options runtime --timestamp "$INSTALLER"
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
    --preserve-metadata=entitlements "$DOWNLOADER"
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$AUTOUPDATE"
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$UPDATER"
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$FRAMEWORK"
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
    --preserve-metadata=entitlements "$APP"

for component in "$INSTALLER" "$DOWNLOADER" "$AUTOUPDATE" "$UPDATER" "$FRAMEWORK" "$APP"; do
    codesign --verify --strict --verbose=2 "$component"
    metadata="$(codesign --display --verbose=4 "$component" 2>&1)"
    if ! grep -q '^Authority=Developer ID Application:' <<< "$metadata"; then
        echo "error: component is not signed with Developer ID Application: $component" >&2
        exit 1
    fi
    if ! grep -q '^Timestamp=' <<< "$metadata"; then
        echo "error: component has no secure timestamp: $component" >&2
        exit 1
    fi
done

codesign --verify --deep --strict --verbose=2 "$APP"
