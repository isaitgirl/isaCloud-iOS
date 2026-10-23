#!/bin/bash

# Applies isaCloud's branding and own translations to the strings copied into the built app.
# Runs as the "[isaCloud] Merge localizations" build phase of the Monal target, after Monal's
# translations (Monal/localization/external, from Monal's Weblate) were copied into the bundle.
#
# 1. Branding: in every <lang>.lproj/*.strings of the app, the word "Monal" is replaced by "isaCloud"
#    in the displayed values only (keys are untouched). Compounds like "Monal-Servers" and URLs or
#    domains (github.com/monal-im/Monal, monal-im.org) are left alone.
# 2. Own translations: isaCloud/localization/<lang>.lproj/<Table>.strings are merged on top.
#    Keys present in both use the isaCloud value, keys only present in isaCloud are added.

set -e

OVERRIDES_DIR="${SRCROOT}/../isaCloud/localization"
RESOURCES_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

/usr/bin/python3 -I - "$RESOURCES_DIR" "$OVERRIDES_DIR" <<'PYTHON'
import glob, os, plistlib, re, subprocess, sys, tempfile

resources_dir, overrides_dir = sys.argv[1], sys.argv[2]

# "Monal" as a standalone word: not part of a path, domain or compound (Monal-Servers, monal-im.org, Monal.im)
BRAND = re.compile(r"(?<![\w/.-])Monal(?![\w-]|\.\w)")

def load(path):
    # .strings files can be old-style text or binary plists, normalize via plutil
    with tempfile.NamedTemporaryFile(suffix=".plist") as tmp:
        subprocess.run(["plutil", "-convert", "xml1", "-o", tmp.name, path], check=True)
        with open(tmp.name, "rb") as f:
            return plistlib.load(f)

def save(path, strings):
    with open(path, "wb") as f:
        plistlib.dump(strings, f, fmt=plistlib.FMT_BINARY)

# 1. branding
for path in sorted(glob.glob(os.path.join(resources_dir, "*.lproj", "*.strings"))):
    strings = load(path)
    changed = 0
    for key, value in strings.items():
        if isinstance(value, str):
            new = BRAND.sub("isaCloud", value)
            if new != value:
                strings[key] = new
                changed += 1
    if changed:
        save(path, strings)
        print("Branded %d strings in %s" % (changed, os.path.relpath(path, resources_dir)))

# 2. own translations
for override in sorted(glob.glob(os.path.join(overrides_dir, "*.lproj", "*.strings"))):
    lproj = os.path.basename(os.path.dirname(override))
    target = os.path.join(resources_dir, lproj, os.path.basename(override))
    if not os.path.exists(target):
        print("warning: %s/%s not found in the app bundle (language not shipped by Monal?), skipping %s" % (lproj, os.path.basename(override), override))
        continue
    strings = load(target)
    own = load(override)
    strings.update(own)
    save(target, strings)
    print("Merged %d isaCloud strings into %s" % (len(own), os.path.relpath(target, resources_dir)))
PYTHON
