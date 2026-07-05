# dotfiles

Personal macOS dotfiles managed with [chezmoi](https://www.chezmoi.io/). One command to
bootstrap a full developer environment on a fresh macOS install.

**Repo:** `https://github.com/mcapanema/dotfiles.git`

```shell
sh -c "$(curl -fsSL https://raw.githubusercontent.com/mcapanema/dotfiles/main/install.sh)"
```

---

## What's Installed

| Component | Details |
|---|---|
| **iTerm2** | Terminal emulator with Snazzy color theme and committed preferences |
| **Neovim** | Text editor with NERDTree, vim-plug, JetBrains Mono font |
| **Homebrew** | Package manager for macOS |
| **Oh My Zsh** | Zsh framework with zplug plugin manager |
| **chezmoi** | Dotfile manager (source in `dotfiles/` subdirectory) |

---

## Quick Start

### Fresh Install

```shell
sh -c "$(curl -fsSL https://raw.githubusercontent.com/mcapanema/dotfiles/main/install.sh)"
```

The script will:

1. Ensure Command Line Tools / git are available
2. Install Homebrew if missing
3. Install iTerm2, Neovim, zplug, chezmoi
4. Import iTerm2 preferences from the versioned snapshot
5. Bootstrap Oh My Zsh and zplug plugins (Pure prompt, syntax highlighting, autosuggestions)
6. Symlink `vim` and `vi` → `nvim` in `~/.local/bin`
7. Install NERDTree via vim-plug
8. Apply all managed dotfiles via chezmoi
9. Set zsh as the login shell

### Update

Re-run the same command on an already-configured machine. It will pull the latest
changes, re-apply dotfiles, re-install plugins, and re-import iTerm2 preferences.

---

## Managing Dotfiles

All shell and editor config lives in `dotfiles/` (chezmoi source directory).

```shell
# Preview what chezmoi would change
chezmoi diff

# Apply changes
chezmoi apply

# Edit a managed file
chezmoi edit dotfiles/.zshrc
chezmoi apply
```

---

## iTerm2 Preferences

Preferences are stored as a versioned plist snapshot at `iterm2/com.googlecode.iterm2.plist.export`.
After changing settings in the iTerm2 GUI, re-export with:

```shell
defaults export com.googlecode.iterm2 \
  "$HOME/.dotfiles/iterm2/com.googlecode.iterm2.plist.export"
```

The script `iterm2/apply-iterm.sh` handles the import: it stops iTerm2, validates the plist
with `plutil -lint`, imports it via `defaults import`, and restarts iTerm2.

**Font:** iTerm2 3.6.11 crashes when `Normal Font` uses the dict form
`{FontName=...; FontSize=...}` or the NSKeyedArchiver blob. Only the legacy CFString
form `"JetBrainsMono-Regular 15"` works. The committed plist uses this form.

---

## Neovim

Config: `~/.config/nvim/init.vim` (managed via chezmoi at `dotfiles/config/nvim/init.vim`).

| Key | Action |
|---|---|
| `\n` | Toggle NERDTree |
| `:PlugInstall` | Install/update plugins |
| `:wq` | Save and quit |

Plugins are managed by **vim-plug**, installed by `install.sh` (not in `init.vim`) because
vim's `system()` doesn't expand `~`. Plugin install: `nvim --headless +PlugInstall +qall`.

**`vim` and `vi`** in `~/.local/bin` both symlink to `nvim`, prepended to `PATH` via `.zshenv`.

---

## Shell Configuration

### `.zshenv` (always sourced — environment, not shell behaviour)
```
export LANG=en_US.UTF-8
export EDITOR=nvim
export VISUAL=nvim
export GREP_COLOR='1;33'
[ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH"
```

### `.zshrc` (interactive shells only)
```
set -o vi                  # Vi keybindings
bindkey -v                # Vi keymap
alias rm='nocorrect rm'   # Disable zsh spell-checker on rm
```

**Note:** zsh uses `#` for comments, not `"`. A `"` after a command starts a string
literal and causes parse errors like "number expected". Always use `#` in `.zshrc`.

---

## Project Structure

```
.dotfiles/
├── install.sh                       # Bootstrap / update script
├── chezmoi.toml                     # chezmoi config
├── iterm2/
│   ├── apply-iterm.sh               # Import preferences snapshot
│   ├── com.googlecode.iterm2.plist.export  # Versioned prefs
│   └── Snazzy.itermcolors           # Color theme
├── dotfiles/                        # chezmoi source directory
│   ├── .zshenv                     # Environment variables
│   ├── .zshrc                      # Interactive shell config
│   ├── .zprofile                   # Login shell config
│   └── config/nvim/init.vim        # Neovim config
└── claude/                          # Claude Code integration
    ├── install.sh                   # Claude Code installer
    ├── statusline-command.sh       # Statusline renderer
    ├── config/settings.json         # API settings
    └── templates/.zshenv           # Claude chezmoi template
```

---

## Claude Code Integration

The `claude/` directory provides a statusline that parses Claude Code's JSON output and
renders model, context usage, cost, token rate, rate limits, directory, and git branch.

See [claude/README.md](./claude/README.md) for installation and configuration.

---

## Tips

- **Restart iTerm2** after first install to pick up the Snazzy theme and font
- **Restart zsh** or run `source ~/.zshrc` after dotfile changes
- Delete `~/.dotfiles-installed` to force a fresh install on next run
- Working tree must be clean before pushing (`install.sh` does not commit)
- Commit iTerm2 preference changes after GUI tweaks: `defaults export ...` then `git add`/`commit`