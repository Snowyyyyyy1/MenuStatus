#!/bin/bash
set -euo pipefail

# Generate Sparkle EdDSA key pair (one-time setup).
# Private key is stored in macOS Keychain.
# Public key is printed — copy it into Project.swift SUPublicEDKey.

cd "$(dirname "$0")/.."

SPARKLE_BIN="Tuist/.build/artifacts/sparkle/Sparkle/bin"

if [ ! -f "$SPARKLE_BIN/generate_keys" ]; then
    echo "Error: Sparkle tools not found. Run 'tuist install' first."
    exit 1
fi

echo "==> Generating Sparkle EdDSA key pair..."
echo "    Private key will be stored in your macOS Keychain."
echo ""

"$SPARKLE_BIN/generate_keys"

echo ""
echo "==> Done! Copy the public key above into Project.swift:"
echo '    "SUPublicEDKey": .string("YOUR_PUBLIC_KEY_HERE")'
