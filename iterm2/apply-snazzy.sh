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
    data = plistlib.load(f)
    profile = data["Profiles"][0] if "Profiles" in data else data

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

target = bookmarks[0]

for k, v in profile.items():
    target[k] = v

for key in ("Background Color", "Foreground Color", "Cursor Color", "Selection Color",
            "Bold Color", "Link Color", "Cursor Text Color", "Selected Text Color",
            "Badge Color",
            "Ansi 0 Color", "Ansi 1 Color", "Ansi 2 Color", "Ansi 3 Color",
            "Ansi 4 Color", "Ansi 5 Color", "Ansi 6 Color", "Ansi 7 Color",
            "Ansi 8 Color", "Ansi 9 Color", "Ansi 10 Color", "Ansi 11 Color",
            "Ansi 12 Color", "Ansi 13 Color", "Ansi 14 Color", "Ansi 15 Color",
            "Cursor Guide Color", "Match Background Color"):
    for variant in (" (Dark)", " (Light)"):
        full_key = key + variant
        if key in target:
            target[full_key] = dict(target[key])

target_guid = target.get("Guid") or str(uuid.uuid4()).upper()
target["Guid"] = target_guid
prefs["Default Bookmark Guid"] = target_guid
target["Default Bookmark"] = "Yes"
target["Name"] = "Snazzy"
target["Description"] = "Default"
target["Use Separate Colors for Light and Dark Mode"] = True

bookmarks[0] = target
prefs["New Bookmarks"] = bookmarks

with open(plist_path, "wb") as f:
    plistlib.dump(prefs, f)

print(f"==> Profile GUID: {target_guid}")
PYEOF

echo "==> Snazzy theme applied to Default Profile (New Bookmarks[0])."
echo "    Backup: $BAK"