#!/bin/bash
set -euo pipefail

# Full release flow:
# 1. Build Release app
# 2. Package as ZIP (Sparkle-compatible)
# 3. Sign with Sparkle EdDSA
# 4. Create GitHub Release with artifact
# 5. Generate appcast.xml
# 6. Commit and push appcast

cd "$(dirname "$0")/.."

VERSION="${1:?Usage: ./Scripts/release.sh <version>}"
APP_NAME="MenuStatus"
SPARKLE_BIN="Tuist/.build/artifacts/sparkle/Sparkle/bin"
DIST_DIR="dist"
APPCAST_DIR="appcast"

# Validate
if [ ! -f "$SPARKLE_BIN/generate_appcast" ]; then
    echo "Error: Sparkle tools not found. Run 'tuist install' first."
    exit 1
fi

if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI (gh) not found. Install with: brew install gh"
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Error: Working tree is not clean. Commit or stash changes first."
    exit 1
fi

# Build
echo "==> Building Release..."
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath .build

APP_PATH=$(find .build -name "$APP_NAME.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
    echo "Error: $APP_NAME.app not found"
    exit 1
fi

# Optional codesign
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -n "$IDENTITY" ]; then
    echo "==> Signing with: $IDENTITY"
    codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP_PATH"
fi

# Package as ZIP (Sparkle expects ZIP)
mkdir -p "$DIST_DIR"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION.zip"
rm -f "$ZIP_PATH"
echo "==> Creating ZIP..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Sign with Sparkle EdDSA
echo "==> Signing ZIP with Sparkle EdDSA..."
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$ZIP_PATH")
echo "    Signature: $SIGNATURE"

# Tag and release
echo "==> Creating git tag v$VERSION..."
git tag "v$VERSION"
git push origin "v$VERSION"

echo "==> Creating GitHub Release..."
gh release create "v$VERSION" "$ZIP_PATH" \
    --title "$APP_NAME v$VERSION" \
    --generate-notes

# Generate appcast
DOWNLOAD_PREFIX="https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/download"
mkdir -p "$APPCAST_DIR"
cp "$ZIP_PATH" "$APPCAST_DIR/"

echo "==> Generating appcast.xml..."
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "$DOWNLOAD_PREFIX/v$VERSION/" \
    "$APPCAST_DIR"

# Copy appcast to repo root for hosting
cp "$APPCAST_DIR/appcast.xml" appcast.xml

echo "==> Committing appcast.xml..."
git add appcast.xml
git commit -m "chore: update appcast.xml for v$VERSION"
git push

# Cleanup
rm -rf "$APPCAST_DIR"

echo ""
echo "==> Release v$VERSION complete!"
echo "    GitHub Release: $(gh release view "v$VERSION" --json url -q .url)"
echo ""
echo "    Make sure SUFeedURL in Project.swift points to:"
echo "    https://raw.githubusercontent.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/main/appcast.xml"
