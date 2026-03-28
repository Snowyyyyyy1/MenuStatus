#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Stop existing instance
pkill -x MenuStatus 2>/dev/null && sleep 1 || true

echo "==> Generating Xcode project..."
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

echo "==> Building..."
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build \
    -scheme MenuStatus \
    -configuration Debug \
    -derivedDataPath .build

echo "==> Launching..."
APP_PATH=$(find .build -name "MenuStatus.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
    echo "Error: MenuStatus.app not found in .build"
    exit 1
fi
open "$APP_PATH"
echo "==> MenuStatus is running"
