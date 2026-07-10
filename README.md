# dotfiles

Personal macOS dotfiles managed with [chezmoi](https://www.chezmoi.io/). One command to
bootstrap a full developer environment on a fresh macOS install.

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
| **Claude Code** | Anthropic's terminal-based AI coding assistant (`claude` CLI) |
| **opencode** | opencode CLI |
| **Desktop apps** | Google Chrome, Firefox, Slack, WhatsApp, Telegram, ChatGPT, Claude, Codex, Codex CLI, Mos |
| **Dev toolchains** | VSCode (managed settings), Node + nvm, Ruby + rvm, Python + uv + pipx, Rust + rustup |
| **macOS settings** | Developer-friendly system defaults (keyboard, trackpad, security, Time Machine) |

---

## Quick Start

### Fresh Install

```shell
sh -c "$(curl -fsSL https://raw.githubusercontent.com/mcapanema/dotfiles/main/install.sh)"
```

The script will:

1. Ensure Command Line Tools / git are available
2. Install Homebrew if missing
3. Install iTerm2, Neovim, zplug, chezmoi, Claude Code, opencode
4. Install dev toolchains: VSCode, Node/nvm, Ruby/rvm, Python/uv/pipx, Rust/rustup
5. Install desktop apps: Google Chrome, Firefox, Slack, WhatsApp, Telegram, ChatGPT, Claude, Codex, Codex CLI, Mos
6. Import iTerm2 preferences from the versioned snapshot
7. Bootstrap Oh My Zsh and zplug plugins (Pure prompt, syntax highlighting, autosuggestions)
8. Symlink `vim` and `vi` → `nvim` in `~/.local/bin`
9. Install NERDTree via vim-plug
10. Apply all managed dotfiles via chezmoi
11. Set zsh as the login shell
12. Apply sensible macOS system defaults (keyboard repeat, trackpad tap-to-click, security, Time Machine)

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

## macOS System Settings

The script `macos/apply-settings.sh` applies developer-friendly macOS defaults. Run it any time to ensure a consistent baseline, or re-run after a clean macOS install.

**What it sets:**

| Setting | Domain | Effect |
|---|---|---|
| Disable press-and-hold / key repeat | `NSGlobalDomain ApplePressAndHoldEnabled` | Characters repeat immediately on key hold |
| Fast key repeat rate | `NSGlobalDomain KeyRepeat=1, InitialKeyRepeat=15` | Max repeat speed |
| Tap to click (built-in trackpad) | `com.apple.AppleMultitouchTrackpad Clicking` | Single-finger tap = click |
| Tap to click (Bluetooth/external trackpad) | `com.apple.driver.AppleBluetoothMultitouch.trackpad` | Same for external devices |
| Require password on wake | `com.apple.screensaver askForPassword=1, askForPasswordDelay=0` | Lock immediately |
| No `.DS_Store` on network volumes | `com.apple.desktopservices DSDontWriteNetworkStores` | Cleaner shares |
| No Time Machine prompt for new drives | `com.apple.TimeMachine DoNotOfferNewDisksForBackup` | No nagging |

**Note:** `ApplePressAndHoldEnabled` / `KeyRepeat` / `InitialKeyRepeat` are deprecated since macOS 13 but still written for compatibility. On macOS 13+ they may be overridden by the Keyboard system settings panel; they remain harmless.

**To apply manually:**
```shell
sh "$HOME/.dotfiles/macos/apply-settings.sh"
```

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
├── macos/
│   └── apply-settings.sh            # Apply developer-friendly macOS defaults
├── dotfiles/                        # chezmoi source directory
│   ├── .zshenv                     # Environment variables
│   ├── .zshrc                      # Interactive shell config
│   ├── .zprofile                   # Login shell config
│   └── config/nvim/init.vim        # Neovim config
├── claude/                          # Claude Code integration
│   ├── install.sh                   # Claude Code installer
│   ├── statusline-command.sh       # Statusline renderer
│   ├── config/settings.json         # API settings
│   └── templates/.zshenv           # Claude chezmoi template
└── devtools/                        # Development toolchains installer
    ├── install.sh                   # VSCode + Node/nvm + Ruby/rvm + Python/uv/pipx + Rust/rustup
    └── vscode/settings.json        # Managed VSCode user settings (symlinked into ~/Library/Application Support/Code/User/)
```

---

## Tips

- **Restart iTerm2** after first install to pick up the Snazzy theme and font
- **Restart zsh** or run `source ~/.zshrc` after dotfile changes
- **Log out / log back in** after running `macos/apply-settings.sh` for all changes to take effect
- Delete `~/.dotfiles-installed` to force a fresh install on next run
- Working tree must be clean before pushing (`install.sh` does not commit)
- Commit iTerm2 preference changes after GUI tweaks: `defaults export ...` then `git add`/`commit`
