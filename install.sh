#!/bin/sh
# Bootstrap script for the mcapanema/dotfiles setup.
#
# On a fresh machine it:
#   - Applies macOS system preferences (keyboard, trackpad, security,
#     file system, Time Machine).
#   - Ensures macOS build tools (CLT/git) are available — required
#     because Homebrew's installer needs git to bootstrap itself.
#   - Installs Homebrew and git via Homebrew.
#   - Clones the dotfiles repo.
#   - Installs Homebrew-managed tools (iTerm2, chezmoi, zplug …).
#   - Opens iTerm2 once (to register its defaults domain), then applies
#     the committed iTerm2 preferences snapshot.
#   - Installs Claude Code and the opencode CLI, including managed config.
#   - Runs chezmoi apply to materialise the managed dotfiles.
#   - Marks the install complete so later runs go via the update path.
#
# Safe to re-run; the install vs. update path is determined by whether
# $HOME/.dotfiles-installed exists.

set -euo pipefail

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

# has — true if a command resolves on PATH
has() { command -v "$1" >/dev/null 2>&1; }

# has_brew   — true if Homebrew is on PATH
has_brew() { has brew; }

# brew_pkg_installed — true if a Homebrew formula or cask is installed.
# Used by has_iterm2/has_zplug and inline checks (e.g. JetBrains Mono).
brew_pkg_installed() { has_brew && brew list "$1" >/dev/null 2>&1; }

# has_iterm2 — true if the Homebrew cask is installed
has_iterm2() { brew_pkg_installed iterm2; }

# has_zplug  — true if the Homebrew formula is installed
has_zplug()  { brew_pkg_installed zplug; }

# brew_install_if_missing — install a Homebrew formula/cask if not present.
#   $1: human-readable name for log lines (e.g. "iTerm2", "zplug")
#   $2: package name (e.g. iterm2, zplug, font-jetbrains-mono)
#   $3+: optional brew install flags (e.g. --cask)
brew_install_if_missing() {
    _kind="$1"; _pkg="$2"; shift 2
    if brew_pkg_installed "$_pkg"; then
        info "$_kind already installed, skipping."
    else
        info "Installing $_kind..."
        brew install "$@" "$_pkg"
    fi
}

# has_chezmoi — true if chezmoi binary is on PATH
has_chezmoi() { has chezmoi; }

has_nvim() { has nvim; }

# has_claude   — true if Claude Code CLI/App binary is on PATH
has_claude() { has claude; }

# has_opencode — true if the opencode CLI binary is on PATH
has_opencode() { has opencode; }

# ensure_brew_on_path — re-sources brew's shellenv so `brew` resolves.
# Used after a fresh brew install and at the top of every update run.
ensure_brew_on_path() {
    if [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    if ! has brew; then
        fail "Homebrew is installed but 'brew' is not on PATH."
    fi
}

# vim-plug for Neovim: installed when the autoload file is missing.
vim_plug_installed() {
    [ -f "$HOME/.local/share/nvim/site/autoload/plug.vim" ]
}

# install_homebrew — installs Homebrew if missing, then ensures it is on PATH.
# Idempotent. Used both as a hard dependency of this repo (called before clone)
# and inside fresh_install.
install_homebrew() {
    if has_brew; then
        ensure_brew_on_path
        return 0
    fi
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL "$BREW_INSTALL_URL")"
    ensure_brew_on_path
}

# ensure_brew_git — guarantees a Homebrew-managed git binary is present and
# resolvable. Treats brew as a hard dependency of this repo so a freshly
# cloned machine does not depend on Apple's older CLT git.
ensure_brew_git() {
    install_homebrew
    _brew_prefix="$(brew --prefix)"
    if [ -x "$_brew_prefix/bin/git" ] && \
       "$_brew_prefix/bin/git" --version >/dev/null 2>&1; then
        info "brew git already available at $_brew_prefix/bin/git"
        return 0
    fi
    info "Installing git via Homebrew..."
    brew install git
}

# ensure_git — installs brew + brew-managed git as dependencies before any
# `git clone` of this repo. If brew is somehow unreachable, falls back to
# the CLT-based path via ensure_build_tools.
ensure_git() {
    ensure_brew_git
    # Final sanity: `git` must actually resolve on PATH at this point.
    if ! command -v git >/dev/null 2>&1; then
        warn "brew-supplied git not on PATH — falling back to CLT."
        ensure_build_tools
    fi
    command -v git >/dev/null 2>&1 || \
        fail "git is not available; install Xcode CLT or Homebrew manually."
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
    for _ in 1 2; do
        softwareupdate --install --agree-to-license -r \
            "Command Line Tools for Xcode" >/dev/null 2>&1 && break
        sleep 2
    done

    # softwareupdate exits 0 even when there was nothing to install.
    # Verify git is actually on PATH rather than trusting the exit code.
    if command -v git >/dev/null 2>&1; then
        info "CLT / git is now available."
    else
        # Silent install didn't apply (no matching update).  Fall back to
        # the standard GUI installer.  The script blocks here until the
        # user dismisses the dialog or 3 minutes elapse.
        warn "Silent CLT install failed — opening GUI installer."
        warn "After installation finishes, dismiss the dialog."
        warn "This script will resume automatically."
        warn "If the dialog stays open longer than 3 minutes, Ctrl-C and"
        warn "re-run this script after CLT is installed."
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

    # --- macOS system preferences
    # Apply first so keyboard repeat, tap-to-click, etc. take effect even
    # if the user logs out partway through the install.  `defaults write`
    # calls are idempotent.
    if [ -x "${DOTFILES_DIR}/macos/apply-settings.sh" ]; then
        info "Applying macOS system preferences..."
        DOTFILES="$DOTFILES_DIR" sh "${DOTFILES_DIR}/macos/apply-settings.sh" || \
            warn "macOS system preferences partially failed; you can rerun apply-settings.sh manually."
    else
        warn "macos/apply-settings.sh not found; skipping macOS defaults."
    fi

    # --- Homebrew
    install_homebrew

    # --- Fonts
    # JetBrains Mono is referenced by the iTerm2 preferences snapshot
    # (JetBrainsMono-Regular) and by Neovim's init.vim.  Install it via
    # Homebrew so the font is available for iTerm2 to use immediately
    # after the preferences are applied.
    brew_install_if_missing "JetBrains Mono" font-jetbrains-mono --cask

    # --- git via Homebrew
    # Install the brew-managed git so it takes precedence over CLT's older
    # git for all subsequent operations (Oh My Zsh clone, vim-plug plugin
    # installs, etc.).
    info "Installing git via Homebrew..."
    brew install git

    # --- iTerm2
    brew_install_if_missing "iTerm2" iterm2 --cask

    # --- Oh My Zsh
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        info "Installing Oh My Zsh..."
        git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
    else
        info "Oh My Zsh already installed, skipping."
    fi

    # --- iTerm2 preferences
    # apply-iterm.sh SIGTERMs any running iTerm2, then defaults-imports
    # the version-controlled plist.  On a fresh install iTerm2's prefs
    # domain isn't registered with defaults(1) until the .app has been
    # launched at least once; we open it briefly here so the import works.
    if [ -f "${DOTFILES_DIR}/iterm2/apply-iterm.sh" ]; then
        if [ -d "/Applications/iTerm.app" ] && \
           ! pgrep -f "iTerm.app/Contents/MacOS/iTerm2" >/dev/null 2>&1; then
            info "Launching iTerm2 once to register its defaults domain..."
            open -a iTerm 2>/dev/null || true
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                sleep 1
                pgrep -f "iTerm.app/Contents/MacOS/iTerm2" >/dev/null 2>&1 && break
            done
        fi
        info "Applying iTerm2 preferences..."
        DOTFILES="$DOTFILES_DIR" sh "${DOTFILES_DIR}/iterm2/apply-iterm.sh" || \
            warn "apply-iterm.sh failed; you can rerun it manually after opening iTerm2 once."
    else
        warn "apply-iterm.sh not found; skipping iTerm2 configuration."
    fi

    # --- zplug
    brew_install_if_missing "zplug" zplug

    # --- Neovim
    brew_install_if_missing "Neovim" neovim

    # --- Neovim config
    if [ -f "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/config/nvim/init.vim" ]; then
        _nvim_dir="$HOME/.config/nvim"
        mkdir -p "$_nvim_dir"
        info "Installing Neovim config..."
        cp "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/config/nvim/init.vim" \
           "$_nvim_dir/init.vim"
    fi

    # --- vim/vi → nvim symlinks
    # ~/.local/bin is prepended to PATH via .zshenv so these take priority
    # over any system vim in /usr/bin or /usr/local/bin.
    if [ -d "$HOME/.local/bin" ] || mkdir -p "$HOME/.local/bin"; then
        for _bin in vim vi; do
            ln -sf "$(command -v nvim)" "$HOME/.local/bin/$_bin" && \
                info "Created ~/.local/bin/$_bin → nvim"
        done
    fi

    # --- vim-plug
    if ! vim_plug_installed; then
        info "Installing vim-plug for Neovim..."
        _plug_dir="$HOME/.local/share/nvim/site/autoload"
        mkdir -p "$_plug_dir"
        curl -sfL 'https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim' \
            --output "$_plug_dir/plug.vim"
    fi

    # --- Neovim plugins
    if vim_plug_installed && [ -s "$HOME/.config/nvim/init.vim" ]; then
        info "Installing Neovim plugins (NERDTree, ...)..."
        nvim --headless +PlugInstall +qall 2>/dev/null || \
            warn "Some Neovim plugins may not have been installed. Run :PlugInstall manually."
    fi

    # --- chezmoi
    brew_install_if_missing "chezmoi" chezmoi

    # --- Claude Code CLI + config
    brew_install_if_missing "Claude Code" claude-code
    if [ -x "${DOTFILES_DIR}/claude/install.sh" ]; then
        info "Applying Claude Code configuration..."
        sh "${DOTFILES_DIR}/claude/install.sh"
    else
        warn "claude/install.sh not found; skipping Claude Code configuration."
    fi

    # --- opencode CLI
    brew_install_if_missing "opencode CLI" opencode

    # --- chezmoi apply
    info "Applying dotfiles..."
    chezmoi apply --source "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}"

    # Ensure .zshrc is present (chezmoi may not overwrite an existing file).
    if [ -f "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/.zshrc" ]; then
        info "Copying .zshrc from dotfiles..."
        cp "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/.zshrc" "$HOME/.zshrc"
    fi

    # --- zplug install
    # Run in a clean zsh session without Oh My Zsh interfering.
    # Tolerant of non-zero exit (e.g. zplug re-clobbers comp files) so the
    # bootstrap path is not blocked by an optional cosmetic step.
    info "Installing zsh plugins..."
    ZPLUG_HOME="$(brew --prefix)/opt/zplug"
    zsh -c "source $ZPLUG_HOME/init.zsh && zplug install" \
        || warn "zplug install returned non-zero; you can run it manually later."

    # --- zsh as login shell
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

    # Re-apply macOS system preferences (idempotent; keeps prefs in sync
    # when apply-settings.sh is updated).
    if [ -x "${DOTFILES_DIR}/macos/apply-settings.sh" ]; then
        DOTFILES="$DOTFILES_DIR" sh "${DOTFILES_DIR}/macos/apply-settings.sh" || true
    fi

    # Ensure brew is on PATH — needed because subsequent `brew --prefix` and
    # `brew install` calls depend on it regardless of how the parent shell
    # was started.
    ensure_brew_on_path

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

    # Keep JetBrains Mono font in sync in case it was updated.
    if ! brew_pkg_installed font-jetbrains-mono; then
        info "Installing JetBrains Mono font..."
        brew install --cask font-jetbrains-mono
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

    if ! has_claude; then
        info "Installing Claude Code..."
        brew install claude-code
    fi

    if ! has_opencode; then
        info "Installing opencode CLI..."
        brew install opencode
    fi

    # Ensure Claude Code managed configuration is in place.  The
    # sub-script is idempotent, so re-running is safe.
    if [ -x "${DOTFILES_DIR}/claude/install.sh" ]; then
        sh "${DOTFILES_DIR}/claude/install.sh" || true
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
        _plug_dir="$HOME/.local/share/nvim/site/autoload"
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
        DOTFILES="$DOTFILES_DIR" sh "${DOTFILES_DIR}/iterm2/apply-iterm.sh" || true
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
    zsh -c "source $ZPLUG_HOME/init.zsh && zplug install" \
        || warn "zplug install returned non-zero; you can run it manually later."

    info "Dotfiles updated successfully."
}

# ---------------------------- Entry point ----------------------------
main() {
    echo ""
    echo "dotfiles bootstrap"
    echo "=================="
    echo ""

    # Pre-flight: brew and brew-managed git are hard dependencies of this
    # repo. When the repo is absent we must install them before cloning.
    # When the repo is already present we only need a working `git` for
    # `git pull`, so the cheap CLT-aware path is sufficient.
    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        info "Repository not yet cloned — installing brew and brew-managed git as dependencies..."
        ensure_git
        info "Cloning dotfiles into $DOTFILES_DIR..."
        git clone --depth 1 "$REPO_URL" "$DOTFILES_DIR"
    else
        info "Dotfiles already present, skipping clone."
        ensure_build_tools
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