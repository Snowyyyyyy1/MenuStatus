#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-0.1.0}"
APP_NAME="MenuStatus"
DERIVED=".build"
OUTPUT_DIR="dist"

echo "==> Generating Xcode project..."
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

echo "==> Building Release..."
xcodebuild build \
    -workspace "$APP_NAME.xcworkspace" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -quiet

APP_PATH=$(find "$DERIVED" -name "$APP_NAME.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
    echo "Error: $APP_NAME.app not found in $DERIVED"
    exit 1
fi

echo "==> Found app at $APP_PATH"
mkdir -p "$OUTPUT_DIR"

# Sign if identity is available (optional)
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -n "$IDENTITY" ]; then
    echo "==> Signing with: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" "$APP_PATH"
fi

# Create DMG if create-dmg is installed, otherwise fall back to ZIP
if command -v create-dmg &>/dev/null; then
    DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"
    rm -f "$DMG_PATH"

    echo "==> Creating DMG..."
    create-dmg \
        --volname "$APP_NAME" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 150 190 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 450 190 \
        "$DMG_PATH" \
        "$APP_PATH"

    echo "==> DMG created: $DMG_PATH"
else
    ZIP_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.zip"
    echo "==> create-dmg not found, creating ZIP instead..."
    echo "    Install with: brew install create-dmg"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    echo "==> ZIP created: $ZIP_PATH"
fi

# Notarize if credentials are available (optional)
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-}"
if [ -n "$IDENTITY" ] && [ -n "$NOTARIZE_PROFILE" ]; then
    ARTIFACT="$OUTPUT_DIR/$APP_NAME-$VERSION."*
    echo "==> Submitting for notarization..."
    xcrun notarytool submit $ARTIFACT \
        --keychain-profile "$NOTARIZE_PROFILE" \
        --wait
    xcrun stapler staple "$APP_PATH"
    echo "==> Notarization complete"
fi

echo "==> Done! Output in $OUTPUT_DIR/"
