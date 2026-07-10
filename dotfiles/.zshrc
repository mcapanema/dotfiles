# Shell behaviour
set -o vi                  # Vi keybindings for the line editor
bindkey -v                 # Ensure vi keymap is active (coexists with set -o vi)
alias rm='nocorrect rm'    # Prevent zsh spell-checker from correcting 'rm'

# Oh My Zsh configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=(git)
source $ZSH/oh-my-zsh.sh

# zplug configuration
export ZPLUG_HOME=$(brew --prefix)/opt/zplug
source $ZPLUG_HOME/init.zsh

zplug "mafredri/zsh-async", use:async.zsh, from:github
zplug "sindresorhus/pure", use:pure.zsh, from:github, as:theme
zplug "zsh-users/zsh-syntax-highlighting", as:plugin, defer:2
zplug "zsh-users/zsh-autosuggestions", as:plugin, defer:2

zplug load

# Auto-install plugins if missing (interactive shells only — keeps
# non-interactive runs like install.sh non-blocking).
if [ -t 0 ] && ! zplug check --verbose; then
    printf "Install plugins? [y/N]: "
    if read -q; then
        echo; zplug install
    fi
fi

# Local bin
export PATH="$HOME/.local/bin:$PATH"

# ---- Dev toolchains (sourced after OMZ/zplug so PATH manipulation wins) ----

# nvm (Node version manager) — brew formula
export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix)/opt/nvm/nvm.sh" ] && . "$(brew --prefix)/opt/nvm/nvm.sh"

# rvm (Ruby version manager) — installed via official installer from get.rvm.io
# Add rvm binary dir for non-interactive shells (cheap; no init cost)
case ":${PATH}:" in
  *":$HOME/.rvm/bin:"*) ;;
  *) export PATH="$HOME/.rvm/bin:$PATH" ;;
esac
# Source rvm if present — must come AFTER nvm so rvm's PATH adjustments win
[ -s "$HOME/.rvm/scripts/rvm" ] && . "$HOME/.rvm/scripts/rvm"

# Rust (rustup) — brew's keg-only rustup formula's shims live at
# /opt/homebrew/opt/rustup/bin (already on PATH via .zprofile).
# `~/.cargo/env` is sourced if it exists (for non-brew rustup installs).
[ -s "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# uv / pipx — pipx installs go to ~/.local/bin (already on PATH above)