#!/bin/sh
# Replace iTerm2's preferences with the snapshot committed to this
# repo. Replaces the entire prefs domain, so anything iTerm2 itself
# rewrites at runtime (window frames, migration flags, GUID-keyed
# per-profile state) snaps back to the exported baseline on each run.
#
# Re-export after tweaking iTerm via the GUI:
#   defaults export com.googlecode.iterm2 \
#     "$DOTFILES/iterm2/com.googlecode.iterm2.plist.export"

set -eu
set -o pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
PLIST_FILE="$DOTFILES/iterm2/com.googlecode.iterm2.plist.export"
DOMAIN="com.googlecode.iterm2"

if [ ! -f "$PLIST_FILE" ]; then
    echo "ERROR: iTerm2 pref snapshot not found at $PLIST_FILE" >&2
    exit 1
fi

# `defaults import` requires the snapshot to be in binary plist form;
# the dotfiles copy is already in that form (kept as a `.export`
# suffix to make that obvious in future diffs).
if plutil -lint "$PLIST_FILE" >/dev/null 2>&1; then
    :
else
    echo "ERROR: $PLIST_FILE is not a valid plist; refusing to import." >&2
    exit 1
fi

# Make sure iTerm2 isn't running so it doesn't overwrite the file we
# just imported on shutdown. SIGTERM is what we found to actually
# take iTerm2 down; osascript's `quit` waits indefinitely when the
# app prompts to confirm session close.
if pgrep -f "iTerm.app/Contents/MacOS/iTerm2" >/dev/null 2>&1; then
    echo "==> Stopping iTerm2 before defaults import..."
    if ! pkill -f "iTerm.app/Contents/MacOS/iTerm2"; then
        echo "ERROR: could not stop iTerm2; aborting import to avoid racing the prefs daemon." >&2
        exit 1
    fi
    # SIGTERM lets the daemon save its own per-window state; once the
    # main process is gone we're clear to swap the prefs file.
    for _ in 1 2 3 4 5; do
        sleep 1
        pgrep -f "iTerm.app/Contents/MacOS/iTerm2" >/dev/null 2>&1 || break
    done
    if pgrep -f "iTerm.app/Contents/MacOS/iTerm2" >/dev/null 2>&1; then
        echo "ERROR: iTerm2 is still running; aborting import." >&2
        exit 1
    fi
fi

defaults import "$DOMAIN" "$PLIST_FILE"
echo "==> iTerm2 prefs imported from $PLIST_FILE"
