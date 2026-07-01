# Claude Code Configuration

This directory manages Claude Code CLI/App installation and configuration for this dotfiles setup.

## Structure

- `config/` — Settings symlinked to `~/.config/claude-code/`
- `statusline-command.sh` — Statusline script symlinked to `~/.claude/statusline-command.sh`
- `templates/.zshenv` — API key template (sourced by `dotfiles/.zshenv`)
- `install.sh` — Standalone installation script

## Installation

### One-liner (recommended)
```shell
sh -c "$(curl -fsSL https://raw.githubusercontent.com/mcapanema/dotfiles/refs/heads/main/install.sh)"
```

### Standalone
```shell
./claude/install.sh
```

## Manual Setup

If you prefer to set up manually:

1. Install Claude Code: `brew install claude-code`
2. Symlink config: `ln -s /path/to/claude/config ~/.config/claude-code`
3. Symlink statusline: `ln -s /path/to/claude/statusline-command.sh ~/.claude/statusline-command.sh`
4. Make executable: `chmod +x ~/.claude/statusline-command.sh`

## Statusline

The statusline is configured in `config/settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "sh ~/.claude/statusline-command.sh",
    "padding": 0
  }
}
```

See `statusline-command.sh` for the full feature list.