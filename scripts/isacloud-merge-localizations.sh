#!/bin/bash

# Merges isaCloud's own translations (isaCloud/localization/<lang>.lproj/<Table>.strings)
# over the Monal translations already copied into the built product.
# Keys present in both use the isaCloud value; keys only present in isaCloud are added.
# Runs as the "[isaCloud] Merge localizations" build phase of the Monal target.

set -e

OVERRIDES_DIR="${SRCROOT}/../isaCloud/localization"
RESOURCES_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

if [[ ! -d "$OVERRIDES_DIR" ]]; then
    echo "No isaCloud localizations found at $OVERRIDES_DIR, nothing to merge"
    exit 0
fi

TMPDIR_MERGE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_MERGE"' EXIT

for override in "$OVERRIDES_DIR"/*.lproj/*.strings; do
    [[ -f "$override" ]] || continue
    lproj=$(basename "$(dirname "$override")")
    table=$(basename "$override")
    target="$RESOURCES_DIR/$lproj/$table"

    if [[ ! -f "$target" ]]; then
        echo "warning: $lproj/$table not found in the app bundle (language not shipped by Monal?), skipping $override"
        continue
    fi

    # both files can be text .strings or binary plists, normalize them to xml plists first
    plutil -convert xml1 -o "$TMPDIR_MERGE/base.plist" "$target"
    plutil -convert xml1 -o "$TMPDIR_MERGE/override.plist" "$override"

    /usr/bin/python3 -I - "$TMPDIR_MERGE/base.plist" "$TMPDIR_MERGE/override.plist" "$TMPDIR_MERGE/merged.plist" <<'PYTHON'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    base = plistlib.load(f)
with open(sys.argv[2], "rb") as f:
    override = plistlib.load(f)
base.update(override)
with open(sys.argv[3], "wb") as f:
    plistlib.dump(base, f, fmt=plistlib.FMT_BINARY)
print("merged %d isaCloud strings" % len(override))
PYTHON

    cp "$TMPDIR_MERGE/merged.plist" "$target"
    echo "Merged $override into $target"
done
