#!/bin/sh
set -e

CLAUDE_CONFIG_SOURCE="$(dirname "$0")/config"
CLAUDE_STATUSLINE_SOURCE="$(dirname "$0")/statusline-command.sh"
CLAUDE_CONFIG_TARGET="$HOME/.config/claude-code"
CLAUDE_TARGET="$HOME/.claude"

info()  { echo "==> $*"; }
warn()  { echo " WARNING: $*"; }
success(){ echo "==> $*"; }

has() { command -v "$1" >/dev/null 2>&1; }

install_claude_code() {
    if ! has claude; then
        info "Installing Claude Code CLI and App via Homebrew..."
        brew install claude-code
    else
        info "Claude Code already installed, skipping."
    fi
}

backup_and_symlink() {
    source_path="$1"
    target_path="$2"
    backup="${target_path}.backup-$(date +%Y%m%d%H%M%S)"

    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
        if [ -L "$target_path" ]; then
            info "Removing old symlink: $target_path"
            rm "$target_path"
        else
            info "Backing up existing $target_path -> $backup"
            mv "$target_path" "$backup"
        fi
    fi

    info "Creating symlink: $target_path -> $source_path"
    ln -s "$source_path" "$target_path"
}

install_configs() {
    info "Setting up Claude Code configuration..."

    backup_and_symlink "$CLAUDE_CONFIG_SOURCE" "$CLAUDE_CONFIG_TARGET"
    mkdir -p "$CLAUDE_TARGET"
    backup_and_symlink "$CLAUDE_STATUSLINE_SOURCE" "$CLAUDE_TARGET/statusline-command.sh"

    info "Making statusline script executable..."
    chmod +x "$CLAUDE_TARGET/statusline-command.sh"

    success "Claude Code configuration installed."
}

main() {
    echo ""
    echo "Claude Code Setup"
    echo "================="
    echo ""

    install_claude_code
    install_configs

    echo ""
    echo "Done! Next steps:"
    echo "  1. Set your API key in ~/.config/claude-code/settings.json or environment"
    echo "  2. Restart your terminal"
    echo ""
}

main "$@"
