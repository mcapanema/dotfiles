#!/bin/zsh
set -e

# ---------------------------- Constants ----------------------------
readonly REPO_URL="https://github.com/mcapanema/dotfiles"
readonly BREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
readonly MARKER_FILE="$HOME/.dotfiles-installed"
readonly CHEZMOI_SOURCE_DIR="${HOME}/.local/share/chezmoi"
readonly DOTFILES_SUBDIR="dotfiles"

# ---------------------------- Messages ----------------------------
info()  { echo "==> $*" }
warn()  { echo " WARNING: $*" }
success(){ echo "==> $*" }

# ---------------------------- Check: already installed? ----------------------------
is_installed(){
    # Check for marker file or chezmoi source with our repo's dotfiles subdirectory
    [[ -f "$MARKER_FILE" ]] && return 0
    [[ -d "${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}" ]] && return 0
    return 1
}

# ---------------------------- Check: binary ----------------------------
has(){
    command -v "$1" >/dev/null 2>&1
}

# ---------------------------- Fresh install ----------------------------
fresh_install(){
    info "Fresh install detected — setting up dotfiles..."

    if ! has brew; then
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL "$BREW_INSTALL_URL")"
    else
        info "Homebrew already installed, skipping."
    fi

    if ! has chezmoi; then
        info "Installing chezmoi..."
        brew install chezmoi
    else
        info "chezmoi already installed, skipping."
    fi

    info "Cloning dotfiles repo..."
    # Clone into chezmoi source dir (no remote, just the files)
    git clone --depth 1 "$REPO_URL" "$CHEZMOI_SOURCE_DIR"

    info "Applying dotfiles (source: ${DOTFILES_SUBDIR}/)..."
    chezmoi apply --source "${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}"

    info "Installing zplug..."
    if ! has zplug; then
        brew install zplug
    else
        info "zplug already installed, skipping."
    fi

    info "Installing zsh plugins..."
    zsh -i -c "zplug install" 2>/dev/null || true

    info "Importing iTerm2 preferences..."
    open "${CHEZMOI_SOURCE_DIR}/iterm2/Snazzy.itermcolors"
    cp "${CHEZMOI_SOURCE_DIR}/iterm2/com.googlecode.iterm2.plist \
        ~/Library/Preferences/

    # Mark as installed
    touch "$MARKER_FILE"
    success "Dotfiles installed successfully."
}

# ---------------------------- Update ----------------------------
update(){
    info "Update detected — pulling latest changes..."

    if [[ ! -d "${CHEZMOI_SOURCE_DIR}/.git" ]]; then
        warn "Chezmoi source is not a git repo. Re-running fresh install."
        fresh_install
        return
    fi

    # Ensure remote points to our repo
    local current_remote
    current_remote=$(git -C "$CHEZMOI_SOURCE_DIR" remote get-url origin 2>/dev/null || echo "")
    if [[ "$current_remote" != "$REPO_URL" ]]; then
        git -C "$CHEZMOI_SOURCE_DIR" remote add origin "$REPO_URL" 2>/dev/null \
            || git -C "$CHEZMOI_SOURCE_DIR" remote set-url origin "$REPO_URL"
    fi

    info "Pulling latest changes..."
    git -C "$CHEZMOI_SOURCE_DIR" pull --ff --autorebase

    info "Applying updated dotfiles..."
    chezmoi apply --source "${CHEZMOI_SOURCE_DIR}/${DOTFILES_SUBDIR}"

    success "Dotfiles updated successfully."
}

# ---------------------------- Main ----------------------------
main(){
    echo ""
    echo "dotfiles bootstrap"
    echo "=================="
    echo ""

    if is_installed; then
        update
    else
        fresh_install
    fi

    echo ""
    echo "Done! Next steps:"
    echo "  1. Restart iTerm2"
    echo "  2. Select Snazzy theme: Preferences > Profiles > Colors > Color Presets > Snazzy"
    echo "  3. Restart zsh"
    echo ""
}

main "$@"