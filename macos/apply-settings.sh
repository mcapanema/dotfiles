#!/bin/sh
# Apply a set of sensible macOS system defaults for a developer workstation.
# Safe to re-run; all writes are idempotent.
#
# Key notes for modern macOS:
#   - ApplePressAndHoldEnabled / KeyRepeat / InitialKeyRepeat on NSGlobalDomain
#     are deprecated since macOS 13 but still accepted by defaults(1). They
#     may be overridden by the Keyboard system settings panel. On macOS 13+
#     the recommended path is the Accessibility Keyboard pane, but writing the
#     keys here is harmless and covers clean-sheet installs.
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

info "Setting fast keyboard repeat rate (KeyRepeat=1, InitialKeyRepeat=15)..."
defaults write NSGlobalDomain KeyRepeat -int 1
defaults write NSGlobalDomain InitialKeyRepeat -int 15

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

info "All macOS settings applied. Log out / log back in for all changes to take effect."