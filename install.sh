#!/bin/sh
# Bootstrap script for the mcapanema/dotfiles setup.
#
# On a fresh machine it:
#   1. Ensures macOS build tools (git) are available via CLT.
#   2. Installs Homebrew if missing.
#   3. Clones / updates the dotfiles repo.
#   4. Installs Homebrew-managed tools (iterm2, chezmoi, zplug …).
#   5. Runs chezmoi apply to materialise the managed dotfiles.
#   6. Marks the install complete so later runs go via the update path.
#
# Safe to re-run; the install vs. update path is determined by whether
# $HOME/.dotfiles-installed exists.

set -eu
set -o pipefail

# ---------------------------- Constants ----------------------------
REPO_URL="https://github.com/mcapanema/dotfiles.git"
BREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
MARKER_FILE="$HOME/.dotfiles-installed"
DOTFILES_DIR="$HOME/.dotfiles"
DOTFILES_SOURCE_SUBDIR="dotfiles"

# ---------------------------- Helpers ----------------------------
info()  { echo "==> $*" ; }
warn()  { echo " WARNING: $*" ; }
fail()  { echo "ERROR: $*" >&2; exit 1 ; }

# has_brew   — true if Homebrew is on PATH
has_brew() {
    command -v brew >/dev/null 2>&1
}

# has_iterm2 — true if the Homebrew cask is installed
has_iterm2() {
    has_brew && brew list --cask iterm2 >/dev/null 2>&1
}

# has_zplug  — true if the Homebrew formula is installed
has_zplug() {
    has_brew && brew list zplug >/dev/null 2>&1
}

# has_chezmoi — true if chezmoi binary is on PATH
has_chezmoi() {
    command -v chezmoi >/dev/null 2>&1
}

has_nvim() {
    command -v nvim >/dev/null 2>&1
}

# vim-plug for Neovim: installed when the autoload file is missing.
vim_plug_installed() {
    [ -f "$HOME/.local/share/nvim/site/autoload/plug.vim" ]
}

# ---------------------------- Pre-flight: build tools ----------------------------
# On a completely fresh macOS install git is only available after the
# Command Line Tools package is installed.  CLT ships a git binary at
# /Library/Developer/CommandLineTools/usr/bin/git that is on PATH once
# xcode-select has been run.  This function:
#   1. Checks whether git already resolves (fast path on a configured box).
#   2. If not, tries to install CLT silently via softwareupdate(8)'s
#      --agree-to-license flag (works on macOS 13+ without user interaction).
#   3. Falls back to opening the standard GUI installer if step 2 fails.
#      The script blocks until the user dismisses the dialog or a 3-minute
#      timeout expires — this is the only interactive step that cannot be
#      avoided on a completely fresh machine.
ensure_build_tools() {
    if command -v git >/dev/null 2>&1; then
        info "git already available, skipping CLT setup."
        return 0
    fi

    info "git not found — ensuring Command Line Tools..."

    # Attempt silent install (no GUI) via softwareupdate(8).
    # --agree-to-license skips the licence prompt on macOS 13+.
    # We try twice because the package label may or may not carry a
    # version suffix (e.g. "Command Line Tools for Xcode" vs
    # "Command Line Tools for Xcode 26.5").
    _clt_installed=0
    for _ in 1 2; do
        if softwareupdate --install --agree-to-license -r \
            "Command Line Tools for Xcode" >/dev/null 2>&1; then
            _clt_installed=1
            break
        fi
        sleep 2
    done

    if [ "$_clt_installed" -eq 1 ]; then
        info "Command Line Tools installed silently."
    else
        # Silent install didn't apply (no matching update).  Fall back to
        # the standard GUI installer.  The script blocks here until the
        # user dismisses the dialog or 3 minutes elapse.
        warn "Silent CLT install failed — opening GUI installer."
        warn "After installation finishes, dismiss the dialog."
        warn "This script will resume automatically."
        xcode-select --install || true
    fi

    # Poll for up to 3 minutes for git to appear after the GUI install.
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
             21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36; do
        sleep 5
        if command -v git >/dev/null 2>&1; then
            info "git is now available."
            return 0
        fi
    done

    fail "Command Line Tools did not become available after 3 minutes. " \
         "Install Xcode Command Line Tools manually and re-run this script."
}

# ---------------------------- Check: already installed? ----------------------------
is_installed() {
    [ -f "$MARKER_FILE" ]
}

# ---------------------------- Fresh install ----------------------------
fresh_install() {
    info "Fresh install detected — setting up dotfiles..."

    # 1. Homebrew
    if ! has_brew; then
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL "$BREW_INSTALL_URL")"
        # shellcheck disable=SC1091
        if [ -x "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -x "/usr/local/bin/brew" ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
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

    # 3. Oh My Zsh
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        info "Installing Oh My Zsh..."
        git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
    else
        info "Oh My Zsh already installed, skipping."
    fi

    # 4. Import the committed iTerm2 preferences snapshot.
    #    apply-iterm.sh SIGTERMs any running iTerm2, then
    #    defaults-imports the version-controlled plist.
    if [ -f "${DOTFILES_DIR}/iterm2/apply-iterm.sh" ]; then
        info "Applying iTerm2 preferences..."
        sh "${DOTFILES_DIR}/iterm2/apply-iterm.sh"
    else
        warn "apply-iterm.sh not found; skipping iTerm2 configuration."
    fi

    # 5. zplug
    if ! has_zplug; then
        info "Installing zplug..."
        brew install zplug
    else
        info "zplug already installed, skipping."
    fi

    # 6. Neovim
    if ! has_nvim; then
        info "Installing Neovim..."
        brew install neovim
    else
        info "Neovim already installed, skipping."
    fi

    # 6b. Neovim config — copy from the dotfiles repo.  This runs
    # before chezmoi apply so the repo template is already in place.
    if [ -f "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/config/nvim/init.vim" ]; then
        _nvim_dir="$HOME/.config/nvim"
        mkdir -p "$_nvim_dir"
        info "Installing Neovim config..."
        cp "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/config/nvim/init.vim" \
           "$_nvim_dir/init.vim"
    fi

    # 6c. Symlink vim/vi → nvim in ~/.local/bin so typing "vim" or "vi"
    #     at a shell opens Neovim regardless of whether a system vim exists.
    #     ~/.local/bin is prepended to PATH via .zshenv.
    if [ -d "$HOME/.local/bin" ] || mkdir -p "$HOME/.local/bin"; then
        for _bin in vim vi; do
            ln -sf "$(command -v nvim)" "$HOME/.local/bin/$_bin" && \
                info "Created ~/.local/bin/$_bin → nvim"
        done
    fi

    # 6d. vim-plug for Neovim — download the plugin manager if not present.
    #     NERDTree (configured in init.vim) is managed by vim-plug.
    if ! vim_plug_installed; then
        info "Installing vim-plug for Neovim..."
        _plug_dir="$(eval echo ~/.local/share/nvim/site/autoload)"
        mkdir -p "$_plug_dir"
        curl -sfL 'https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim' \
            --output "$_plug_dir/plug.vim"
    fi

    # 6e. Run PlugInstall to fetch NERDTree and any other plugins.
    #     Runs non-interactively; skips if autoload dir is empty (no plugins declared).
    if vim_plug_installed && [ -s "$HOME/.config/nvim/init.vim" ]; then
        info "Installing Neovim plugins (NERDTree, ...)..."
        nvim --headless +PlugInstall +qall 2>/dev/null || \
            warn "Some Neovim plugins may not have been installed. Run :PlugInstall manually."
    fi

    # 7. chezmoi
    if ! has_chezmoi; then
        info "Installing chezmoi..."
        brew install chezmoi
    else
        info "chezmoi already installed, skipping."
    fi

    # 8. Apply dotfiles
    info "Applying dotfiles..."
    chezmoi apply --source "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}"

    # Ensure .zshrc is present (chezmoi may not overwrite an existing file).
    if [ -f "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/.zshrc" ]; then
        info "Copying .zshrc from dotfiles..."
        cp "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/.zshrc" "$HOME/.zshrc"
    fi

    # 9. zplug install — run in a clean zsh session without OME Zsh interference.
    info "Installing zsh plugins..."
    ZPLUG_HOME="$(brew --prefix)/opt/zplug"
    zsh -c "source $ZPLUG_HOME/init.zsh && zplug install"

    # 10. Set zsh as the login shell.
    if [ "$SHELL" != "/bin/zsh" ]; then
        info "Setting zsh as default shell..."
        chsh -s /bin/zsh 2>/dev/null || \
            warn "Could not set zsh as default shell (may need sudo)."
    else
        info "zsh already default shell, skipping."
    fi

    # Mark done
    touch "$MARKER_FILE"
    info "Dotfiles installed successfully."
}

# ---------------------------- Update ----------------------------
update() {
    info "Update detected — pulling latest changes..."

    # If dotfiles isn't a git repo (e.g. cloned as a tarball), re-run fresh install.
    if [ ! -d "${DOTFILES_DIR}/.git" ]; then
        warn "Dotfiles is not a git repo. Re-running fresh install."
        fresh_install
        return
    fi

    # Ensure the origin remote points to the right URL.
    current_remote="$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || echo '')"
    if [ "$current_remote" != "$REPO_URL" ]; then
        git -C "$DOTFILES_DIR" remote add origin "$REPO_URL" 2>/dev/null || \
            git -C "$DOTFILES_DIR" remote set-url origin "$REPO_URL"
    fi

    info "Pulling latest changes..."
    git -C "$DOTFILES_DIR" pull --rebase --autostash

    # Ensure managed tools are present.
    if ! has_brew; then
        warn "Homebrew not found; re-running fresh install."
        fresh_install
        return
    fi

    if ! has_chezmoi; then
        info "Installing chezmoi..."
        brew install chezmoi
    fi

    if ! has_zplug; then
        info "Installing zplug..."
        brew install zplug
    fi

    if ! has_nvim; then
        info "Installing Neovim..."
        brew install neovim
    fi

    # Keep Neovim config in sync with the dotfiles repo.
    if [ -f "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/config/nvim/init.vim" ]; then
        mkdir -p "$HOME/.config/nvim"
        info "Updating Neovim config..."
        cp "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/config/nvim/init.vim" \
           "$HOME/.config/nvim/init.vim"
    fi

    # Keep vim/vi → nvim symlinks in sync.
    if mkdir -p "$HOME/.local/bin" 2>/dev/null; then
        for _bin in vim vi; do
            ln -sf "$(command -v nvim)" "$HOME/.local/bin/$_bin" 2>/dev/null || true
        done
    fi

    # Keep vim-plug and plugins in sync.
    if ! vim_plug_installed; then
        info "Installing vim-plug for Neovim..."
        _plug_dir="$(eval echo ~/.local/share/nvim/site/autoload)"
        mkdir -p "$_plug_dir"
        curl -sfL 'https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim' \
            --output "$_plug_dir/plug.vim"
    fi
    if vim_plug_installed; then
        info "Updating Neovim plugins..."
        nvim --headless +PlugInstall +qall 2>/dev/null || true
    fi

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        warn "Oh My Zsh missing — re-running fresh install."
        fresh_install
        return
    fi

    # Re-apply the iTerm2 preferences snapshot.
    if [ -f "${DOTFILES_DIR}/iterm2/apply-iterm.sh" ]; then
        info "Re-applying iTerm2 preferences..."
        sh "${DOTFILES_DIR}/iterm2/apply-iterm.sh" || true
    fi

    # Re-apply chezmoi-managed dotfiles.
    info "Applying updated dotfiles..."
    chezmoi apply --source "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}"

    # Keep .zshrc in sync.
    if [ -f "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/.zshrc" ]; then
        cp "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/.zshrc" "$HOME/.zshrc"
    fi

    # Re-run zplug install to pick up any new plugins.
    info "Re-installing zsh plugins..."
    ZPLUG_HOME="$(brew --prefix)/opt/zplug"
    zsh -c "source $ZPLUG_HOME/init.zsh && zplug install"

    info "Dotfiles updated successfully."
}

# ---------------------------- Entry point ----------------------------
main() {
    echo ""
    echo "dotfiles bootstrap"
    echo "=================="
    echo ""

    # Pre-flight: make sure git is available before we try to clone or pull.
    ensure_build_tools

    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        info "Cloning dotfiles into $DOTFILES_DIR..."
        git clone --depth 1 "$REPO_URL" "$DOTFILES_DIR"
    else
        info "Dotfiles already present, skipping clone."
    fi

    # Always cd into the repo so subsequent git/chezmoi commands work
    # regardless of the current working directory at script invocation.
    cd "$DOTFILES_DIR"

    if is_installed; then
        update
    else
        fresh_install
    fi

    echo ""
    echo "Done! Next steps:"
    echo "  1. Restart iTerm2   (Snazzy theme and preferences are applied)"
    echo "  2. Restart zsh      (plugins and .zshrc are now active)"
    echo ""
}

main "$@"