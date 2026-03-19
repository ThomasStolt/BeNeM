#!/bin/bash
# Build and optionally deploy BeNeM to a physical iOS device or simulator.
#
# Configuration: copy build.local.sh.example to build.local.sh and fill in your values.
# build.local.sh is gitignored and never committed.

set -e

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# Load local overrides (device ID, simulator name, etc.)
LOCAL_CONFIG="$REPO_ROOT/build.local.sh"
if [ -f "$LOCAL_CONFIG" ]; then
    # shellcheck source=/dev/null
    source "$LOCAL_CONFIG"
fi

SCHEME="${BENEM_SCHEME:-BeNeM}"
PROJECT="$REPO_ROOT/BeNeM.xcodeproj"
DEVICE_ID="${BENEM_DEVICE_ID:-}"
SIMULATOR="${BENEM_SIMULATOR:-iPhone 16 Pro}"

if [ -n "$DEVICE_ID" ]; then
    DESTINATION="id=$DEVICE_ID"
    echo "==> Building for device ($DEVICE_ID)..."
else
    DESTINATION="platform=iOS Simulator,name=$SIMULATOR"
    echo "==> No device configured — building for simulator ($SIMULATOR)..."
fi

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    clean build

if [ -n "$DEVICE_ID" ]; then
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "BeNeM.app" \
        -path "*/Debug-iphoneos/*" 2>/dev/null | head -1)
    if [ -z "$APP_PATH" ]; then
        echo "ERROR: Could not find BeNeM.app in DerivedData." >&2
        exit 1
    fi
    echo "==> Installing on device..."
    xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
    echo "==> Done! App installed."
else
    echo "==> Done! (Simulator build — no install step)"
fi
