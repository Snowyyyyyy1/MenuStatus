#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MenuStatus"
DERIVED=".build"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
DMG_STAGING_DIR="$OUTPUT_DIR/dmg-root"
USE_CREATE_DMG="${USE_CREATE_DMG:-0}"

cleanup() {
    rm -rf "$DMG_STAGING_DIR"
}

require_value() {
    local name="$1"
    local value="$2"
    if [ -z "$value" ]; then
        echo "Error: $name must be set for release packaging."
        exit 1
    fi
}

normalize_metadata_value() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

read_plist_value() {
    local plist="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist"
}

validate_release_metadata() {
    local app_path="$1"
    local plist="$app_path/Contents/Info.plist"
    local actual_version
    local actual_build
    local actual_feed_url
    local actual_public_key

    actual_version="$(normalize_metadata_value "$(read_plist_value "$plist" CFBundleShortVersionString)")"
    actual_build="$(normalize_metadata_value "$(read_plist_value "$plist" CFBundleVersion)")"
    actual_feed_url="$(normalize_metadata_value "$(read_plist_value "$plist" SUFeedURL)")"
    actual_public_key="$(normalize_metadata_value "$(read_plist_value "$plist" SUPublicEDKey)")"

    if [ "$actual_version" != "$MENU_STATUS_VERSION" ]; then
        echo "Error: CFBundleShortVersionString is '$actual_version' but expected '$MENU_STATUS_VERSION'."
        exit 1
    fi

    if [ "$actual_build" != "$MENU_STATUS_BUILD" ]; then
        echo "Error: CFBundleVersion is '$actual_build' but expected '$MENU_STATUS_BUILD'."
        exit 1
    fi

    if [ "$actual_feed_url" != "$MENU_STATUS_FEED_URL" ]; then
        echo "Error: SUFeedURL is '$actual_feed_url' but expected '$MENU_STATUS_FEED_URL'."
        exit 1
    fi

    if [ "$actual_public_key" != "$MENU_STATUS_PUBLIC_ED_KEY" ]; then
        echo "Error: SUPublicEDKey does not match the configured release key."
        exit 1
    fi
}

if [ "${PACKAGE_APP_SOURCE_ONLY:-0}" = "1" ]; then
    if [ "${BASH_SOURCE[0]}" != "$0" ]; then
        return 0
    fi
    exit 0
fi

VERSION="$(normalize_metadata_value "${1:-${MENU_STATUS_VERSION:-${RELEASE_VERSION:-0.0.0-dev}}}")"
BUILD_NUMBER="$(normalize_metadata_value "${MENU_STATUS_BUILD:-0}")"
FEED_URL="$(normalize_metadata_value "${MENU_STATUS_FEED_URL:-}")"
PUBLIC_ED_KEY="$(normalize_metadata_value "${MENU_STATUS_PUBLIC_ED_KEY:-}")"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"

export MENU_STATUS_VERSION="$VERSION"
export MENU_STATUS_BUILD="$BUILD_NUMBER"
export MENU_STATUS_FEED_URL="$FEED_URL"
export MENU_STATUS_PUBLIC_ED_KEY="$PUBLIC_ED_KEY"
export TUIST_APP_VERSION="$MENU_STATUS_VERSION"
export TUIST_APP_BUILD="$MENU_STATUS_BUILD"
export TUIST_APP_FEED_URL="$MENU_STATUS_FEED_URL"
export TUIST_APP_PUBLIC_ED_KEY="$MENU_STATUS_PUBLIC_ED_KEY"

trap cleanup EXIT

require_value "MENU_STATUS_VERSION" "$MENU_STATUS_VERSION"
require_value "MENU_STATUS_BUILD" "$MENU_STATUS_BUILD"
require_value "MENU_STATUS_FEED_URL" "$MENU_STATUS_FEED_URL"
require_value "MENU_STATUS_PUBLIC_ED_KEY" "$MENU_STATUS_PUBLIC_ED_KEY"

echo "==> Generating Xcode project..."
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

echo "==> Building Release..."
echo "    Version: $MENU_STATUS_VERSION ($MENU_STATUS_BUILD)"
xcodebuild build \
    -workspace MenuStatus.xcworkspace \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -quiet

APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    APP_PATH=$(find "$DERIVED" -path "*/Build/Products/Release/$APP_NAME.app" -type d | head -1)
fi
if [ -z "$APP_PATH" ]; then
    echo "Error: $APP_NAME.app not found in $DERIVED"
    exit 1
fi

echo "==> Found app at $APP_PATH"
echo "==> Validating release metadata..."
validate_release_metadata "$APP_PATH"
mkdir -p "$OUTPUT_DIR"

# Sign if identity is available (optional)
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -n "$IDENTITY" ]; then
    echo "==> Signing with: $IDENTITY"
    codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP_PATH"
fi

# Stage a standard drag-to-Applications DMG payload.
rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_PATH" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

rm -f "$DMG_PATH"
if [ "$USE_CREATE_DMG" = "1" ] && command -v create-dmg &>/dev/null; then
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
        "$DMG_STAGING_DIR"

    echo "==> DMG created: $DMG_PATH"
else
    echo "==> Creating plain DMG with hdiutil..."
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_STAGING_DIR" \
        -ov \
        -format UDZO \
        "$DMG_PATH"
    echo "==> DMG created: $DMG_PATH"
fi

# Notarize if credentials are available (optional)
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"

if [ -n "$IDENTITY" ] && [ -n "$NOTARIZE_PROFILE" ]; then
    echo "==> Submitting for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARIZE_PROFILE" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    echo "==> Notarization complete"
elif [ -n "$IDENTITY" ] && [ -n "$APPLE_ID" ] && [ -n "$APPLE_APP_SPECIFIC_PASSWORD" ] && [ -n "$APPLE_TEAM_ID" ]; then
    echo "==> Submitting for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    echo "==> Notarization complete"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "artifact_path=$DMG_PATH" >> "$GITHUB_OUTPUT"
    echo "artifact_name=$(basename "$DMG_PATH")" >> "$GITHUB_OUTPUT"
    echo "version=$VERSION" >> "$GITHUB_OUTPUT"
    echo "build_number=$BUILD_NUMBER" >> "$GITHUB_OUTPUT"
fi

echo "==> Done! Output in $OUTPUT_DIR/"
