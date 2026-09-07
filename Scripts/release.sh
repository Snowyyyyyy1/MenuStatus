#!/bin/bash
set -euo pipefail

# Release entry point. The GitHub Actions workflow owns build, packaging,
# signing, notarization, GitHub Release, and appcast generation. This local
# wrapper only validates the release preconditions and pushes the tag that
# starts that workflow, so local and CI release artifacts cannot diverge.

cd "$(dirname "$0")/.."

VERSION="${1:?Usage: ./Scripts/release.sh <version>}"
TAG="v$VERSION"

if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(alpha|beta|rc)(\.[0-9A-Za-z-]+)*)?$ ]]; then
    echo "Error: invalid or unsupported version '$VERSION'. Expected SemVer such as 0.1.16, 0.1.16-beta.1, or 0.1.16-rc.1." >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: working tree is not clean. Commit or stash changes first." >&2
    exit 1
fi

if [[ "$(git branch --show-current)" != "main" ]]; then
    echo "Error: release tags must be created from the main branch." >&2
    exit 1
fi

if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
    echo "Error: tag $TAG already exists locally." >&2
    exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
    echo "Error: git remote 'origin' is not configured." >&2
    exit 1
fi

if git ls-remote --exit-code --refs origin "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "Error: tag $TAG already exists on origin." >&2
    exit 1
fi

echo "==> Pushing $TAG to origin..."
git push origin "HEAD:refs/tags/$TAG"

echo ""
echo "==> Release workflow started for $TAG."
echo "    Build, packaging, signing, notarization, GitHub Release, and appcast are handled by GitHub Actions."
