#!/bin/sh
# setup-ai-tools.sh — configure AI auxiliary tools (rtk, engram, graphify)
# for Claude Code and opencode.
#
# Run manually after install.sh finishes. Each tool's binaries must already
# be on PATH (installed by install.sh: rtk and engram via brew, graphify via
# `uv tool install graphifyy`).
#
# headroom is intentionally NOT configured here — `headroom wrap claude`
# launches a live wrapped session (interactive, runtime) rather than writing
# durable config. Run it manually per session when you want compression.
#
# Safe to re-run; each step warns on failure and continues.

set -eu
set -o pipefail

# Source shared primitives (info, warn, has, soft_fail, ...) from the lib/
# directory.  This script's existing `soft_fail "msg"` call sites match
# lib/common.sh's always-warn `soft_fail` contract verbatim, so no callsite
# changes are required.
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

# ---------------------------- Pre-flight ----------------------------
# All three tools must already be installed (by install.sh). Abort early
# with a clear message rather than failing per-step.
preflight() {
    _missing=""
    for _bin in rtk engram graphify; do
        has "$_bin" || _missing="$_missing $_bin"
    done
    if [ -n "$_missing" ]; then
        warn "Missing binaries:$_missing"
        warn "Run install.sh first, or install manually:"
        warn "  brew install rtk"
        warn "  brew tap gentleman-programming/tap && brew install gentleman-programming/tap/engram"
        warn "  uv tool install graphifyy"
        warn "Then re-run this script."
        exit 1
    fi
    # claude CLI is needed for engram's Claude Code plugin path.
    if ! has claude; then
        warn "'claude' CLI not found; skipping engram Claude Code plugin step."
        warn "Install via: brew install claude-code"
    fi
}

# ---------------------------- rtk ----------------------------
# rtk init -g installs the PreToolUse hook + RTK.md for the target agent.
# --auto-patch makes it non-interactive (safe for scripting).
setup_rtk() {
    info "Setting up rtk for Claude Code..."
    rtk init -g --auto-patch \
        || soft_fail "rtk init for Claude Code failed; run 'rtk init -g' manually."
    info "Setting up rtk for opencode..."
    rtk init -g --opencode --auto-patch \
        || soft_fail "rtk init for opencode failed; run 'rtk init -g --opencode' manually."
}

# ---------------------------- engram ----------------------------
# Claude Code uses the plugin marketplace (not `engram setup`); opencode
# uses `engram setup opencode`. Both write MCP config / plugin files.
setup_engram() {
    if has claude; then
        info "Installing engram plugin for Claude Code..."
        claude plugin marketplace add Gentleman-Programming/engram \
            || soft_fail "engram marketplace add failed (may already be added)."
        claude plugin install engram \
            || soft_fail "engram plugin install failed; run 'claude plugin install engram' manually."
    fi
    info "Setting up engram for opencode..."
    engram setup opencode \
        || soft_fail "engram setup opencode failed; run 'engram setup opencode' manually."
}

# ---------------------------- graphify ----------------------------
# graphify install registers the skill with the assistant. Default target is
# Claude Code; --platform opencode targets opencode.
setup_graphify() {
    info "Installing graphify skill for Claude Code..."
    graphify install \
        || soft_fail "graphify install for Claude Code failed; run 'graphify install' manually."
    info "Installing graphify skill for opencode..."
    graphify install --platform opencode \
        || soft_fail "graphify install for opencode failed; run 'graphify install --platform opencode' manually."
}

main() {
    echo ""
    echo "AI tools setup"
    echo "=============="
    echo ""

    preflight

    setup_rtk
    setup_engram
    setup_graphify

    echo ""
    echo "Done! Next steps:"
    echo "  1. Restart Claude Code   (loads rtk hook + engram MCP + graphify skill)"
    echo "  2. Restart opencode      (same — reloads all three integrations)"
    echo ""
    echo "headroom (not configured by this script):"
    echo "  headroom wrap claude    # start a live wrapped session with compression"
    echo "  headroom unwrap claude  # undo durable agent config writes"
    echo ""
    echo "Undo individual tools:"
    echo "  rtk init -g --uninstall"
    echo "  claude plugin uninstall engram"
    echo "  graphify uninstall"
    echo ""
}

main "$@"
