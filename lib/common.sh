#!/bin/sh
# lib/common.sh — shared primitives for the dotfiles installer and its
# child scripts (devtools/install.sh, claude/install.sh, setup-ai-tools.sh,
# macos/apply-settings.sh, iterm2/apply-iterm.sh).
#
# This file is SOURCED (never executed directly).  Each sourcing script owns
# its own `set -eu` + `set -o pipefail` — we re-set them here intentionally
# to enforce the contract in any script that forgets its own.
#
# Variable names prefixed with `_` are function-local throwaways; the
# convention is enforced by convention only since POSIX sh lacks `local`.

set -eu
set -o pipefail

# BACKUP_TS — used by symlink_into_place for unique backup suffixes.
# Guard so scripts that source this file only for info/warn don't break;
# a sourcing script that sets BACKUP_TS before sourcing wins.
[ -n "${BACKUP_TS:-}" ] || BACKUP_TS="$(date +%Y%m%d%H%M%S)-$$"

# ---------------------------- Logging ----------------------------
info()  { echo "==> $*" ; }
warn()  { echo " WARNING: $*" ; }
fail()  { echo "ERROR: $*" >&2; exit 1 ; }

# ---------------------------- Command / brew presence ----------------------------
# cmd_available — true if a command resolves on PATH.
cmd_available() { command -v "$1" >/dev/null 2>&1; }

# has — alias for cmd_available, kept so existing child scripts don't
# need to rename every callsite.
has() { cmd_available "$1"; }

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

# ---------------------------- Symlink helper ----------------------------
# symlink_into_place — idempotent backup-and-symlink.
#   $1: source path (in the repo)
#   $2: target path (in $HOME or elsewhere)
# If target already points at source, nothing happens.  Otherwise any
# existing file/symlink at target is moved aside with a unique backup
# suffix (BACKUP_TS) before the new symlink is created.
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

# ---------------------------- Tolerance primitives ----------------------------
# Two functions with DIFFERENT contracts.  The names exist to make the
# contract visible at each callsite — earlier versions of these scripts
# had two functions both named `soft_fail` with different semantics,
# which was a latent bug.

# soft_fail — always warn and return 0.  Use this when a step is
# non-fatal regardless of caller context (e.g. setup-ai-tools.sh, which
# is always user-invoked and always wants to surface what failed).
#   $1: message
soft_fail() {
    warn "$1"
    return 0
}

# tolerant_fail — honour the tolerance contract.  Returns 0 so `set -e`
# doesn't abort the caller; warns only when tolerance is "warn".
#   $1: tolerance — "warn" surfaces the message, "true" swallows it silently
#   $2: message
tolerant_fail() {
    _tolerance="$1"; _msg="$2"
    [ "$_tolerance" = "true" ] || warn "$_msg"
    return 0
}

# ---------------------------- uv-managed CLI tools ----------------------------
# install_uv_tool — installs a CLI as a uv-managed global tool if the
# command is not already on PATH.  Backs the graphify/headroom installs.
# uv is installed by devtools/install.sh, so this helper must be called
# AFTER install_devtools.
#   $1: tolerance — "warn" surfaces failures, "true" swallows them.
#   $2: human-readable name (for log lines, e.g. "graphify")
#   $3: uv tool spec (e.g. "graphifyy", "headroom-ai[all]")
#   $4: command name to check for idempotency (e.g. "graphify", "headroom")
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
