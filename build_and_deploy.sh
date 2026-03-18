#!/bin/bash
set -e

PROJECT="/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/BeNeM.xcodeproj"
SCHEME="BeNeM"
XCODE_DEVICE_ID="00008110-00167D41263A801E"
DEVICE_NAME="TomiPhone13"
APP_PATH="/Users/thomasstolt/Library/Developer/Xcode/DerivedData/BeNeM-gwfbvcgxlpmlvheswovjholwhghu/Build/Products/Debug-iphoneos/BeNeM.app"

echo "==> Checking if $DEVICE_NAME is connected..."
DEVICECTL_ID=$(xcrun devicectl list devices 2>/dev/null | awk -v name="$DEVICE_NAME" '$1 == name {print $3}')

if [ -n "$DEVICECTL_ID" ]; then
    DESTINATION="platform=iOS,id=$XCODE_DEVICE_ID"
    echo "==> $DEVICE_NAME found (devicectl: $DEVICECTL_ID), building for device..."
else
    DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro"
    echo "==> $DEVICE_NAME not connected, falling back to simulator..."
fi

echo "==> Building..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    build

if [ -n "$DEVICECTL_ID" ]; then
    echo "==> Installing on $DEVICE_NAME..."
    xcrun devicectl device install app \
        --device "$DEVICECTL_ID" \
        "$APP_PATH"
    echo "==> Done! App installed on $DEVICE_NAME."
else
    echo "==> Done! (Simulator build, no install needed)"
fi
