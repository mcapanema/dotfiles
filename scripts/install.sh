#!/bin/zsh
set -e

echo "==> Installing Homebrew..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo "==> Installing chezmoi..."
brew install chezmoi

echo "==> Initializing chezmoi from dotfiles repo..."
chezmoi init https://github.com/mcapanema/dotfiles

echo "==> Applying dotfiles..."
# source-dir is the cloned repo; managed files live in the dotfiles/ subdirectory
chezmoi apply --source "$(chezmoi source-path)/dotfiles"

echo "==> Installing zplug..."
brew install zplug

echo "==> Installing plugins..."
zsh -i -c "zplug install"

echo "==> Importing iTerm2 preferences..."
SOURCE="$(chezmoi source-path)"
open "$SOURCE/iterm2/Snazzy.itermcolors"
cp "$SOURCE/iterm2/com.googlecode.iterm2.plist ~/Library/Preferences/

echo ""
echo "Done! Please:"
echo "  1. Restart iTerm2"
echo "  2. Select Snazzy theme: Preferences > Profiles > Colors > Color Presets > Snazzy"
echo "  3. Restart zsh"