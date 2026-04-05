#!/bin/bash
# Usage: ./scripts/bump_version.sh [major|minor|patch]
# Bumps the marketing version (SemVer) and increments the build number.
# Edits project.pbxproj directly — avoids agvtool which breaks on
# projects where Info.plist uses $(MARKETING_VERSION) variable references.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PBXPROJ="$PROJECT_DIR/BeNeM.xcodeproj/project.pbxproj"

if [[ ! -f "$PBXPROJ" ]]; then
    echo "Error: project.pbxproj not found at $PBXPROJ" >&2
    exit 1
fi

# Read current values directly from project.pbxproj
CURRENT_VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/;//;s/ *//')
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/;//;s/ *//')

if [[ -z "$CURRENT_VERSION" || -z "$CURRENT_BUILD" ]]; then
    echo "Error: Could not read version from $PBXPROJ" >&2
    exit 1
fi

# Split SemVer into components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR=${MAJOR:-0}; MINOR=${MINOR:-0}; PATCH=${PATCH:-0}

COMPONENT="${1:-patch}"
case "$COMPONENT" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
    *)
        echo "Usage: $0 [major|minor|patch]" >&2
        exit 1 ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "Version: ${CURRENT_VERSION} → ${NEW_VERSION}"
echo "Build:   ${CURRENT_BUILD} → ${NEW_BUILD}"

# Update project.pbxproj in-place (perl handles macOS in-place cleanly)
perl -pi -e "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${NEW_VERSION};/g" "$PBXPROJ"
perl -pi -e "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBXPROJ"

# Verify
WRITTEN_VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/;//;s/ *//')
WRITTEN_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/;//;s/ *//')

if [[ "$WRITTEN_VERSION" != "$NEW_VERSION" || "$WRITTEN_BUILD" != "$NEW_BUILD" ]]; then
    echo "Error: Verification failed — expected $NEW_VERSION / $NEW_BUILD, got $WRITTEN_VERSION / $WRITTEN_BUILD" >&2
    exit 1
fi

echo "Done."
