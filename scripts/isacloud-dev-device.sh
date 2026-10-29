#!/bin/bash

# Builds the isaCloud ".dev" variant and installs it on a connected iPhone, signed with the team given below (automatic signing).
#
# usage (from the repository root):
#   scripts/isacloud-dev-device.sh <TEAM_ID> [DEVICE_UDID]
#
# - TEAM_ID: Xcode -> Settings -> Accounts -> your team (or: defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier)
# - DEVICE_UDID: optional, defaults to the first connected physical iPhone (xcrun devicectl list devices)
#
# The .dev variant uses the bundle id br.com.isacloud.messenger.dev (app group and keychain follow it), so it never
# blocks the real bundle id, and the entitlements in isaCloud/dev-entitlements/ (with the app group group.<bundle id>, so the app and its
# extensions share their data, but without aps-environment (no APNs push; the notifications seen in the .dev are local ones), communication
# notifications and the increased memory limit, which this variant does not ask for). A free Apple ID would expire after 7 days and could not
# use the app group; with the paid team the profile lasts a year (security cms -D -i <app>/embedded.mobileprovision shows it).

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

# chave da busca de GIF (Giphy), guardada fora do repositório; sem ela a busca mostra que não está configurada
GIPHY_KEY_FILE="$REPO_ROOT/isaCloud/local/giphy-api-key.txt"
GIPHY_API_KEY=""
if [[ -f "$GIPHY_KEY_FILE" ]]; then
    GIPHY_API_KEY="$(tr -d '[:space:]' < "$GIPHY_KEY_FILE")"
fi

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
    ISACLOUD_DISPLAY_NAME="isaCloud.dev" \
    ISACLOUD_OPEN_SCHEME="isacloudOpenDev" \
    ISACLOUD_ENTITLEMENTS_DIR="../isaCloud/dev-entitlements/" \
    GIPHY_API_KEY="$GIPHY_API_KEY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="Apple Development" \
    PROVISIONING_PROFILE_SPECIFIER= \
    build

APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/isaCloud.app"
echo "Installing $APP..."
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"
echo "Launching $BUNDLE_ID..."
xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID" || \
    echo "Could not launch: if iOS says the developer is not trusted, open Settings > General > VPN & Device Management and trust your Apple ID, then open isaCloud."
