#!/bin/zsh
set -e

echo "==> Installing Homebrew..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo "==> Installing chezmoi..."
brew install chezmoi

echo "==> Initializing chezmoi from dotfiles repo..."
chezmoi init https://github.com/mcapanema/dotfiles
chezmoi apply

echo "==> Installing zplug..."
brew install zplug

echo "==> Installing plugins..."
zsh -i -c "zplug install"

echo "==> Importing iTerm2 preferences..."
open $(chezmoi source-path)/iterm2/Snazzy.itermcolors
cp $(chezmoi source-path)/iterm2/com.googlecode.iterm2.plist ~/Library/Preferences/

echo ""
echo "Done! Please:"
echo "  1. Restart iTerm2"
echo "  2. Select Snazzy theme: Preferences > Profiles > Colors > Color Presets > Snazzy"
echo "  3. Restart zsh"