#!/bin/sh
# Apply a set of sensible macOS system defaults for a developer workstation.
# Safe to re-run; all writes are idempotent.
#
# Key notes for modern macOS:
#   - ApplePressAndHoldEnabled / KeyRepeat / InitialKeyRepeat on NSGlobalDomain
#     are deprecated since macOS 13 but still accepted by defaults(1). They
#     are also re-asserted by the per-user com.apple.HIToolbox domain, which
#     the keyboard input services read at login. We write BOTH domains, then
#     restart cfprefsd so the changes are picked up by the live session —
#     otherwise `defaults write` returns success while the running session
#     continues to serve the cached older values via cfprefsd.
#   - The built-in trackpad uses com.apple.AppleMultitouchTrackpad on Apple
#     Silicon Macs. The older com.apple.driver.AppleBluetoothMultitouch.trackpad
#     domain covers external Bluetooth trackpads. We write both for maximum
#     coverage across Intel and Apple Silicon machines.
#   - Time Machine's DoNotOfferNewDisksForBackup is still respected on macOS 26.

set -eu
set -o pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"

info()  { echo "==> $*" ; }
warn()  { echo " WARNING: $*" ; }

# ------------------------- Keyboard -------------------------

info "Disabling press-and-hold for keys (key repeat enabled)..."
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
# Also write under the per-user HIToolbox domain. On macOS 13+ the input
# services layer reads press-and-hold from here at login and will silently
# override whatever was set in NSGlobalDomain until it's dropped.
defaults write com.apple.HIToolbox ApplePressAndHoldEnabled -bool false

info "Setting fast keyboard repeat rate (KeyRepeat=1, InitialKeyRepeat=15)..."
defaults write NSGlobalDomain KeyRepeat -int 1
defaults write NSGlobalDomain InitialKeyRepeat -int 15
# Mirror the repeat values under HIToolbox so they survive a re-login and
# aren't reassigned by per-keyboard-layout defaults cached elsewhere.
defaults write com.apple.HIToolbox KeyRepeat -int 1
defaults write com.apple.HIToolbox InitialKeyRepeat -int 15

# ------------------------- Trackpad -------------------------

info "Enabling tap to click on built-in trackpad..."
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadTapBehavior -int 1

info "Enabling tap to click on external Bluetooth trackpad..."
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

info "Enabling tap to click at login screen (global Mouse/Touchpad setting)..."
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# ------------------------- Security -------------------------

info "Requiring password immediately after sleep or screen saver..."
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

# ------------------------- File System ----------------------

info "Avoiding .DS_Store creation on network volumes..."
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

# ------------------------- Time Machine ---------------------

info "Preventing Time Machine from prompting to use new drives as backup..."
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

# ------------------------- Reload preferences -------------------------
# cfprefsd caches preferences on behalf of every running process. `defaults
# write` updates the on-disk plist, but the user's cfprefsd CONTINUES to
# serve the older cached values to apps that already opened the prefs
# (including the keyboard input services). Kill ONLY this user's cfprefsd
# instances so launchd can respawn them with the new values visible.
# The root-owned system daemon (PID owned by uid 0) is left alone — we
# don't have permission to signal it anyway, and a per-user agent restart
# is sufficient for our session's apps to pick up the change.
# A logged-out / logged-back-in session is still required for some
# keyboard repeat settings to be visible everywhere on macOS 13+.
_uid="$(id -u)"
_user_cfprefsd="$(pgrep -u "$_uid" -x cfprefsd || true)"
if [ -n "$_user_cfprefsd" ]; then
    info "Restarting this user's cfprefsd so the new defaults are picked up..."
    # shellcheck disable=SC2086
    kill $_user_cfprefsd 2>/dev/null || true
    # Wait briefly for launchd to bring it back up; if it doesn't, warn
    # rather than fail — the on-disk writes have already happened.
    for _ in 1 2 3 4 5; do
        sleep 1
        pgrep -u "$_uid" -x cfprefsd >/dev/null 2>&1 && break
    done
    pgrep -u "$_uid" -x cfprefsd >/dev/null 2>&1 || \
        warn "cfprefsd did not respawn; a log out / log in may be required."
else
    info "No per-user cfprefsd running; on-disk values will be read on next login."
fi

# ------------------------- Verify -------------------------
# Surface the final values so the user can confirm the writes actually
# landed. If a cached value still shows the old default, log out / log
# back in (or run this script after a reboot) for it to take effect.
info "Verifying applied keyboard settings (log out / log in if these differ from expected):"
printf '   %-32s %s\n' \
    "NSGlobalDomain ApplePressAndHoldEnabled" "$(defaults read NSGlobalDomain ApplePressAndHoldEnabled 2>&1)" \
    "NSGlobalDomain KeyRepeat"                  "$(defaults read NSGlobalDomain KeyRepeat 2>&1)" \
    "NSGlobalDomain InitialKeyRepeat"           "$(defaults read NSGlobalDomain InitialKeyRepeat 2>&1)" \
    "com.apple.HIToolbox  ApplePressAndHoldEnabled" "$(defaults read com.apple.HIToolbox ApplePressAndHoldEnabled 2>&1)" \
    "com.apple.HIToolbox  KeyRepeat"            "$(defaults read com.apple.HIToolbox KeyRepeat 2>&1)" \
    "com.apple.HIToolbox  InitialKeyRepeat"     "$(defaults read com.apple.HIToolbox InitialKeyRepeat 2>&1)"

info "All macOS settings applied. Log out / log back in for all changes to take effect."