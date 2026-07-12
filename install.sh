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
#
# LIBRARY LAYOUT
#   install.sh inlines a minimal set of bootstrap primitives at the top
#   because $DOTFILES_DIR/lib/ does not yet exist when this script runs
#   via the curl-bootstrap command (we haven't cloned the repo yet).
#   Once the repo is cloned install.sh sources the canonical versions
#   from lib/common.sh, lib/bootstrap.sh, lib/brew-packages.sh, and
#   lib/nvim.sh — those sources redefine the same functions and the
#   maintainer-owned versions win.  Keep the inline bootstrap copy in
#   sync with lib/bootstrap.sh when editing either file.

set -eu
set -o pipefail

# ---------------------------- Constants ----------------------------
REPO_URL="https://github.com/mcapanema/dotfiles.git"
MARKER_FILE="$HOME/.dotfiles-installed"
DOTFILES_DIR="$HOME/.dotfiles"
DOTFILES_SOURCE_SUBDIR="dotfiles"

# ---------------------------- Bootstrap-phase primitives ----------------------------
# Inline copies of lib/common.sh's logging/presence primitives and selected
# brew-pkg helpers, plus lib/bootstrap.sh's bootstrap subsystem.  These run
# BEFORE the repo is cloned (when lib/ does not yet exist on disk).  The
# canonical lib/common.sh version exists for the five child scripts
# (devtools/install.sh, claude/install.sh, setup-ai-tools.sh,
# macos/apply-settings.sh, iterm2/apply-iterm.sh) so they share one
# definition; install.sh owns its own inline copy because it must run
# before lib/ is available.  Keep the two copies in sync.
info()  { echo "==> $*" ; }
warn()  { echo " WARNING: $*" ; }
fail()  { echo "ERROR: $*" >&2; exit 1 ; }

# cmd_available — true if a command resolves on PATH.
cmd_available() { command -v "$1" >/dev/null 2>&1; }

# brew_installed — true if a Homebrew formula or cask is installed.
brew_installed() { cmd_available brew && brew list "$1" >/dev/null 2>&1; }

# brew_install_if_missing — install a Homebrew formula/cask if not present.
#   $1: human-readable name for log lines (e.g. "iTerm2", "zplug")
#   $2: package name (e.g. iterm2, zplug, font-jetbrains-mono)
#   $3+: optional brew install flags (e.g. --cask)
brew_install_if_missing() {
    _kind="$1"; _pkg="$2"; shift 2
    if brew_installed "$_pkg"; then
        info "$_kind already installed, skipping."
    else
        info "Installing $_kind..."
        brew install "$@" "$_pkg"
    fi
}

# install_uv_tool — installs a CLI as a uv-managed global tool if the
# command is not already on PATH.  Called from lib/brew-packages.sh's
# install_ai_aux_tools, so it must be inline here (lib/common.sh is only
# sourced by child scripts).  Keep in sync with lib/common.sh.
#   $1: tolerance — "warn" surfaces failures, "true" swallows them.
#   $2: human-readable name (for log lines, e.g. "graphify").
#   $3: uv tool spec (e.g. "graphifyy", "headroom-ai[all]").
#   $4: command name to check for idempotency (e.g. "graphify", "headroom").
install_uv_tool() {
    _tolerance="${1:-warn}"
    _name="$2"; _spec="$3"; _cmd="$4"
    if cmd_available "$_cmd"; then
        info "$_name already installed, skipping."
        return 0
    fi
    if ! cmd_available uv; then
        [ "$_tolerance" = "warn" ] && warn "uv not found; skipping $_name."
        return 0
    fi
    info "Installing $_name via uv..."
    uv tool install "$_spec" \
        || [ "$_tolerance" = "true" ] \
        || warn "$_name install failed; run 'uv tool install \"$_spec\"' manually."
}

BREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

# ensure_brew_on_path — re-sources brew's shellenv so `brew` resolves.
ensure_brew_on_path() {
    if [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    if ! cmd_available brew; then
        fail "Homebrew is installed but 'brew' is not on PATH."
    fi
}

# install_homebrew — installs Homebrew if missing, then ensures it is on PATH.
install_homebrew() {
    if cmd_available brew; then
        ensure_brew_on_path
        return 0
    fi
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL "$BREW_INSTALL_URL")"
    ensure_brew_on_path
}

# ensure_brew_git — guarantees a Homebrew-managed git binary is present.
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

# ensure_build_tools — installs CLT via softwareupdate (silent) or xcode-select
# (GUI fallback), then polls for git to appear.
ensure_build_tools() {
    if command -v git >/dev/null 2>&1; then
        info "git already available, skipping CLT setup."
        return 0
    fi
    info "git not found — ensuring Command Line Tools..."
    for _ in 1 2; do
        softwareupdate --install --agree-to-license -r \
            "Command Line Tools for Xcode" >/dev/null 2>&1 && break
        sleep 2
    done
    if command -v git >/dev/null 2>&1; then
        info "CLT / git is now available."
    else
        warn "Silent CLT install failed — opening GUI installer."
        warn "After installation finishes, dismiss the dialog."
        warn "This script will resume automatically."
        warn "If the dialog stays open longer than 3 minutes, Ctrl-C and"
        warn "re-run this script after CLT is installed."
        xcode-select --install || true
    fi
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

# ensure_git — installs brew + brew-managed git as dependencies before any
# `git clone` of this repo.  Falls back to CLT if brew is unreachable.
ensure_git() {
    ensure_brew_git
    if ! command -v git >/dev/null 2>&1; then
        warn "brew-supplied git not on PATH — falling back to CLT."
        ensure_build_tools
    fi
    command -v git >/dev/null 2>&1 || \
        fail "git is not available; install Xcode CLT or Homebrew manually."
}

# ---------------------------- Install.sh-local step helpers ----------------------------
# These helpers back both fresh_install and update so neither path can
# silently drift from the other.  Each helper encapsulates a single
# install-time concern.  They live in install.sh (not lib/) because they
# reference DOTFILES_DIR / DOTFILES_SOURCE_SUBDIR and are orchestrated by
# the two paths below — keeping them next to the orchestrators makes the
# dataflow visible.

# apply_macos_prefs — runs macos/apply-settings.sh idempotently.  Fresh
# install is permitted to surface a soft warning if partial failure
# occurs; update treats any failure as cosmetic.
apply_macos_prefs() {
    _tolerance="${1:-warn}"
    if [ -x "${DOTFILES_DIR}/macos/apply-settings.sh" ]; then
        if [ "$_tolerance" = "warn" ]; then
            info "Applying macOS system preferences..."
        fi
        DOTFILES="$DOTFILES_DIR" sh "${DOTFILES_DIR}/macos/apply-settings.sh" \
            || [ "$_tolerance" = "true" ] \
            || warn "macOS system preferences partially failed; you can rerun apply-settings.sh manually."
    fi
}

# launch_iterm_once — opens iTerm2 the first time so its defaults domain
# is registered with defaults(1) before the snapshot is imported.  No-op
# if the domain is already registered, iTerm2 is currently running and
# the domain is present, or iTerm2 isn't installed yet.
#
# On first launch iTerm2 displays welcome/permissions dialogs and the
# com.googlecode.iterm2 defaults domain is only registered once that
# first-run sequence finishes — so we poll for the domain (not the
# process) for up to 60s.  The user is told to dismiss any dialogs in
# the iTerm2 window so the script continues.
launch_iterm_once() {
    if [ ! -d "/Applications/iTerm.app" ]; then
        return 0
    fi
    # Fast path: domain already registered (iTerm ran previously).
    if defaults read com.googlecode.iterm2 >/dev/null 2>&1; then
        return 0
    fi
    # Domain not registered.  If iTerm isn't already running, launch it.
    if ! pgrep -f "iTerm.app/Contents/MacOS/iTerm2" >/dev/null 2>&1; then
        info "Launching iTerm2 once to register its defaults domain..."
        open -a iTerm 2>/dev/null || true
    fi
    info "Waiting for iTerm2 to register its defaults domain..."
    info "(if a first-run dialog appears in iTerm2, dismiss it to continue.)"
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
             21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 \
             41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60; do
        sleep 1
        if defaults read com.googlecode.iterm2 >/dev/null 2>&1; then
            info "iTerm2 defaults domain registered."
            return 0
        fi
    done
    warn "iTerm2 defaults domain did not register within 60s; " \
         "apply-iterm.sh may fail. Dismiss any open dialogs in iTerm2 and re-run."
}

apply_iterm_prefs() {
    _tolerance="${1:-warn}"
    if [ ! -f "${DOTFILES_DIR}/iterm2/apply-iterm.sh" ]; then
        [ "$_tolerance" = "warn" ] && warn "apply-iterm.sh not found; skipping iTerm2 configuration."
        return 0
    fi
    DOTFILES="$DOTFILES_DIR" sh "${DOTFILES_DIR}/iterm2/apply-iterm.sh" \
        || [ "$_tolerance" = "true" ] \
        || warn "apply-iterm.sh failed; you can rerun it manually after opening iTerm2 once."
}

# install_omz — clones Oh My Zsh to ~/.oh-my-zsh if absent.  The repo
# is ~140 MB shallow-cloned so the install-time cost is modest.
install_omz() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        info "Oh My Zsh already installed, skipping."
    else
        info "Installing Oh My Zsh..."
        git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
    fi
}

# install_claude_config — applies claude/install.sh if shipped.
#   $1: tolerance — "true" swallows errors, "warn" surfaces them.
install_claude_config() {
    _tolerance="${1:-warn}"
    if [ ! -x "${DOTFILES_DIR}/claude/install.sh" ]; then
        [ "$_tolerance" = "warn" ] \
            && warn "claude/install.sh not found; skipping Claude Code configuration."
        return 0
    fi
    if [ "$_tolerance" = "warn" ]; then
        info "Applying Claude Code configuration..."
        sh "${DOTFILES_DIR}/claude/install.sh"
    else
        sh "${DOTFILES_DIR}/claude/install.sh" || true
    fi
}

# install_devtools — applies devtools/install.sh if shipped.  Installs
# VSCode, Node/nvm, Ruby/rvm, Python/uv/pipx, Rust/rustup and symlinks
# VSCode user settings into ~/Library/Application Support/Code/User/.
#   $1: tolerance — "true" swallows errors, "warn" surfaces them.
install_devtools() {
    _tolerance="${1:-warn}"
    if [ ! -x "${DOTFILES_DIR}/devtools/install.sh" ]; then
        [ "$_tolerance" = "warn" ] \
            && warn "devtools/install.sh not found; skipping dev toolchains."
        return 0
    fi
    if [ "$_tolerance" = "warn" ]; then
        info "Installing development toolchains..."
        sh "${DOTFILES_DIR}/devtools/install.sh" "$_tolerance"
    else
        sh "${DOTFILES_DIR}/devtools/install.sh" "$_tolerance" || true
    fi
}

# copy_dotfile — copies a managed file from the repo to $HOME if it
# exists.  Used for .zshrc which chezmoi may not overwrite.
copy_dotfile() {
    _src="$1"
    _dst="$2"
    [ "${3:-}" = "verbose" ] && info "Copying $(basename "$_src") from dotfiles..."
    cp "$_src" "$_dst"
}

# run_zplug_install — runs zplug install in a clean zsh session so Oh
# My Zsh init doesn't interfere.  Tolerant of non-zero exit (zplug
# occasionally re-clobbers completion files).
run_zplug_install() {
    info "Syncing zsh plugins..."
    ZPLUG_HOME="$(brew --prefix)/opt/zplug"
    zsh -c "source $ZPLUG_HOME/init.zsh && zplug install" \
        || warn "zplug install returned non-zero; you can run it manually later."
}

# ---------------------------- Check: already installed? ----------------------------
is_installed() {
    [ -f "$MARKER_FILE" ]
}

# ---------------------------- Fresh install ----------------------------
fresh_install() {
    info "Fresh install detected — setting up dotfiles..."

    apply_macos_prefs warn

    install_homebrew

    install_core_casks

    # Install the brew-managed git (always; ensure_brew_git's earlier
    # early-return already verified it as a hard dependency, so this is
    # a no-op upgrade when present and a fresh install when not).
    info "Installing git via Homebrew..."
    brew install git

    install_omz

    # Launch iTerm2 once on first run so its defaults domain is
    # registered with defaults(1) before we import the snapshot.
    launch_iterm_once
    info "Applying iTerm2 preferences..."
    apply_iterm_prefs warn

    install_core_formulas

    sync_neovim_config

    sync_nvim_symlinks warn

    ensure_vim_plug

    install_nvim_plugins warn

    install_claude_config warn

    install_devtools warn

    # AI auxiliary tools — must run AFTER install_devtools so uv is on PATH
    # (uv is a devtools dependency).
    install_ai_aux_tools warn

    # Desktop apps + CLI tools — shared with the update path.
    install_all_desktop_apps

    info "Applying dotfiles..."
    chezmoi apply --source "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}"

    # Ensure .zshrc is present (chezmoi may not overwrite an existing file).
    if [ -f "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/.zshrc" ]; then
        copy_dotfile "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/.zshrc" \
                     "$HOME/.zshrc" verbose
    fi

    run_zplug_install

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
    info "To configure AI tools (rtk/engram/graphify) for Claude Code + opencode, run:"
    info "  sh \"$DOTFILES_DIR/setup-ai-tools.sh\""
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

    apply_macos_prefs true

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
    if ! cmd_available brew; then
        warn "Homebrew not found; re-running fresh install."
        fresh_install
        return
    fi

    install_core_formulas

    install_all_desktop_apps

    install_claude_config true

    install_devtools true

    # AI auxiliary tools — must run AFTER install_devtools so uv is on PATH.
    install_ai_aux_tools true

    sync_neovim_config
    sync_nvim_symlinks true

    ensure_vim_plug
    install_nvim_plugins true

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        warn "Oh My Zsh missing — re-running fresh install."
        fresh_install
        return
    fi

    info "Re-applying iTerm2 preferences..."
    apply_iterm_prefs true

    info "Applying updated dotfiles..."
    chezmoi apply --source "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}"

    if [ -f "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/.zshrc" ]; then
        copy_dotfile "${DOTFILES_DIR}/${DOTFILES_SOURCE_SUBDIR}/.zshrc" \
                     "$HOME/.zshrc"
    fi

    run_zplug_install

    info "Dotfiles updated successfully."
    info "To configure AI tools (rtk/engram/graphify) for Claude Code + opencode, run:"
    info "  sh \"$DOTFILES_DIR/setup-ai-tools.sh\""
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

    # Source the per-group brew package list and Neovim helpers from lib/.
    # install.sh keeps its own inline copies of the bootstrap primitives
    # (info/warn/cmd_available/brew_installed/brew_install_if_missing/
    # symlink_into_place/install_uv_tool etc.) because those are needed
    # pre-clone too (lib/ doesn't exist yet on the curl-bootstrap path).
    # The bootstrap subsystem (lib/bootstrap.sh) is also kept inline for
    # the same reason.  lib/common.sh exists for the five child scripts
    # (devtools/install.sh, claude/install.sh, setup-ai-tools.sh,
    # macos/apply-settings.sh, iterm2/apply-iterm.sh) so they share one
    # canonical definition; install.sh has its own and doesn't need to
    # re-source it.
    # shellcheck source=lib/brew-packages.sh
    . "$DOTFILES_DIR/lib/brew-packages.sh"
    # shellcheck source=lib/nvim.sh
    . "$DOTFILES_DIR/lib/nvim.sh"

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
