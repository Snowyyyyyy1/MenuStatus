#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Stop existing instance
pkill -x MenuStatus 2>/dev/null && sleep 1 || true

echo "==> Generating Xcode project..."
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

echo "==> Building..."
xcodebuild build \
    -workspace MenuStatus.xcworkspace \
    -scheme MenuStatus \
    -configuration Debug \
    -derivedDataPath .build \
    -quiet

echo "==> Launching..."
APP_PATH=".build/Build/Products/Debug/MenuStatus.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Debug MenuStatus.app not found at $APP_PATH"
    exit 1
fi
open -n "$APP_PATH"
echo "==> MenuStatus is running"
