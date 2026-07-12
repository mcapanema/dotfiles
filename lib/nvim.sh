#!/bin/sh
# lib/nvim.sh — Neovim setup helpers.  Sourced (never executed directly)
# by install.sh.  Reference DOTFILES_DIR and DOTFILES_SOURCE_SUBDIR from
# the outer scope (set by install.sh's Constants block).
#
# Functions are idempotent so they're safe to call from both fresh_install
# and update.
#
# CHEZMOI RELATIONSHIP
#   dotfiles/config/nvim/init.vim IS a chezmoi-managed file (chezmoi managed
#   lists it; `chezmoi apply` materialises it to ~/.config/nvim/init.vim).
#   sync_neovim_config below also force-copies the same file BEFORE
#   `chezmoi apply` runs in fresh_install/update.  The redundancy is
#   intentional: install_nvim_plugins (nvim --headless +PlugInstall) needs
#   init.vim present on disk before chezmoi apply has run.  Reordering so
#   `chezmoi apply` precedes `install_nvim_plugins` would eliminate the
#   duplication but make the orchestrator flow harder to follow; the
#   harmless redundant cp is kept as a safety net.  Do not remove
#   sync_neovim_config without also reordering the orchestrators — see
#   CLAUDE.md §6 for the full rationale.

# vim_plug_installed — true if the vim-plug autoload script is present.
vim_plug_installed() {
    [ -f "$HOME/.local/share/nvim/site/autoload/plug.vim" ]
}

# sync_neovim_config — copies the managed init.vim into ~/.config/nvim.
# No-op if the source file is missing from the repo.
#
# Redundant with `chezmoi apply` (the file is chezmoi-managed) but kept
# as an intentional pre-apply copy because install_nvim_plugins needs
# init.vim on disk to run :PlugInstall against, and that step currently
# executes before `chezmoi apply`.  See file header for the full story.
sync_neovim_config() {
    if [ ! -f "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/config/nvim/init.vim" ]; then
        return 0
    fi
    mkdir -p "$HOME/.config/nvim"
    info "Syncing Neovim config..."
    cp "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/config/nvim/init.vim" \
       "$HOME/.config/nvim/init.vim"
}

# sync_nvim_symlinks — links ~/.local/bin/{vim,vi} to whatever `nvim`
# resolves to.  ~/.local/bin is prepended to PATH via .zshenv so these
# take priority over any system vim in /usr/bin or /usr/local/bin.
#   $1: tolerance — "warn" surfaces per-link success, "true" silences
#       everything; defaults to "warn".
sync_nvim_symlinks() {
    _tolerance="${1:-warn}"
    _target="$(command -v nvim 2>/dev/null)" || return 0
    mkdir -p "$HOME/.local/bin"
    for _bin in vim vi; do
        if [ "$_tolerance" = "warn" ]; then
            ln -sf "$_target" "$HOME/.local/bin/$_bin" \
                && info "Created ~/.local/bin/$_bin → nvim"
        else
            ln -sf "$_target" "$HOME/.local/bin/$_bin" 2>/dev/null || true
        fi
    done
}

# ensure_vim_plug — installs vim-plug's autoload script if absent.
ensure_vim_plug() {
    if vim_plug_installed; then
        return 0
    fi
    info "Installing vim-plug for Neovim..."
    _plug_dir="$HOME/.local/share/nvim/site/autoload"
    mkdir -p "$_plug_dir"
    curl -sfL 'https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim' \
        --output "$_plug_dir/plug.vim"
}

# install_nvim_plugins — runs :PlugInstall non-interactively.  Tolerates
# plugin-install errors (see original comments at fresh_install:308 and
# update:474 for context).
#   $1: tolerance — "warn" surfaces failures, "true" swallows them.
install_nvim_plugins() {
    if ! vim_plug_installed || [ ! -s "$HOME/.config/nvim/init.vim" ]; then
        return 0
    fi
    info "Syncing Neovim plugins..."
    nvim --headless +PlugInstall +qall 2>/dev/null || \
        [ "${1:-warn}" = "true" ] || \
        warn "Some Neovim plugins may not have been installed. Run :PlugInstall manually."
}
