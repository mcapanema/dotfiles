#!/bin/sh
# Install Claude Code configuration (settings.json symlink + statusline script).
# The brew install of claude-code itself is handled by the parent install.sh.

set -eu
set -o pipefail

CLAUDE_DIR="$(dirname "$0")"
CLAUDE_CONFIG_SOURCE="$CLAUDE_DIR/config"
CLAUDE_STATUSLINE_SOURCE="$CLAUDE_DIR/statusline-command.sh"
CLAUDE_CONFIG_TARGET="$HOME/.config/claude-code"
CLAUDE_TARGET="$HOME/.claude"
# shellcheck disable=SC2034  # BACKUP_TS is read by symlink_into_place in lib/common.sh at runtime
BACKUP_TS="$(date +%Y%m%d%H%M%S)-$$"

# Source shared primitives (info, warn, symlink_into_place, ...) from lib/.
# shellcheck source=../lib/common.sh
. "$CLAUDE_DIR/../lib/common.sh"

install_configs() {
    info "Setting up Claude Code configuration..."

    symlink_into_place "$CLAUDE_CONFIG_SOURCE" "$CLAUDE_CONFIG_TARGET"
    mkdir -p "$CLAUDE_TARGET"
    symlink_into_place "$CLAUDE_STATUSLINE_SOURCE" "$CLAUDE_TARGET/statusline-command.sh"

    info "Claude Code configuration installed."
}

main() {
    echo ""
    echo "Claude Code Setup"
    echo "================="
    echo ""

    install_configs

    echo ""
    echo "Done! Next steps:"
    echo "  1. Set your API key in ~/.config/claude-code/settings.json or environment"
    echo "  2. Restart your terminal"
    echo ""
}

main "$@"
