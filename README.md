# dotfiles

My personal dotfiles repository, managed with [chezmoi](https://www.chezmoi.io/).

## Quick Setup

```shell
sh -c "$(curl -fsSL https://raw.githubusercontent.com/mcapanema/dotfiles/main/install.sh)"
```

## Components

### [Claude Statusline](./claude-statusline/)

A POSIX shell script that parses Claude Code's JSON output and renders a beautiful, color-coded statusline showing:

- Model and thinking effort
- Context window usage
- Session cost and token rate
- Rate limit status (5h and 7d)
- Current directory, worktree, and git branch

```shell
🤖 Sonnet 4.6 | 💪 high | 🧠 53% | 💰 $6.74 | ⚡ 69 tok/s | ⏱️ 5h 85% • 6:12PM (2h0m) | 7d 55% • Wed 4:16PM
📁 ProductAgents | 🌳 worktree-v3-streaming-reasoning-ui | 🌿 main
```

See [claude-statusline/README.md](./claude-statusline/README.md) for installation and configuration.