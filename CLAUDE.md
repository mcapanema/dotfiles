# CLAUDE.md — mcapanema/dotfiles

**This file is the agent's primary source of truth for the repository.** If `install.sh`
changes, update this file to match. `README.md` is the human-facing public intro; this
file is optimised for a Claude agent reading it before touching anything.

---

## 1. Project Overview

macOS dotfiles repo managed with **chezmoi** (source in `dotfiles/` subdirectory). Single
`install.sh` bootstraps a full developer environment from scratch, with idempotent
fresh-install and update paths.

| | |
|---|---|
| **Repo** | `https://github.com/mcapanema/dotfiles.git` |
| **Managed by** | chezmoi (source: `dotfiles/` subdir) |
| **Bootstrap** | `sh -c "$(curl -fsSL https://raw.githubusercontent.com/mcapanema/dotfiles/main/install.sh)"` |
| **Marker file** | `$HOME/.dotfiles-installed` — gates install vs. update; delete to force fresh install |

---

## 2. Layout & File Inventory

```
.dotfiles/
├── CLAUDE.md                    # THIS FILE — agent harness
├── README.md                    # Human-facing public intro; keep accurate
├── install.sh                   # Bootstrap / update orchestrator
├── chezmoi.toml                 # chezmoi config (source=repo root, files=dotfiles/)
├── .gitignore                   # Ignores docs/superpowers/ and .worktrees/
├── iterm2/
│   ├── apply-iterm.sh           # Import plist snapshot (verifies with plutil -lint first)
│   ├── com.googlecode.iterm2.plist.export  # Versioned prefs (ALWAYS use CFString font form)
│   └── Snazzy.itermcolors       # Color theme
├── macos/
│   └── apply-settings.sh        # Apply developer-friendly macOS defaults (idempotent)
├── dotfiles/                    # chezmoi source directory (managed files)
│   ├── .zshenv                 # Environment variables (always sourced by zsh)
│   ├── .zshrc                  # Interactive shell config; force-copied after chezmoi apply
│   ├── .zprofile               # Login shell config
│   └── config/nvim/init.vim    # Neovim init file
└── claude/                      # Claude Code / opencode integration
    ├── install.sh               # Claude Code + opencode installer
    ├── statusline-command.sh    # Statusline renderer
    ├── config/settings.json     # API settings
    ├── templates/.zshenv       # chezmoi template for API config (conditional source in .zshenv)
    └── test/                    # Internal test fixtures (do not ship)
```

### Edit freely

`dotfiles/.zshenv`, `dotfiles/.zshrc`, `dotfiles/.zprofile`, `dotfiles/config/nvim/init.vim`,
`macos/apply-settings.sh`, `iterm2/apply-iterm.sh`, `claude/install.sh`, `claude/statusline-command.sh`,
`claude/config/settings.json`, `CLAUDE.md`, `README.md`

### Edit with care — verify after changing

| File | Required check |
|---|---|
| `install.sh` | Trace through both `fresh_install` and `update` paths; run shellcheck if available |
| `iterm2/com.googlecode.iterm2.plist.export` | Run `plutil -lint` before committing |
| `chezmoi.toml` | `diff` before `chezmoi apply` |
| `claude/templates/.zshenv` | Must be valid zsh syntax when sourced; test with `zsh -n` |

---

## 3. `install.sh` Reference

### Pre-flight: brew + brew-managed git

`brew` and a Homebrew-managed `git` are **hard dependencies** of this repo — they are installed
*before* the repo is cloned, because the clone itself needs `git`.

```
main()
  └─ if [ ! -d "$DOTFILES_DIR/.git" ]      # no repo yet
       ensure_git()                         # install brew, then brew git
       git clone --depth 1 "$REPO_URL" ...
     else                                   # repo already present
       ensure_build_tools()                 # CLT git only; sufficient for git pull
```

`ensure_git()` → `ensure_brew_git()` → `install_homebrew()` + `brew install git`.
If brew is somehow unreachable, `ensure_build_tools()` falls back to CLT via
`softwareupdate` (silent, macOS 13+) or `xcode-select --install` (GUI, blocks up to 3 min).

### Orchestrators

| | `fresh_install` | `update` |
|---|---|---|
| **Trigger** | `$HOME/.dotfiles-installed` absent | Marker file present |
| **macOS prefs** | `apply_macos_prefs warn` | `apply_macos_prefs true` (swallow failure) |
| **brew** | `install_homebrew` then `brew install git` | `ensure_brew_on_path` only |
| **Remote normalisation** | — | Re-points `origin` to `$REPO_URL` if mismatched |
| **git pull** | — | `git pull --rebase --autostash` |
| **CLT fallback** | `ensure_git` (pre-clone) | `ensure_build_tools` (post-clone) |
| **Re-entry condition** | N/A | If `~/.oh-my-zsh` missing or not a git repo → `fresh_install` |
| **Marker** | `touch "$MARKER_FILE"` at end | No marker touch |

### Shared step helpers (called from both orchestrators)

Each accepts a `tolerance` arg: `"warn"` surfaces failures (fresh-install contract);
`"true"` swallows failures silently (update contract).

| Helper | What it does |
|---|---|
| `apply_macos_prefs` | Runs `macos/apply-settings.sh` idempotently |
| `launch_iterm_once` | Opens iTerm2 once so its defaults domain is registered before plist import; no-op if already running or not installed |
| `apply_iterm_prefs` | Runs `iterm2/apply-iterm.sh` (stops iTerm, plutil -lint, defaults import, restart) |
| `install_omz` | Shallow-clones Oh My Zsh to `$HOME/.oh-my-zsh` if absent |
| `sync_neovim_config` | Copies `dotfiles/config/nvim/init.vim` → `~/.config/nvim/init.vim` |
| `sync_nvim_symlinks` | Creates `~/.local/bin/{vim,vi}` → `nvim`; `~/.local/bin` is prepended to PATH via `.zshenv` |
| `ensure_vim_plug` | Downloads `plug.vim` into `$HOME/.local/share/nvim/site/autoload` if absent |
| `install_nvim_plugins` | Runs `nvim --headless +PlugInstall +qall`; tolerates errors |
| `install_claude_config` | Runs `claude/install.sh`; tolerance controls whether errors are surfaced |
| `copy_dotfile` | Force-copies `dotfiles/.zshrc` → `$HOME/.zshrc` (see note below) |
| `run_zplug_install` | Runs `zplug install` in a clean zsh session; tolerates non-zero exit by design |

**`.zshrc force-copy note:** `chezmoi apply` does not overwrite an existing file in `$HOME`.
On fresh install `.zshrc` already exists from Oh My Zsh's bootstrap, so `install.sh`
force-copies the managed version after `chezmoi apply` to ensure the managed version wins.

### Two primitives

```sh
cmd_available()   # true if a binary resolves on PATH
brew_installed()   # true if a Homebrew formula or cask is installed
```

All per-tool detection funnels through these two. Variable names prefixed with `_` are
function-local throwaways (enforced by convention only — POSIX sh has no `local`).

### Full install-order list (fresh_install)

```
apply_macos_prefs
install_homebrew
brew_install_if_missing JetBrains Mono (font-jetbrains-mono --cask)
brew install git
brew_install_if_missing iTerm2 (iterm2 --cask)
install_omz
launch_iterm_once
apply_iterm_prefs
brew_install_if_missing zplug
brew_install_if_missing Neovim
sync_neovim_config
sync_nvim_symlinks
ensure_vim_plug
install_nvim_plugins
brew_install_if_missing chezmoi
brew_install_if_missing claude-code
install_claude_config
brew_install_if_missing opencode
brew_install_if_missing Google Chrome (google-chrome --cask)
brew_install_if_missing Firefox (firefox --cask)
brew_install_if_missing Slack (slack --cask)
brew_install_if_missing WhatsApp (whatsapp --cask)
brew_install_if_missing Telegram (telegram --cask)
brew_install_if_missing ChatGPT (chatgpt --cask)
brew_install_if_missing Claude (claude --cask)
chezmoi apply --source "$DOTFILES/dotfiles"
copy_dotfile (dotfiles/.zshrc → $HOME/.zshrc)
run_zplug_install
chsh -s /bin/zsh  (silenced if fails)
touch "$MARKER_FILE"
```

---

## 4. macOS System Preferences

`macos/apply-settings.sh` applies developer-friendly defaults idempotently. Run manually
any time or via `install.sh`.

**What it sets:**

| Setting | Domain | Effect |
|---|---|---|
| Disable press-and-hold / key repeat | `NSGlobalDomain ApplePressAndHoldEnabled` + `com.apple.HIToolbox` | Characters repeat immediately on key hold |
| Fast key repeat rate | `NSGlobalDomain KeyRepeat=1, InitialKeyRepeat=15` + mirrored to `com.apple.HIToolbox` | Max repeat speed |
| Tap to click (built-in trackpad) | `com.apple.AppleMultitouchTrackpad Clicking=1, TrackpadTapBehavior=1` | Single-finger tap = click |
| Tap to click (Bluetooth/external) | `com.apple.driver.AppleBluetoothMultitouch.trackpad` + `-currentHost NSGlobalDomain` | Same for external devices |
| Require password on wake | `com.apple.screensaver askForPassword=1, askForPasswordDelay=0` | Lock immediately |
| No `.DS_Store` on network volumes | `com.apple.desktopservices DSDontWriteNetworkStores` | Cleaner shares |
| No Time Machine prompt for new drives | `com.apple.TimeMachine DoNotOfferNewDisksForBackup` | No nagging |

**Key technical notes:**

- `ApplePressAndHoldEnabled` / `KeyRepeat` / `InitialKeyRepeat` are written to **both**
  `NSGlobalDomain` and `com.apple.HIToolbox`. On macOS 13+ the input services layer reads
  these from `HIToolbox` at login and silently overrides `NSGlobalDomain`. Both domains are
  written so settings survive a re-login.
- `cfprefsd` caches preferences for all running processes. `defaults write` updates the
  on-disk plist, but the live `cfprefsd` continues serving cached older values. The script
  kills the **per-user** `cfprefsd` instances so launchd respawns them with the new values.
  A logged-out / logged-back-in session is still required for all keyboard repeat settings
  on macOS 13+.
- `ApplePressAndHoldEnabled` / `KeyRepeat` / `InitialKeyRepeat` via `defaults write` are
  deprecated since macOS 13 but still accepted. They may be overridden by the Keyboard
  system settings panel; they remain harmless.

**Manual re-run:**
```sh
DOTFILES="$HOME/.dotfiles" sh "$HOME/.dotfiles/macos/apply-settings.sh"
```

---

## 5. iTerm2 Preferences

### Approach
Whole-plist import via `defaults import com.googlecode.iterm2 <plist>`. **Not** a Python
mutation script. After any GUI change, re-export with:
```sh
defaults export com.googlecode.iterm2 "$DOTFILES/iterm2/com.googlecode.iterm2.plist.export"
```

### `apply-iterm.sh` flow
1. `plutil -lint "$PLIST_FILE"` — refuse to import invalid plist.
2. `pkill -f iTerm.app/Contents/MacOS/iTerm2` — stop iTerm2 (SIGTERM lets the daemon save state).
3. Poll until process exits (up to 5 s).
4. `defaults import com.googlecode.iterm2 "$PLIST_FILE"`.

### Font Format — CRITICAL (do not change)
iTerm2 3.6.11 has a **crash bug** with the NSKeyedArchiver font descriptor and with the
`{FontName/FontSize}` dict form. Only the legacy CFString `"Name Size"` form works:
```
Normal Font = "JetBrainsMono-Regular 15"
```
Both the dict and NSKeyedArchiver `NSFontDescriptor` forms produce:
```
-[<obj> fontValueWithLigaturesEnabled:]: unrecognized selector
in +[ITAddressBookMgr fontWithDesc:ligaturesEnabled:]
```
The committed `.plist.export` uses the CFString form. **Do not switch to dict or NSData.**

### Commit the Plist
The `.plist.export` file is committed to the repo. It contains personal keys
(`AiModel`, `AitermURL`, etc.). Consider `.gitignore`-excluding it if sharing publicly.

---

## 6. Neovim Configuration

- **init.vim location:** `~/.config/nvim/init.vim` (managed via chezmoi at
  `dotfiles/config/nvim/init.vim`; **force-copied** to `$HOME/.config/nvim` on fresh install).
- **Plugin manager:** vim-plug (installed by `install.sh`, NOT in `init.vim`).
  Reason: `system()` in vim script doesn't expand `~`; download is done in shell with curl.
- **Plugins:** NERDTree via `Plug 'preservim/nerdtree'`. `\n` toggles NERDTree.
- **vim-plug install path:** `$HOME/.local/share/nvim/site/autoload/plug.vim`
- **Plugin install:** `nvim --headless +PlugInstall +qall` (non-interactive).
- **Symlinks:** `~/.local/bin/vim` and `~/.local/bin/vi` both point to `nvim`. Prepended
  to `PATH` via `.zshenv` so they take priority over system vim in `/usr/bin`.

### init.vim Settings
```vim
set nocompatible
set tabstop=4 softtabstop=4 shiftwidth=4 expandtab
set hlsearch incsearch ignorecase smartcase
set hidden wildmenu
set mouse=a
set number relativenumber
```

---

## 7. Shell Configuration

### `.zshenv` vs `.zshrc`
- `.zshenv`: Always sourced (login + interactive). Environment variables, `PATH` setup,
  conditional chezmoi template source.
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
```sh
set -o vi                  # Vi line editing
bindkey -v                 # Vi keymap
alias rm='nocorrect rm'   # Prevent zsh spell-checker from correcting rm
# Oh My Zsh + zplug + Pure prompt
```

---

## 8. chezmoi

- **Source directory:** `dotfiles/` subdirectory of the repo.
- **Config:** `chezmoi.toml` at repo root.
- **`edit.command`:** `["nvim", "-c", "set nofoldenable"]` — opens nvim without folds.
- **`add.templateSymlinks`:** `true` — templates can create symlinks.
- **`diff.pager`:** `"less -R"` — coloured diffs in the terminal.
- **Claude API template:** sourced conditionally in `.zshenv` from
  `$HOME/.local/share/chezmoi/claude/templates/.zshenv` (only if present after first apply).

---

## 9. Homebrew Packages

### Formulae

| Package | Purpose |
|---|---|
| `neovim` | Text editor |
| `chezmoi` | Dotfile manager |
| `zplug` | Zsh plugin manager |
| `claude-code` | Claude Code CLI (terminal AI coding assistant, `claude` binary) — **distinct from the `claude` cask** |
| `opencode` | opencode CLI |
| `git` | Version control (managed by brew, not CLT) |

### Casks

| Cask | Purpose |
|---|---|
| `iterm2` | Terminal emulator |
| `font-jetbrains-mono` | Monospace font for NERDTree; referenced in iTerm2 prefs as `JetBrainsMono-Regular`. The font name must match exactly in the CFString plist entry. |
| `google-chrome` | Web browser |
| `firefox` | Web browser |
| `slack` | Team messaging |
| `whatsapp` | Messaging |
| `telegram` | Messaging |
| `chatgpt` | OpenAI ChatGPT desktop app |
| `claude` | Anthropic Claude desktop app (GUI) — **distinct from the `claude-code` CLI formula** |

**Note:** `claude-code` (formula) installs the `claude` CLI binary; `claude` (cask) installs
the `Claude.app` desktop GUI app. They are unrelated Homebrew packages that happen to share
a vendor. Do not conflate them.

---

## 10. Claude Code / opencode Integration

End-to-end flow:

1. `brew install claude-code` (cask) — installed by both `fresh_install` and `update`.
2. `sh claude/install.sh` — configures the Claude Code CLI (settings, statusline, templates).
3. `brew install opencode` (cask) — installed by both paths.
4. On subsequent `chezmoi apply`, `claude/templates/.zshenv` (a chezmoi template) is
   materialised to `$HOME/.local/share/chezmoi/claude/templates/.zshenv` and sourced
   conditionally from `dotfiles/.zshenv` only if present.

### Files

| File | Role |
|---|---|
| `claude/install.sh` | Bootstrap: installs Claude Code CLI, sets up config directory, applies settings.json |
| `claude/statusline-command.sh` | Renders the Claude Code statusline prompt |
| `claude/config/settings.json` | Claude Code API settings |
| `claude/templates/.zshenv` | chezmoi template for API config; conditional source in `dotfiles/.zshenv` |

---

## 11. `.gitignore`

```
docs/superpowers/
.worktrees/
```

If you create a git worktree for an experiment, it will be invisible to `git status` in the
main checkout. Delete the `.worktrees/` entry or remove the worktree entry from the file
if you need to track it.

---

## 12. Commit Conventions

Observed convention from `git log`:

| Prefix | Scope |
|---|---|
| `install:` | Changes to `install.sh` or its helper scripts |
| `docs:` | Changes to `CLAUDE.md`, `README.md`, or other documentation |
| `chezmoi:` | Changes to `chezmoi.toml` or managed files in `dotfiles/` |

Keep commit messages lowercase, imperative mood, max ~72 chars.
Do not commit directly to `main` — the user explicitly asks for `git push`.

---

## 13. Guardrails

**MUST NOT do the following without explicitly checking with the user first:**

1. **Do not change `Normal Font` in `iterm2/com.googlecode.iterm2.plist.export`** to dict
   form (`{FontName=...; FontSize=...}`) or NSKeyedArchiver `NSData`. This crashes iTerm2
   3.6.11. Only the CFString `"Name Size"` form is safe.

2. **Do not weaken `set -eu` / `set -euo pipefail` in any shell script.** These guards
   prevent silent failures in a `curl | sh` bootstrap.

3. **Do not commit or push** without being explicitly asked to. The working tree must
   be clean before push; `install.sh` does not commit.

4. **Do not modify `~/.dotfiles-installed` marker file semantics.** The file gates
   install vs. update. Do not delete it, move it, or change its path.

5. **Do not add new top-level Homebrew packages** without consulting the user. Each
   package changes the install surface area significantly.

6. **Do not modify `macos/apply-settings.sh`'s dual-domain write pattern or cfprefsd
   kill logic.** These are load-bearing: without them keyboard settings are silently
   ignored on macOS 13+.

7. **Do not use `～` (fullwidth tilde) or any non-ASCII variant** in any file path or
   string literal. Always use `$HOME` or ASCII tilde `~`.

8. **Do not introduce Python, Node, or Ruby dependency runners** (e.g. `pip install`,
   `npm install`, `gem install`) unless the user explicitly asks. This repo uses
   Homebrew and shell scripts only.

---

## 14. Verification & Testing

After any change to `install.sh`, `macos/apply-settings.sh`, `iterm2/apply-iterm.sh`, or
`claude/install.sh`:

```sh
# shellcheck (install shellcheck first if not present)
brew_install_if_missing ShellCheck shellcheck
shellcheck install.sh macos/apply-settings.sh iterm2/apply-iterm.sh claude/install.sh
```

After any change to `iterm2/com.googlecode.iterm2.plist.export`:

```sh
plutil -lint iterm2/com.googlecode.iterm2.plist.export
```

After any change to `chezmoi.toml` or managed files:

```sh
chezmoi diff --source dotfiles/
```

After any change to shell config files:

```sh
zsh -n dotfiles/.zshenv
zsh -n dotfiles/.zshrc
```

When editing `install.sh`, trace through both `fresh_install` and `update` mentally before
committing. All shared helpers must back at least two call sites (`f771884` convention).
Do not copy logic from a helper into both orchestrators — extend the helper instead.

---

## 15. Key Gotchas / Lessons Learned

1. **iTerm2 font must be CFString `"Name Size"`.** Dict and NSKeyedArchiver forms crash iTerm2 3.6.11.
2. **zsh uses `#` for comments, not `"`.** `"` after a command in `.zshrc` causes parse errors.
3. **`~` doesn't expand inside quotes in shell scripts.** Use `$HOME`.
4. **vim-plug install must happen in shell**, not via `system()` in vim — `~` expansion fails.
5. **chezmoi applies `dotfiles/` subdir**, not repo root. `chezmoi.toml` config reflects this.
6. **`chsh -s /bin/zsh` may prompt graphically.** Always silence: `2>/dev/null || warn`.
7. **On fresh macOS, git is missing** until CLT is installed. `ensure_build_tools()` handles
   this with silent `softwareupdate` (macOS 13+) and a GUI fallback via `xcode-select --install`.
8. **Marker file** (`$HOME/.dotfiles-installed`) gates install vs. update path. Delete to re-run fresh install.
9. **`~/.zshrc` may not be overwritten by `chezmoi apply`** when it already exists.
   `install.sh` force-copies it after `chezmoi apply` to ensure the managed version wins.
10. **The update path silently re-points `origin` remote** to `$REPO_URL` if it differs —
    convenient when migrating from a manual clone.
11. **macOS 13+ keyboard settings need a re-login** even after `cfprefsd` is killed, for
    all apps to pick up the new values.
12. **zplug occasionally returns non-zero from `zplug install`** — it re-clobbers completion
    files on some runs. `run_zplug_install` tolerates this by design (`d161613`).

---

## 16. Development Workflow

```sh
# Make changes to managed files
$EDITOR dotfiles/.zshrc
$EDITOR dotfiles/config/nvim/init.vim
$EDITOR macos/apply-settings.sh

# Verify before touching anything else
chezmoi diff --source dotfiles/

# Apply changes
chezmoi apply

# Commit
git add -p   # stage selectively
git commit -m "install: describe the change"
git push

# On another machine / fresh install
sh -c "$(curl -fsSL https://raw.githubusercontent.com/mcapanema/dotfiles/main/install.sh)"
```