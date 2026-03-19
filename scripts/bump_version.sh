#!/bin/bash
# Usage: ./scripts/bump_version.sh [major|minor|patch]
# Bumps the marketing version (SemVer) and increments the build number.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Read current versions via agvtool
CURRENT_VERSION=$(xcrun agvtool what-marketing-version -terse 2>/dev/null | head -1)
CURRENT_BUILD=$(xcrun agvtool what-version -terse 2>/dev/null | head -1)

if [[ -z "$CURRENT_VERSION" || -z "$CURRENT_BUILD" ]]; then
    echo "Error: Could not read version from project." >&2
    exit 1
fi

# Split SemVer into components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR=${MAJOR:-0}; MINOR=${MINOR:-0}; PATCH=${PATCH:-0}

COMPONENT="${1:-patch}"
case "$COMPONENT" in
    major)
        MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor)
        MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch)
        PATCH=$((PATCH + 1)) ;;
    *)
        echo "Usage: $0 [major|minor|patch]" >&2
        exit 1 ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "Version: ${CURRENT_VERSION} → ${NEW_VERSION}"
echo "Build:   ${CURRENT_BUILD} → ${NEW_BUILD}"

xcrun agvtool new-marketing-version "$NEW_VERSION"
xcrun agvtool new-version -all "$NEW_BUILD"

echo "Done."
