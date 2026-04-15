#!/bin/bash
set -euo pipefail

# Generate Sparkle EdDSA key pair (one-time setup).
# Private key is stored in macOS Keychain.
# Public key is printed — copy it into the SPARKLE_PUBLIC_ED_KEY GitHub secret
# and MENU_STATUS_PUBLIC_ED_KEY environment variable for release packaging.

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
echo "==> Done! Save the public key above in your release configuration:"
echo "    GitHub secret: SPARKLE_PUBLIC_ED_KEY"
echo "    Local env var: MENU_STATUS_PUBLIC_ED_KEY"
