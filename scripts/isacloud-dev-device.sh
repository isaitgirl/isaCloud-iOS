#!/bin/bash

# Builds the isaCloud ".dev" variant and installs it on a connected iPhone, using a free Apple ID (Personal Team).
#
# usage (from the repository root):
#   scripts/isacloud-dev-device.sh <TEAM_ID> [DEVICE_UDID]
#
# - TEAM_ID: Xcode -> Settings -> Accounts -> your team (or: defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier)
# - DEVICE_UDID: optional, defaults to the first connected physical iPhone (xcrun devicectl list devices)
#
# The .dev variant uses the bundle id br.com.isacloud.messenger.dev (app group and keychain follow it), so it never
# blocks the real bundle id, and the entitlements in isaCloud/dev-entitlements/ (without push, communication notifications, app groups and the
# increased memory limit, which free accounts cannot use; the app then keeps its data in its own private directory,
# so the notification and share extensions do not share it). Builds signed with a free account expire after 7 days.

set -e
set -o pipefail

TEAM_ID="$1"
DEVICE_UDID="$2"
if [[ -z "$TEAM_ID" ]]; then
    echo "usage: $0 <TEAM_ID> [DEVICE_UDID]" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$REPO_ROOT/build/dev-device}"
BUNDLE_ID="br.com.isacloud.messenger.dev"

if [[ -z "$DEVICE_UDID" ]]; then
    DEVICE_UDID=$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /connected/ { for(i=1;i<=NF;i++) if($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) { print $i; exit } }')
    if [[ -z "$DEVICE_UDID" ]]; then
        echo "no connected iPhone found (xcrun devicectl list devices)" >&2
        exit 1
    fi
fi
echo "Building $BUNDLE_ID for device $DEVICE_UDID (team $TEAM_ID)..."

cd "$REPO_ROOT/Monal"
xcodebuild -quiet \
    -workspace Monal.xcworkspace \
    -scheme Monal \
    -configuration Debug \
    -destination "id=$DEVICE_UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    ISACLOUD_BUNDLE_ID="$BUNDLE_ID" \
    ISACLOUD_ENTITLEMENTS_DIR="../isaCloud/dev-entitlements/" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="Apple Development" \
    PROVISIONING_PROFILE_SPECIFIER= \
    build

APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/Monal.app"
echo "Installing $APP..."
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"
echo "Launching $BUNDLE_ID..."
xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID" || \
    echo "Could not launch: if iOS says the developer is not trusted, open Settings > General > VPN & Device Management and trust your Apple ID, then open isaCloud."
