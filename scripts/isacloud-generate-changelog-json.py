#!/usr/bin/env python3
# isaCloud: generates Monal/isaCloud-changelog.json (the "Novidades do isaCloud" shown in the chats list and in Settings → About)
# from CHANGELOG-USERS.md. Called by scripts/archive-testflight.sh and scripts/isacloud-dev-device.sh before xcodebuild.
#
# usage (python3, no dependencies):
#   scripts/isacloud-generate-changelog-json.py [CHANGELOG-USERS.md] [Monal/isaCloud-changelog.json]
#
# Markdown format:
#   ## Build 104 · 11/11/2026        release (the date is optional)
#   ## Próximo build                 the build being prepared: it takes the number of CURRENT_PROJECT_VERSION of the project
#                                    and today's date (dd/MM/yyyy). Ignored, with a warning, when the project's build is already
#                                    a "## Build N" section (the build was closed). Empty: skipped with a warning.
#   ### Novidades | ### Melhorias | ### Correções
#   - item                          items keep their text as written (emoji and simple markdown included)
# Text before the first "## " is ignored.
#
# Exit status 1 (and nothing written) when the Markdown or the project is inconsistent: a failure here fails the build script.

import datetime
import json
import os
import re
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
DEFAULT_MARKDOWN = os.path.join(REPO_ROOT, "CHANGELOG-USERS.md")
DEFAULT_JSON = os.path.join(REPO_ROOT, "Monal", "isaCloud-changelog.json")
PBXPROJ = os.path.join(REPO_ROOT, "Monal", "Monal.xcodeproj", "project.pbxproj")

SECTION_TITLES = ("Novidades", "Melhorias", "Correções")
RELEASE_HEADER = re.compile(r"^Build\s+(\d+)(?:\s*·\s*(\d{2}/\d{2}/\d{4}))?$")
PENDING_HEADER = re.compile(r"^pr[oó]ximo build$", re.IGNORECASE)
SECTION_HEADER = re.compile(r"^###\s+(.+?)\s*$")
ITEM = re.compile(r"^-\s+(.+?)\s*$")


def fail(message):
    sys.stderr.write("error: %s\n" % message)
    sys.exit(1)


def warn(message):
    sys.stderr.write("warning: %s\n" % message)


def project_build_number():
    try:
        with open(PBXPROJ, encoding="utf-8") as f:
            values = set(re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", f.read()))
    except OSError as e:
        fail("cannot read %s: %s" % (PBXPROJ, e))
    if len(values) != 1:
        fail("CURRENT_PROJECT_VERSION is not the same everywhere in the project: %s" % ", ".join(sorted(values)))
    value = values.pop().strip()
    if not value.isdigit():
        fail("CURRENT_PROJECT_VERSION is not a number: %s" % value)
    return int(value)


def parse(lines):
    """Returns (releases, pending), each release as a dict with build, date and sections (title + items)."""
    releases = []
    pending = None
    current = None      # the release being read
    section = None      # the section being read
    for number, raw in enumerate(lines, 1):
        line = raw.rstrip("\n").strip()
        if line.startswith("## "):
            title = line[3:].strip()
            match = RELEASE_HEADER.match(title)
            if match:
                current = {"build": int(match.group(1)), "date": match.group(2), "sections": []}
                releases.append(current)
            elif PENDING_HEADER.match(title):
                if pending is not None:
                    fail("line %d: more than one \"## Próximo build\" section" % number)
                current = {"build": None, "date": None, "sections": []}
                pending = current
            else:
                fail("line %d: unknown release header \"%s\" (expected \"## Build N · dd/MM/yyyy\" or \"## Próximo build\")" % (number, title))
            section = None
            continue
        if current is None:
            continue    # introduction before the first release
        if line.startswith("### "):
            match = SECTION_HEADER.match(line)
            title = match.group(1)
            if title not in SECTION_TITLES:
                fail("line %d: unknown section \"%s\" (expected one of: %s)" % (number, title, ", ".join(SECTION_TITLES)))
            section = {"title": title, "items": []}
            current["sections"].append(section)
            continue
        match = ITEM.match(line)
        if match and section is not None:
            section["items"].append(match.group(1))
    return releases, pending


def clean(releases):
    """Drops empty sections and releases (with a warning) and returns the releases with items only."""
    kept = []
    for release in releases:
        label = "build %s" % release["build"] if release["build"] is not None else "\"Próximo build\""
        sections = []
        for section in release["sections"]:
            if section["items"]:
                sections.append(section)
            else:
                warn("%s: section \"%s\" has no items, skipped" % (label, section["title"]))
        if sections:
            release["sections"] = sections
            kept.append(release)
        else:
            warn("%s has no items, skipped" % label)
    return kept


def main(argv):
    args = argv[1:]
    if len(args) > 2:
        fail("usage: %s [CHANGELOG-USERS.md] [isaCloud-changelog.json]" % os.path.basename(argv[0]))
    markdown_path = args[0] if len(args) > 0 else DEFAULT_MARKDOWN
    json_path = args[1] if len(args) > 1 else DEFAULT_JSON

    try:
        with open(markdown_path, encoding="utf-8") as f:
            lines = f.readlines()
    except OSError as e:
        fail("cannot read %s: %s" % (markdown_path, e))

    releases, pending = parse(lines)
    releases = clean(releases)
    build_number = project_build_number()
    closed = [release for release in releases if release["build"] == build_number]

    if pending is not None:
        if pending["sections"] and any(section["items"] for section in pending["sections"]):
            if closed:
                warn("\"## Próximo build\" ignored: build %d is already closed in the Markdown (\"## Build %d\")" % (build_number, build_number))
            else:
                pending["build"] = build_number
                pending["date"] = datetime.date.today().strftime("%d/%m/%Y")
                releases.append(pending)
        else:
            warn("\"## Próximo build\" is empty, skipped")
        releases = clean(releases)

    releases.sort(key=lambda release: release["build"], reverse=True)
    if not releases:
        fail("no release with items in %s" % markdown_path)
    builds = [release["build"] for release in releases]
    duplicates = sorted({b for b in builds if builds.count(b) > 1})
    if duplicates:
        fail("duplicate builds in %s: %s" % (markdown_path, ", ".join(str(b) for b in duplicates)))

    output = {"releases": []}
    for release in releases:
        entry = {"build": release["build"]}
        if release["date"]:
            entry["date"] = release["date"]
        entry["sections"] = [{"title": s["title"], "items": s["items"]} for s in release["sections"]]
        output["releases"].append(entry)

    os.makedirs(os.path.dirname(os.path.abspath(json_path)), exist_ok=True)
    with open(json_path, "w", encoding="utf-8") as f:
        f.write(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    items = sum(len(s["items"]) for r in releases for s in r["sections"])
    print("isaCloud changelog: %d release(s), %d item(s), newest build %d -> %s" % (len(releases), items, builds[0] if builds else 0, json_path))


if __name__ == "__main__":
    main(sys.argv)
