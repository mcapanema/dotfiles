# CLAUDE.md — mcapanema/dotfiles

## Project Overview

macOS dotfiles repo managed with **chezmoi** (source in `dotfiles/` subdirectory). Single
`install.sh` bootstraps a full developer environment from scratch, with idempotent
fresh-install and update paths.

**Repo:** `https://github.com/mcapanema/dotfiles.git`
**Managed by:** chezmoi (source: `dotfiles/` subdir)
**Bootstrap:** `sh -c "$(curl -fsSL https://raw.githubusercontent.com/mcapanema/dotfiles/main/install.sh)"`

---

## Architecture

```
.dotfiles/
├── install.sh               # Single bootstrap script; fresh-install or update
├── chezmoi.toml             # chezmoi config (source=repo root, files=dotfiles/)
├── iterm2/
│   ├── apply-iterm.sh       # SIGTERMs iTerm2, runs `defaults import`
│   └── com.googlecode.iterm2.plist.export  # Versioned prefs snapshot
├── dotfiles/                 # chezmoi source directory (managed files)
│   ├── .zshenv              # Environment variables (always sourced by zsh)
│   ├── .zshrc               # Interactive shell config, Oh My Zsh, zplug
│   ├── .zprofile            # Login shell config
│   └── config/nvim/init.vim # Neovim configuration
└── claude/                   # Claude Code integration (statusline, templates)
```

---

## Bootstrap Script Logic (`install.sh`)

- **Determines fresh vs. update** by presence of `$HOME/.dotfiles-installed` marker.
- **Fresh install (steps 1–10):** CLT/git → Homebrew → iTerm2 → Oh My Zsh → apply-iterm.sh →
  zplug → Neovim → nvim config → vim/vi symlinks → vim-plug → chezmoi → chezmoi apply →
  zplug install → `chsh -s /bin/zsh`.
- **Update:** `git pull --rebase --autostash` → re-run managed-tool installs → re-apply
  iTerm2 prefs → `chezmoi apply` → re-run zplug install.
- `set -euo pipefail` is always set. `chsh` failures are silenced with `2>/dev/null || warn`.

---

## iTerm2 Preferences

### Approach
Whole-plist import via `defaults import com.googlecode.iterm2 <plist>`. **Not** a Python
mutation script. After any GUI change, re-export with:
```sh
defaults export com.googlecode.iterm2 "$DOTFILES/iterm2/com.googlecode.iterm2.plist.export"
```

### Font Format — CRITICAL
iTerm2 3.6.11 has a **crash bug** with the NSKeyedArchiver font descriptor and with the
`{FontName/FontSize}` dict form. Only the legacy CFString `"Name Size"` form works:
```
Normal Font = "JetBrainsMono-Regular 15"
```
Both the dict (e.g. `{FontName = "..."; FontSize = 15}`) and the NSKeyedArchiver
`NSFontDescriptor` blob produce:
```
-[<obj> fontValueWithLigaturesEnabled:]: unrecognized selector
in +[ITAddressBookMgr fontWithDesc:ligaturesEnabled:]
```
The committed `.plist.export` uses the CFString form. **Do not switch to dict or NSData.**

### Commit the Plist
The `.plist.export` file is committed to the repo. It contains personal keys
(`AiModel`, `AitermURL`, etc.). Consider `.gitignore`-excluding it if sharing publicly.

---

## Neovim Configuration

- **Location:** `~/.config/nvim/init.vim` (managed via chezmoi at `dotfiles/config/nvim/init.vim`).
- **Plugin manager:** vim-plug (installed by `install.sh`, NOT in `init.vim`).
  Reason: `system()` in vim script doesn't expand `~`; download is done in shell with curl.
- **Plugins:** NERDTree via `Plug 'preservim/nerdtree'`. `\n` toggles NERDTree.
- **vim-plug install path:** `$HOME/.local/share/nvim/site/autoload/plug.vim`
- **Plugin install:** `nvim --headless +PlugInstall +qall` (non-interactive).
- **Symlinks:** `~/.local/bin/vim` and `~/.local/bin/vi` both point to `nvim`. Prepended
  to `PATH` via `.zshenv` so they take priority over system vim in `/usr/bin`.

### init.vim Settings
```
set nocompatible
set tabstop=4 softtabstop=4 shiftwidth=4 expandtab
set hlsearch incsearch ignorecase smartcase
set hidden wildmenu
set mouse=a
set number relativenumber
```

---

## Shell Configuration

### `.zshenv` vs `.zshrc`
- `.zshenv`: Always sourced (login + interactive). Environment variables, `PATH` setup.
- `.zshrc`: Sourced only for interactive shells. Oh My Zsh, zplug, `set -o vi`, etc.

### `#` Comments Only in zsh Scripts
**zsh does not treat `"` as a comment character.** In zsh, `"` is a string delimiter.
Using `"` after a command in `.zshrc` causes "number expected" parse errors. Always
use `#` for comments in `.zshrc`, `.zshenv`, and any `/bin/zsh` or `/bin/sh` script.

### `$HOME` Instead of `~` in Shell Scripts
Inside quoted strings, `~` is not expanded by most shells. Use `$HOME` instead, e.g.:
```sh
# WRONG
_plug_dir="$(eval echo ~/.local/share/nvim/...)"
# CORRECT
_plug_dir="$HOME/.local/share/nvim/site/autoload"
```

### `.zshenv` Contents
```
export LANG=en_US.UTF-8
export EDITOR=nvim
export VISUAL=nvim
export Nvim_As_Edit="true"
export GREP_COLOR='1;33'
[ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH"
# Conditional chezmoi template source (guards against "no such file" before first apply)
```

### `.zshrc` Contents
```
set -o vi                  # Vi line editing
bindkey -v                 # Vi keymap
alias rm='nocorrect rm'    # Prevent zsh spell-checker from correcting rm
# Oh My Zsh + zplug + Pure prompt
```

---

## chezmoi

- **Source directory:** `dotfiles/` subdirectory of the repo.
- **Config:** `chezmoi.toml` at repo root.
- **`edit.command`:** `["nvim", "-c", "set nofoldenable"]` — opens nvim without folds.
- **`add.templateSymlinks`:** `true` — templates can create symlinks.
- **Claude API template:** sourced conditionally in `.zshenv` from
  `$HOME/.local/share/chezmoi/claude/templates/.zshenv` (only if present).

---

## Homebrew Packages

| Package | Purpose |
|---|---|
| `neovim` | Text editor |
| `iterm2` | Terminal emulator |
| `chezmoi` | Dotfile manager |
| `zplug` | Zsh plugin manager |

**Casks:** `font-jetbrains-mono` (NERDTree compatible monospace font; referenced in iTerm2 prefs as `JetBrainsMono-Regular`).

---

## Key Gotchas / Lessons Learned

1. **iTerm2 font must be CFString `"Name Size"`.** Dict and NSKeyedArchiver forms crash iTerm2 3.6.11.
2. **zsh uses `#` for comments, not `"`.** `"` after a command in `.zshrc` causes parse errors.
3. **`~` doesn't expand inside quotes in shell scripts.** Use `$HOME`.
4. **vim-plug install must happen in shell**, not via `system()` in vim — `~` expansion fails.
5. **chezmoi applies dotfiles/ subdir**, not repo root. `chezmoi.toml` config reflects this.
6. **`chsh -s /bin/zsh` may prompt graphically.** Always silence: `2>/dev/null || warn`.
7. **On fresh macOS, git is missing** until CLT is installed. `ensure_build_tools()` handles this
   with silent `softwareupdate` (macOS 13+) and a GUI fallback via `xcode-select --install`.
8. **Working tree must be clean before push.** `install.sh` does not commit; manual `git add`/`commit` required.
9. **Marker file** (`$HOME/.dotfiles-installed`) gates install vs. update path. Delete to re-run fresh install.

---

## Development Workflow

```sh
# Make changes to managed files
$EDITOR dotfiles/.zshrc
$EDITOR dotfiles/config/nvim/init.vim

# Preview chezmoi changes
chezmoi diff

# Apply changes
chezmoi apply

# Update iTerm2 prefs after GUI change
defaults export com.googlecode.iterm2 \
  "$DOTFILES/iterm2/com.googlecode.iterm2.plist.export"

# Commit
git add -p   # stage selectively
git commit -m "description"
git push

# On another machine / fresh install
sh -c "$(curl -fsSL https://raw.githubusercontent.com/mcapanema/dotfiles/main/install.sh)"
```

---

## File Inventory

| File | Purpose |
|---|---|
| `install.sh` | Bootstrap / update script |
| `chezmoi.toml` | chezmoi configuration |
| `iterm2/apply-iterm.sh` | Import iTerm2 prefs snapshot |
| `iterm2/com.googlecode.iterm2.plist.export` | iTerm2 prefs (versioned) |
| `iterm2/Snazzy.itermcolors` | Snazzy color theme |
| `dotfiles/.zshenv` | Environment variables |
| `dotfiles/.zshrc` | Interactive shell config |
| `dotfiles/.zprofile` | Login shell config |
| `dotfiles/config/nvim/init.vim` | Neovim init file |
| `claude/statusline-command.sh` | Claude Code statusline |
| `claude/install.sh` | Claude Code integration installer |
| `claude/config/settings.json` | Claude API settings |
| `claude/templates/.zshenv` | chezmoi template for API config |