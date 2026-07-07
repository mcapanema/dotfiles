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
BACKUP_TS="$(date +%Y%m%d%H%M%S)-$$"

info()  { echo "==> $*" ; }
warn()  { echo " WARNING: $*" ; }

has() { command -v "$1" >/dev/null 2>&1; }

# Symlink a file/dir into place. If the target exists:
#   - if it's already the right symlink, nothing to do
#   - if it's a different symlink or a regular file/dir, back it up
#     with a unique backup suffix, then create the new symlink
symlink_into_place() {
    source_path="$1"
    target_path="$2"

    # Already pointing at the right source — nothing to do.
    if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$source_path" ]; then
        info "$target_path already symlinked to $source_path"
        return 0
    fi

    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
        backup="${target_path}.backup-${BACKUP_TS}"
        info "Moving existing $target_path -> $backup"
        mv "$target_path" "$backup"
    fi

    info "Creating symlink: $target_path -> $source_path"
    ln -s "$source_path" "$target_path"
}

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
