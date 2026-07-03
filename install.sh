#!/bin/sh
set -e

# ---------------------------- Constants ----------------------------
REPO_URL="https://github.com/mcapanema/dotfiles"
BREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
MARKER_FILE="$HOME/.dotfiles-installed"
CHEZMOI_SOURCE_DIR="${HOME}/.local/share/chezmoi"
DOTFILES_SUBDIR="dotfiles"

# ---------------------------- Messages ----------------------------
info()  { echo "==> $*" ; }
warn()  { echo " WARNING: $*" ; }
success(){ echo "==> $*" ; }

# ---------------------------- Check: already installed? ----------------------------
is_installed(){
    [ -f "$MARKER_FILE" ] && return 0
    [ -d "${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}" ] && return 0
    return 1
}

# ---------------------------- Check: binary ----------------------------
has_brew() {
    command -v brew >/dev/null 2>&1
}

has_iterm2() {
    has_brew && brew list --cask iterm2 >/dev/null 2>&1
}

has_zplug() {
    has_brew && brew list zplug >/dev/null 2>&1
}

has_chezmoi() {
    command -v chezmoi >/dev/null 2>&1
}

# ---------------------------- Fresh install ----------------------------
fresh_install(){
    info "Fresh install detected — setting up dotfiles..."

    DOTFILES_DIR="$HOME/.dotfiles"

    # 1. Homebrew
    if ! has_brew; then
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL "$BREW_INSTALL_URL")"
        BREW_BIN=$(command -v brew)
        [ -n "$BREW_BIN" ] && eval "$($BREW_BIN shellenv)"
    else
        info "Homebrew already installed, skipping."
    fi

    # 2. iTerm2
    if ! has_iterm2; then
        info "Installing iTerm2..."
        brew install --cask iterm2
    else
        info "iTerm2 already installed, skipping."
    fi

    # 7. Clone dotfiles repo (needed for theme and subsequent steps)
    if [ ! -d "$CHEZMOI_SOURCE_DIR/.git" ]; then
        info "Cloning dotfiles repo..."
        git clone --depth 1 "$REPO_URL" "$CHEZMOI_SOURCE_DIR"
    else
        info "Dotfiles repo already exists, skipping clone."
    fi

    # 3. iTerm2 Snazzy theme — force-applied to the Default Profile.
    # Note: we deliberately do NOT copy this into
    # ~/Library/Application Support/iTerm2/DynamicProfiles/, because the
    # colors file embeds a fixed GUID that conflicts with the default
    # bookmark's GUID and triggers:
    #   "Dynamic profile with Guid ... conflicts with non-dynamic profile
    #    with same Guid"
    # apply-snazzy.sh reads from the dotfiles repo directly.
    COLORS_SRC="${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}/iterm2/Snazzy.itermcolors"
    sh "${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}/iterm2/apply-snazzy.sh"

    # 4. Oh My Zsh
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        info "Installing Oh My Zsh..."
        RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    else
        info "Oh My Zsh already installed, skipping."
    fi

    # 5. zplug
    if ! has_zplug; then
        info "Installing zplug..."
        brew install zplug
    else
        info "zplug already installed, skipping."
    fi

    # 6. chezmoi
    if ! has_chezmoi; then
        info "Installing chezmoi..."
        brew install chezmoi
    else
        info "chezmoi already installed, skipping."
    fi

    # 8. Apply dotfiles
    info "Applying dotfiles (source: ${DOTFILES_SUBDIR}/)..."
    chezmoi apply --source "${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}"

    # Ensure .zshrc is copied (chezmoi may not overwrite existing files)
    if [ -f "${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}/.zshrc" ]; then
        info "Copying .zshrc from dotfiles..."
        cp "${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}/.zshrc" "$HOME/.zshrc"
    fi

    # 9. zplug install (run in zsh)
    info "Installing zsh plugins..."
    zsh -c 'source "${HOME}/.zshrc" && zplug install' 2>/dev/null || true

    # 10. Set zsh as default shell
    if [ "$SHELL" != "/bin/zsh" ]; then
        info "Setting zsh as default shell..."
        chsh -s /bin/zsh
    else
        info "zsh already default shell, skipping."
    fi

    # Mark as installed
    touch "$MARKER_FILE"
    success "Dotfiles installed successfully."
}

# ---------------------------- Update ----------------------------
update(){
    info "Update detected — pulling latest changes..."

    if [ ! -d "${CHEZMOI_SOURCE_DIR}/.git" ]; then
        warn "Chezmoi source is not a git repo. Re-running fresh install."
        fresh_install
        return
    fi

    current_remote=$(git -C "$CHEZMOI_SOURCE_DIR" remote get-url origin 2>/dev/null || echo "")
    if [ "$current_remote" != "$REPO_URL" ]; then
        git -C "$CHEZMOI_SOURCE_DIR" remote add origin "$REPO_URL" 2>/dev/null || \
            git -C "$CHEZMOI_SOURCE_DIR" remote set-url origin "$REPO_URL"
    fi

    info "Pulling latest changes..."
    git -C "$CHEZMOI_SOURCE_DIR" pull --rebase --autostash

    if ! has_chezmoi; then
        info "Installing chezmoi..."
        brew install chezmoi
    fi

    if ! has_zplug; then
        info "Installing zplug..."
        brew install zplug
    fi

    info "Applying updated dotfiles..."
    chezmoi apply --source "${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}"

    # Ensure .zshrc is updated
    if [ -f "${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}/.zshrc" ]; then
        cp "${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}/.zshrc" "$HOME/.zshrc"
    fi

    # Re-apply Snazzy to the Default Profile
    if [ -f "${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}/iterm2/Snazzy.itermcolors" ]; then
        sh "${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}/iterm2/apply-snazzy.sh" || true
    fi

    info "Re-running zplug install..."
    zsh -c 'source "${HOME}/.zshrc" && zplug install' 2>/dev/null || true

    success "Dotfiles updated successfully."
}

# ---------------------------- Main ----------------------------
main(){
    echo ""
    echo "dotfiles bootstrap"
    echo "=================="
    echo ""

    DOTFILES_DIR="$HOME/.dotfiles"
    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        info "Cloning dotfiles into $DOTFILES_DIR..."
        git clone --depth 1 "$REPO_URL" "$DOTFILES_DIR"
        cd "$DOTFILES_DIR"
    else
        info "Dotfiles already present at $DOTFILES_DIR, skipping clone."
        cd "$DOTFILES_DIR"
    fi

    if is_installed; then
        update
    else
        fresh_install
    fi

    echo ""
    echo "Done! Next steps:"
    echo "  1. Restart iTerm2 (Snazzy is already applied to the Default Profile)"
    echo "  2. Restart zsh"
    echo ""
}

main "$@"
