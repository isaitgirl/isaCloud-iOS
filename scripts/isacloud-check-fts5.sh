#!/bin/bash

# Checks that the SQLite inside a build has FTS5 (the full text search of the messages needs it).
# The SQLite comes from the sqlite3-package fork (trait ENABLE_FTS5), but Xcode can reuse an old compiled copy of it
# (stale package cache in the derived data) and then the app is built WITHOUT FTS5, without any warning.
#
# usage: scripts/isacloud-check-fts5.sh <path to the .app, the .framework or the monalxmpp binary>
# exit: 0 = has FTS5, 1 = does not have it (or the binary was not found)
#
# Used by the "[isaCloud] Check FTS5" build phase, by scripts/archive-testflight.sh and by hand (docs/troubleshooting.md).

set -e

TARGET="$1"
if [[ -z "$TARGET" ]]; then
    echo "usage: $0 <app, framework or binary>" >&2
    exit 1
fi

if [[ -d "$TARGET" && "$TARGET" == *.app ]]; then
    TARGET="$TARGET/Frameworks/monalxmpp.framework/monalxmpp"
elif [[ -d "$TARGET" && "$TARGET" == *.framework ]]; then
    TARGET="$TARGET/monalxmpp"
fi

if [[ ! -f "$TARGET" ]]; then
    echo "error: [isaCloud] monalxmpp binary not found at $TARGET, cannot check FTS5" >&2
    exit 1
fi

# SQLite lists its compile options as plain strings ("ENABLE_FTS5") inside the binary
if [[ "$(strings -a "$TARGET" | grep -c '^ENABLE_FTS5$')" == "1" ]]; then
    echo "FTS5 ok: $TARGET"
    exit 0
fi

echo "error: [isaCloud] this build's SQLite has NO FTS5 (the message search would not work). Xcode reused an old compiled SQLite: delete the derived data folder of this build (build/dev-device, /tmp/ddarch, or ~/Library/Developer/Xcode/DerivedData/Monal-*) and build again. See docs/troubleshooting.md." >&2
exit 1
