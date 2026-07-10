#!/bin/sh
# Install development toolchains: VSCode, Node/nvm, Ruby/rvm, Python/uv/pipx, Rust/rustup.
# Invoked by the parent install.sh; the $1 tolerance arg ("warn" or "true")
# controls whether errors are surfaced or swallowed.
#
# Design notes:
#   - VSCode is installed as a cask and its user settings.json is symlinked
#     from devtools/vscode/settings.json into ~/Library/Application Support/Code/User/.
#   - The brew `node` formula is intentionally removed so nvm is the sole
#     Node source of truth (avoids version confusion).
#   - RVM is installed via its official `curl | bash` installer from get.rvm.io
#     (same trust pattern as the existing Homebrew and Oh My Zsh bootstraps).
#   - rustup is installed via the keg-only brew formula; `rustup install stable`
#     then bootstraps the stable toolchain into ~/.cargo (PATH already wired
#     in .zprofile).
#   - Only the *manager* is installed; specific language versions are
#     user-driven (nvm install <ver>, rvm install <ver>, etc.).

set -eu
set -o pipefail

DEVTOOLS_DIR="$(dirname "$0")"
TOLERANCE="${1:-warn}"
BACKUP_TS="$(date +%Y%m%d%H%M%S)-$$"

info()  { echo "==> $*" ; }
warn()  { echo " WARNING: $*" ; }
has()   { command -v "$1" >/dev/null 2>&1; }

# brew_installed — true if a Homebrew formula or cask is installed.
# Defined inside main() to avoid shadowing a homonym in the parent script
# (this file is sourced via `sh`, never via `.`, so scoping is safe).
brew_installed() { has brew && brew list "$1" >/dev/null 2>&1; }

# soft_fail — respect the tolerance contract. Returns 0 so `set -e` doesn't
# abort the parent script; surfaces a warning when tolerance is "warn".
soft_fail() {
    [ "$TOLERANCE" = "true" ] || warn "$1"
    return 0
}

# symlink_into_place — same backup-and-symlink pattern as claude/install.sh.
#   $1: source path (in the repo)
#   $2: target path (in $HOME)
symlink_into_place() {
    _src="$1"; _dst="$2"
    if [ -L "$_dst" ] && [ "$(readlink "$_dst")" = "$_src" ]; then
        info "$_dst already symlinked to $_src"
        return 0
    fi
    if [ -e "$_dst" ] || [ -L "$_dst" ]; then
        _backup="${_dst}.backup-${BACKUP_TS}"
        info "Moving existing $_dst -> $_backup"
        mv "$_dst" "$_backup"
    fi
    info "Creating symlink: $_dst -> $_src"
    ln -s "$_src" "$_dst"
}

# ---------------------------- VSCode ----------------------------
install_vscode() {
    if brew_installed visual-studio-code; then
        info "VSCode already installed, skipping."
    else
        info "Installing VSCode cask..."
        brew install --cask visual-studio-code \
            || soft_fail "VSCode cask install failed; install manually via brew."
    fi
}

# symlink_vscode_settings — link devtools/vscode/settings.json into the
# VSCode User dir.  VSCode creates that dir on first launch, but we
# `mkdir -p` defensively in case the cask was just installed and not opened.
symlink_vscode_settings() {
    _src="${DEVTOOLS_DIR}/vscode/settings.json"
    _dst_dir="$HOME/Library/Application Support/Code/User"
    _dst="$_dst_dir/settings.json"
    if [ ! -f "$_src" ]; then
        soft_fail "VSCode settings source missing at $_src; skipping."
        return 0
    fi
    mkdir -p "$_dst_dir"
    symlink_into_place "$_src" "$_dst"
}

# ---------------------------- Node + nvm ----------------------------
install_node_nvm() {
    # Uninstall any brew node formula so nvm is the sole Node source of truth.
    if brew list node >/dev/null 2>&1; then
        info "Removing brew node formula (nvm will manage Node)..."
        # --ignore-dependencies: brew refuses to remove node if another formula
        # depends on it (e.g. opencode).  Since nvm will provide node going
        # forward, force the removal.
        brew uninstall --ignore-dependencies node \
            || soft_fail "Could not remove brew node; remove manually with 'brew uninstall --ignore-dependencies node'."
    fi

    if brew_installed nvm; then
        info "nvm already installed, skipping."
    else
        info "Installing nvm formula..."
        brew install nvm || soft_fail "nvm install failed; install manually via 'brew install nvm'."
    fi

    # nvm requires this dir to exist before `nvm install` works.
    mkdir -p "$HOME/.nvm"

    # Install a default Node LTS if no nvm-managed version exists yet.
    if [ ! -d "$HOME/.nvm/versions/node" ] || \
       [ -z "$(ls -A "$HOME/.nvm/versions/node" 2>/dev/null)" ]; then
        info "Installing default Node LTS via nvm..."
        (
            export NVM_DIR="$HOME/.nvm"
            # shellcheck disable=SC1091
            . "$(brew --prefix)/opt/nvm/nvm.sh"
            nvm install --lts
        ) || soft_fail "nvm install --lts failed; run 'nvm install --lts' manually after restart."
    fi
}

# ---------------------------- Ruby + rvm ----------------------------
install_ruby_rvm() {
    if [ -s "$HOME/.rvm/scripts/rvm" ]; then
        info "RVM already installed, skipping."
        return 0
    fi
    info "Installing RVM (stable) via official installer..."
    # Same trust pattern as Homebrew and Oh My Zsh bootstraps in install.sh.
    /bin/bash -c "$(curl -sSL https://get.rvm.io)" -s stable \
        || soft_fail "RVM installer failed; install manually from https://rvm.io."
}

# ---------------------------- Python + uv + pipx ----------------------------
install_python_uv_pipx() {
    if ! brew_installed python@3.14; then
        info "Installing python@3.14 formula..."
        brew install python@3.14 || soft_fail "python@3.14 install failed."
    else
        info "python@3.14 already installed, skipping."
    fi

    if ! brew_installed uv; then
        info "Installing uv formula..."
        brew install uv || soft_fail "uv install failed."
    else
        info "uv already installed, skipping."
    fi

    if ! brew_installed pipx; then
        info "Installing pipx formula..."
        brew install pipx || soft_fail "pipx install failed."
    else
        info "pipx already installed, skipping."
    fi

    # pipx ensurepath prepends ~/.local/bin; harmless if already on PATH
    # (the .zshenv already prepends ~/.local/bin).
    if has pipx; then
        pipx ensurepath >/dev/null 2>&1 || true
    fi
}

# ---------------------------- Rust + rustup ----------------------------
install_rust_rustup() {
    if has rustc && has cargo; then
        info "Rust toolchain already installed, skipping."
        return 0
    fi

    if ! brew list rustup >/dev/null 2>&1; then
        info "Installing rustup formula (keg-only)..."
        brew install rustup || soft_fail "rustup formula install failed."
    else
        info "rustup formula already installed, skipping."
    fi

    # rustup is keg-only — its binaries live at $(brew --prefix rustup)/bin/.
    # Newer rustup formula (>= 1.29.0_2) no longer ships `rustup-init`; the
    # single `rustup` binary is used to install toolchains.  We do NOT modify
    # PATH (the rustup formula itself stays keg-only); `rustup install stable`
    # bootstraps ~/.cargo/bin/{rustc,cargo,...} which .zprofile already wires.
    _rustup="$(brew --prefix rustup)/bin/rustup"
    if [ ! -x "$_rustup" ]; then
        # Older formula versions shipped `rustup-init` instead.
        _rustup="$(brew --prefix rustup)/bin/rustup-init"
    fi
    if [ ! -x "$_rustup" ]; then
        soft_fail "Could not locate rustup binary; run 'rustup install stable' manually."
        return 0
    fi
    info "Installing Rust stable toolchain via rustup..."
    # `rustup install stable` installs the stable toolchain and sets up the
    # default profile (rustc, cargo, rustfmt, clippy).  --no-self-update
    # avoids rustup trying to update itself (brew manages the rustup formula).
    "$_rustup" install stable --profile default --no-self-update \
        || soft_fail "rustup install stable failed; run 'rustup install stable' manually."
    # Make stable the default toolchain so ~/.cargo/bin/rustc etc. resolve.
    "$_rustup" default stable 2>/dev/null || true
}

main() {
    echo ""
    echo "Dev toolchains Setup"
    echo "===================="
    echo ""

    install_vscode
    symlink_vscode_settings
    install_node_nvm
    install_ruby_rvm
    install_python_uv_pipx
    install_rust_rustup

    echo ""
    echo "Done! Next steps:"
    echo "  1. Restart zsh to load nvm/rvm/rust env"
    echo "  2. Install language versions as needed:"
    echo "       nvm install <ver>     (Node)"
    echo "       rvm install <ver>      (Ruby)"
    echo "       uv python install <v>  (Python)"
    echo "       rustup toolchain install <ver>  (Rust)"
    echo ""
}

main "$@"
