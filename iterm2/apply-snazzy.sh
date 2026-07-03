#!/bin/sh
# Apply the Snazzy color preset directly into the iTerm2 Default Profile
# (New Bookmarks[0]) so it is active on launch.
#
# Reads from: $HOME/.dotfiles/iterm2/Snazzy.itermcolors
# Writes to:  $HOME/Library/Preferences/com.googlecode.iterm2.plist
#
# Safe to run multiple times. Backs up the plist before writing.

set -e

PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
COLORS_FILE="$HOME/.dotfiles/iterm2/Snazzy.itermcolors"

if [ ! -f "$COLORS_FILE" ]; then
    echo "ERROR: Snazzy colors not found at $COLORS_FILE" >&2
    echo "       Copy Snazzy.itermcolors there before running this script." >&2
    exit 1
fi

mkdir -p "$(dirname "$PLIST")"

if [ ! -f "$PLIST" ]; then
    /usr/bin/plutil -create xml1 "$PLIST" >/dev/null 2>&1 || {
        echo "ERROR: failed to create $PLIST" >&2
        exit 1
    }
fi

BAK="/tmp/com.googlecode.iterm2.plist.bak.$(date +%s)"
cp "$PLIST" "$BAK" >/dev/null 2>&1 || true

python3 - "$PLIST" "$COLORS_FILE" <<'PYEOF'
import sys, plistlib, uuid

plist_path, colors_path = sys.argv[1], sys.argv[2]

with open(colors_path, "rb") as f:
    profile = plistlib.load(f)["Profiles"][0]

try:
    with open(plist_path, "rb") as f:
        prefs = plistlib.load(f)
except Exception:
    prefs = {}

bookmarks = prefs.get("New Bookmarks") or []
if not bookmarks:
    bookmarks = [{}]
else:
    bookmarks = list(bookmarks)
    while len(bookmarks) < 1:
        bookmarks.append({})

target = bookmarks[0]

# Merge all Snazzy keys into the default bookmark first
for k, v in profile.items():
    target[k] = v

# Now ensure we have a stable GUID and Default markers.
# If the colors file already supplies a Guid, reuse it; otherwise generate one.
target_guid = target.get("Guid") or str(uuid.uuid4()).upper()
target["Guid"] = target_guid
prefs["Default Bookmark Guid"] = target_guid
target["Default Bookmark"] = "Yes"
target["Name"] = "Snazzy"
target["Description"] = "Default"

bookmarks[0] = target
prefs["New Bookmarks"] = bookmarks

with open(plist_path, "wb") as f:
    plistlib.dump(prefs, f)

print(f"==> Profile GUID: {target_guid}")
PYEOF

echo "==> Snazzy theme applied to Default Profile (New Bookmarks[0])."
echo "    Backup: $BAK"
