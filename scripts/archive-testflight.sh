#!/bin/bash

# Archives the isaCloud AppStore build for TestFlight, always in a fresh derived data folder, and checks the archive
# before anything is uploaded (build number, bundle id and FTS5 in the SQLite). Steps of docs/publicacao-testflight.md.
#
# usage (from anywhere):
#   scripts/archive-testflight.sh            archive and check only
#   scripts/archive-testflight.sh --upload   archive, check and upload to App Store Connect
#
# The build number is the one in the project (CURRENT_PROJECT_VERSION, 25 places): bump it BEFORE running this script.
# The archive is made in /tmp/ddarch (deleted first): reusing the default derived data once produced an archive without FTS5 (builds 32 and 77).
# The tag (git tag -a build-N), the CHANGELOG and the other steps of "novo build e push" stay with the person (CLAUDE.md).

set -e
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM_ID="K8Y6S5RF2S"
BUNDLE_ID="br.com.isacloud.messenger"
DERIVED_DATA="/tmp/ddarch"
ARCHIVE="$REPO_ROOT/build/isaCloud-AppStore.xcarchive"
EXPORT_OPTIONS="$REPO_ROOT/scripts/exportOptions/isaCloud_AppStore_Upload_ExportOptions.plist"
GIPHY_KEY_FILE="$REPO_ROOT/isaCloud/local/giphy-api-key.txt"
UPLOAD=0
[[ "$1" == "--upload" ]] && UPLOAD=1

# 1. the build number must be the same in the 25 places
VERSIONS=$(grep -o "CURRENT_PROJECT_VERSION = [0-9.]*" "$REPO_ROOT/Monal/Monal.xcodeproj/project.pbxproj" | sort | uniq -c)
if [[ $(echo "$VERSIONS" | wc -l | tr -d ' ') != "1" ]]; then
    echo "error: CURRENT_PROJECT_VERSION is not the same everywhere:" >&2
    echo "$VERSIONS" >&2
    exit 1
fi
BUILD_NUMBER=$(echo "$VERSIONS" | sed 's/.*= //')
echo "Archiving build $BUILD_NUMBER ($(echo "$VERSIONS" | awk '{print $1}') places)"

GIPHY_API_KEY=""
if [[ -f "$GIPHY_KEY_FILE" ]]; then
    GIPHY_API_KEY="$(tr -d '[:space:]' < "$GIPHY_KEY_FILE")"
else
    echo "warning: $GIPHY_KEY_FILE not found, the GIF search will be off in this build" >&2
fi

# 2. fresh derived data and archive
rm -rf "$DERIVED_DATA" "$ARCHIVE"
cd "$REPO_ROOT/Monal"
xcodebuild archive \
    -workspace Monal.xcworkspace \
    -scheme Monal \
    -sdk iphoneos \
    -configuration AppStore \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ISACLOUD_BUNDLE_ID="$BUNDLE_ID" \
    ISACLOUD_ENTITLEMENTS_DIR= \
    GIPHY_API_KEY="$GIPHY_API_KEY"

# 3. check the archive before uploading anything
APP=$(ls -d "$ARCHIVE"/Products/Applications/*.app)
ARCHIVED_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Info.plist")
ARCHIVED_BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
if [[ "$ARCHIVED_NUMBER" != "$BUILD_NUMBER" || "$ARCHIVED_BUNDLE" != "$BUNDLE_ID" ]]; then
    echo "error: the archive says build $ARCHIVED_NUMBER / $ARCHIVED_BUNDLE, expected $BUILD_NUMBER / $BUNDLE_ID" >&2
    exit 1
fi
"$REPO_ROOT/scripts/isacloud-check-fts5.sh" "$APP"
echo "Archive checked: build $ARCHIVED_NUMBER, $ARCHIVED_BUNDLE, FTS5 present."

# 4. upload
if [[ $UPLOAD == 1 ]]; then
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        -allowProvisioningUpdates
    echo "Build $BUILD_NUMBER uploaded at $(date +%H:%M). Next: git tag -a build-$BUILD_NUMBER <commit> and push it."
else
    echo "Not uploaded (use --upload). Archive: $ARCHIVE"
fi
