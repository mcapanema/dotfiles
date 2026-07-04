#!/bin/sh
# Apply the Snazzy color preset and a default font to the iTerm2 Default
# Profile (New Bookmarks[0]) so it is active on launch.
#
# Reads from: $HOME/.dotfiles/iterm2/Snazzy.itermcolors
# Writes to:  $HOME/Library/Preferences/com.googlecode.iterm2.plist
#
# Safe to run multiple times. Backs up the plist before writing.
#
# Notes on the font field:
# iTerm2 3.6.x expects "Normal Font" inside a bookmark dict to be the
# legacy CFString "<Font Name> <Size>" (e.g. "JetBrainsMono-Regular 15").
# Writing it as either a {FontName, FontSize} dict or as an NSKeyedArchiver
# NSFontDescriptor <data> blob crashes iTerm2 at launch with
#   -[<obj> fontValueWithLigaturesEnabled:]: unrecognized selector ...
# so we use the string form, which is what 3.6.11 reads back without errors.

set -e

PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
COLORS_FILE="$HOME/.dotfiles/iterm2/Snazzy.itermcolors"
FONT_NAME="JetBrainsMono-Regular"
FONT_SIZE=15

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

FONT_VALUE="${FONT_NAME} ${FONT_SIZE}"
# Verify the resolved font exists. If not, install it via Homebrew and rebuild
# the font cache; if still missing, leave the profile's Normal Font untouched
# so we never end up with an unresolvable name string in the plist.
font_installed() {
    for cand in \
        "$HOME/Library/Fonts/${FONT_NAME}.ttf" \
        "$HOME/Library/Fonts/${FONT_NAME}.otf" \
        "$HOME/Library/Fonts/${FONT_NAME}.ttc"; do
        [ -f "$cand" ] && return 0
    done
    /usr/bin/mdfind -name "${FONT_NAME}.ttf" -onlyin "$HOME/Library" 2>/dev/null | grep -q . || return 1
    /usr/bin/mdfind -name "${FONT_NAME}.otf" -onlyin "$HOME/Library" 2>/dev/null | grep -q .
}

if font_installed; then
    :
else
    if command -v brew >/dev/null 2>&1; then
        echo "==> Installing font ${FONT_NAME} via Homebrew..."
        # --quiet keeps the output tame on a clean machine.
        brew install --cask --quiet font-jetbrains-mono 2>&1 | tail -20 || {
            echo "WARN: brew install font-jetbrains-mono failed; "
            FONT_VALUE=""
        }
    else
        echo "WARN: Homebrew is not on PATH; cannot auto-install ${FONT_NAME}."
    fi
fi

if font_installed; then
    :
else
    echo "WARN: Font '$FONT_NAME' not registered; Normal Font will be left unchanged." >&2
    FONT_VALUE=""
fi

python3 - "$PLIST" "$COLORS_FILE" "$FONT_VALUE" <<'PYEOF'
import sys, plistlib, uuid

plist_path, colors_path, font_value = sys.argv[1], sys.argv[2], sys.argv[3]

with open(colors_path, "rb") as f:
    data = plistlib.load(f)
profile = data["Profiles"][0] if "Profiles" in data else data

try:
    with open(plist_path, "rb") as f:
        prefs = plistlib.load(f)
except Exception:
    prefs = {}

bookmarks = prefs.get("New Bookmarks") or []
bookmarks = list(bookmarks) if bookmarks else [{}]

target = bookmarks[0]

for k, v in profile.items():
    target[k] = v

duplicate_keys = (
    "Background Color", "Foreground Color", "Cursor Color", "Selection Color",
    "Bold Color", "Link Color", "Cursor Text Color", "Selected Text Color",
    "Badge Color",
    "Ansi 0 Color", "Ansi 1 Color", "Ansi 2 Color", "Ansi 3 Color",
    "Ansi 4 Color", "Ansi 5 Color", "Ansi 6 Color", "Ansi 7 Color",
    "Ansi 8 Color", "Ansi 9 Color", "Ansi 10 Color", "Ansi 11 Color",
    "Ansi 12 Color", "Ansi 13 Color", "Ansi 14 Color", "Ansi 15 Color",
    "Cursor Guide Color", "Match Background Color",
)
for key in duplicate_keys:
    if key not in target:
        continue
    base = dict(target[key])
    for variant in (" (Dark)", " (Light)"):
        if key + variant not in target:
            target[key + variant] = dict(base)

target_guid = target.get("Guid") or str(uuid.uuid4()).upper()
target["Guid"] = target_guid
prefs["Default Bookmark Guid"] = target_guid
target["Default Bookmark"] = "Yes"
target["Name"] = "Snazzy"
target["Description"] = "Default"
target["Use Separate Colors for Light and Dark Mode"] = True
# "Anti Aliasing" >= 1 enables antialiasing globally, but iTerm2 also forces
# ASCII glyphs to NOT be antialiased whenever "ASCII Anti Aliased" is false
# (Bool 0) inside the profile, which overrides the global knob. Set BOTH
# so the GUI "Anti-aliased text" tickbox reflects the expected state.
target["Anti Aliasing"] = 1
target["ASCII Anti Aliased"] = True

if font_value:
    target["Normal Font"] = font_value

bookmarks[0] = target
prefs["New Bookmarks"] = bookmarks

with open(plist_path, "wb") as f:
    plistlib.dump(prefs, f)

print(f"==> Profile GUID: {target_guid}")
PYEOF

echo "==> Snazzy theme applied to Default Profile (New Bookmarks[0])."
if [ -n "$FONT_VALUE" ]; then
    echo "    Normal Font: $FONT_VALUE"
else
    echo "    Normal Font: (unchanged)"
fi
echo "    Backup: $BAK"
