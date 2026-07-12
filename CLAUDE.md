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
├── setup-ai-tools.sh            # Configure rtk/engram/graphify for Claude Code + opencode (manual run after install.sh)
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
├── claude/                      # Claude Code / opencode integration
│   ├── install.sh               # Claude Code + opencode installer
│   ├── statusline-command.sh    # Statusline renderer
│   ├── config/settings.json     # API settings
│   ├── templates/.zshenv       # chezmoi template for API config (conditional source in .zshenv)
│   └── test/                    # Internal test fixtures (do not ship)
├── devtools/                    # Development toolchains installer
│   ├── install.sh               # VSCode + Node/nvm + Ruby/rvm + Python/uv/pipx + Rust/rustup
│   └── vscode/settings.json    # Managed VSCode user settings (symlinked into ~/Library/Application Support/Code/User/)
└── lib/                         # Shared shell libraries (sourced by install.sh and child scripts)
    ├── common.sh                # Logging/presence primitives + symlink_into_place + soft_fail/tolerant_fail + install_uv_tool (sourced by all 6 scripts)
    ├── bootstrap.sh             # ensure_brew_on_path/install_homebrew/ensure_brew_git/ensure_build_tools/ensure_git (canonical source; install.sh keeps an inline copy for the curl-bootstrap case)
    ├── brew-packages.sh         # Per-group brew-install functions (install_core_casks/install_core_formulas/install_browsers/.../install_all_desktop_apps/install_ai_aux_tools)
    └── nvim.sh                  # Neovim setup helpers (vim_plug_installed/sync_neovim_config/sync_nvim_symlinks/ensure_vim_plug/install_nvim_plugins)
```

### Edit freely

`dotfiles/.zshenv`, `dotfiles/.zshrc`, `dotfiles/.zprofile`, `dotfiles/config/nvim/init.vim`,
`macos/apply-settings.sh`, `iterm2/apply-iterm.sh`, `claude/install.sh`, `claude/statusline-command.sh`,
`claude/config/settings.json`, `devtools/install.sh`, `devtools/vscode/settings.json`, `setup-ai-tools.sh`,
`lib/common.sh`, `lib/brew-packages.sh`, `lib/nvim.sh`, `CLAUDE.md`, `README.md`

### Edit with care — verify after changing

| File | Required check |
|---|---|
| `install.sh` | Trace through both `fresh_install` and `update` paths; run shellcheck if available. **Also audit `lib/bootstrap.sh`**: install.sh keeps an inline copy of those functions for the curl-bootstrap case — keep the two copies in sync |
| `lib/bootstrap.sh` | Run shellcheck; trace through both the inline `install.sh` copy and the lib copy (they must stay in sync) |
| `setup-ai-tools.sh` | Run shellcheck |
| `iterm2/com.googlecode.iterm2.plist.export` | Run `plutil -lint` before committing |
| `chezmoi.toml` | `diff` before `chezmoi apply` |
| `claude/templates/.zshenv` | Must be valid zsh syntax when sourced; test with `zsh -n` |
| `devtools/install.sh` | Run shellcheck; trace both `fresh_install` and `update` call sites |
| `devtools/vscode/settings.json` | Validate JSON (`python3 -m json.tool`) before committing |
| `dotfiles/.zshrc` | `zsh -n` after editing (nvm/rvm/rust lazy-loaders live here) |

---

## 3. `install.sh` Reference

### Pre-flight: brew + brew-managed git

`brew` and a Homebrew-managed `git` are **hard dependencies** of this repo — they are installed
*before* the repo is cloned, because the clone itself needs `git`. The bootstrap subsystem
(`ensure_brew_on_path` / `install_homebrew` / `ensure_brew_git` / `ensure_build_tools` / `ensure_git`)
lives in `lib/bootstrap.sh`, but `install.sh` keeps an **inline copy** of those same functions because
the curl-bootstrap path runs before `lib/` exists on disk. The two copies must stay in sync.

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

Some helpers live in `install.sh` directly; others have been factored out to `lib/`
files (sourced by `install.sh`'s `main()` after the repo is cloned). The "Where" column
shows the canonical location to edit.

| Helper | Where | What it does |
|---|---|---|
| `apply_macos_prefs` | install.sh | Runs `macos/apply-settings.sh` idempotently |
| `launch_iterm_once` | install.sh | Opens iTerm2 once so its defaults domain is registered before plist import; no-op if already running or not installed |
| `apply_iterm_prefs` | install.sh | Runs `iterm2/apply-iterm.sh` (stops iTerm, plutil -lint, defaults import, restart) |
| `install_omz` | install.sh | Shallow-clones Oh My Zsh to `$HOME/.oh-my-zsh` if absent |
| `sync_neovim_config` | lib/nvim.sh | Copies `dotfiles/config/nvim/init.vim` → `~/.config/nvim/init.vim` |
| `sync_nvim_symlinks` | lib/nvim.sh | Creates `~/.local/bin/{vim,vi}` → `nvim`; `~/.local/bin` is prepended to PATH via `.zshenv` |
| `ensure_vim_plug` | lib/nvim.sh | Downloads `plug.vim` into `$HOME/.local/share/nvim/site/autoload` if absent |
| `install_nvim_plugins` | lib/nvim.sh | Runs `nvim --headless +PlugInstall +qall`; tolerates errors |
| `install_claude_config` | install.sh | Runs `claude/install.sh`; tolerance controls whether errors are surfaced |
| `install_devtools` | install.sh | Runs `devtools/install.sh` (VSCode + Node/nvm + Ruby/rvm + Python/uv/pipx + Rust/rustup); tolerance controls whether errors are surfaced |
| `install_ai_aux_tools` | lib/brew-packages.sh | Installs rtk + engram (brew 3rd-party tap) + graphify + headroom (uv tool). Tolerance-aware; must run AFTER `install_devtools` so uv is on PATH |
| `install_uv_tool` | lib/common.sh (+ inline in install.sh) | Installs a CLI as a uv-managed global tool (`uv tool install <spec>`) if the command is not already on PATH. Backs the graphify/headroom installs. |
| `copy_dotfile` | install.sh | Force-copies `dotfiles/.zshrc` → `$HOME/.zshrc` (see note below) |
| `run_zplug_install` | install.sh | Runs `zplug install` in a clean zsh session; tolerates non-zero exit by design |

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

These two primitives plus the higher-level logging/symlink/tolerance helpers live in
`lib/common.sh`, sourced by the five child scripts (`devtools/install.sh`,
`claude/install.sh`, `setup-ai-tools.sh`, `macos/apply-settings.sh`,
`iterm2/apply-iterm.sh`). `install.sh` keeps inline copies of the primitives it uses
(`info`, `warn`, `fail`, `cmd_available`, `brew_installed`, `brew_install_if_missing`,
`install_uv_tool`) because the curl-bootstrap path runs before `lib/` exists on disk;
the lib copy is the canonical source for the child scripts, and `install.sh`'s inline
copy is the canonical source for itself. Keep the two in sync when editing.

### lib/brew-packages.sh — per-group brew install functions

The 30+ `brew_install_if_missing` calls that back the desktop-app and CLI-tool list
are factored into `lib/brew-packages.sh` to eliminate the duplication that previously
existed between `fresh_install` and `update`. The functions are grouped per
CLAUDE.md §9 (Browsers, Messaging, AI Assistants, Productivity, Menu Bar, Security,
Dev Tools, CLI tools):

| Function | Casks / formulas | Called by |
|---|---|---|
| `install_core_casks` | JetBrains Mono, iTerm2 | `fresh_install` only (update assumes they persist once installed) |
| `install_core_formulas` | zplug, neovim, chezmoi, claude-code | both `fresh_install` and `update` (a formula may have been `brew uninstall`ed) |
| `install_browsers` | Google Chrome, Firefox | both |
| `install_messaging` | Slack, WhatsApp, Telegram | both |
| `install_ai_assistants` | ChatGPT, Claude | both |
| `install_productivity` | Mos, Alfred, Contexts, BetterTouchTool, Moom, AppCleaner | both |
| `install_menu_bar` | iStat Menus, Bartender | both |
| `install_security` | 1Password, NordVPN | both |
| `install_dev_tools` | Docker Desktop | both |
| `install_cli_tools` | opencode, Codex | both |
| `install_ai_aux_tools(tolerance)` | rtk, engram, graphify, headroom | both (tolerance-aware) |
| `install_all_desktop_apps` | Convenience wrapper = `install_browsers + install_messaging + ... + install_cli_tools` | both |

### Full install-order list (fresh_install)

```
apply_macos_prefs
install_homebrew
install_core_casks
  brew_install_if_missing JetBrains Mono (font-jetbrains-mono --cask)
  brew_install_if_missing iTerm2 (iterm2 --cask)
brew install git
install_omz
launch_iterm_once
apply_iterm_prefs
install_core_formulas
  brew_install_if_missing zplug
  brew_install_if_missing Neovim
  brew_install_if_missing chezmoi
  brew_install_if_missing claude-code
sync_neovim_config
sync_nvim_symlinks
ensure_vim_plug
install_nvim_plugins
install_claude_config
install_devtools
install_ai_aux_tools warn
  brew_install_if_missing rtk
  brew tap gentleman-programming/tap
  brew_install_if_missing engram (gentleman-programming/tap/engram)
  install_uv_tool warn graphify (graphifyy)
  install_uv_tool warn headroom (headroom-ai[all])
install_all_desktop_apps
  install_browsers        (Google Chrome, Firefox)
  install_messaging       (Slack, WhatsApp, Telegram)
  install_ai_assistants   (ChatGPT, Claude)
  install_productivity    (Mos, Alfred, Contexts, BetterTouchTool, Moom, AppCleaner)
  install_menu_bar        (iStat Menus, Bartender)
  install_security        (1Password, NordVPN)
  install_dev_tools       (Docker Desktop)
  install_cli_tools       (opencode, Codex)
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
  `dotfiles/config/nvim/init.vim`; **also force-copied** to `$HOME/.config/nvim`
  by `lib/nvim.sh`'s `sync_neovim_config` before `chezmoi apply` runs). The
  redundancy is intentional: `install_nvim_plugins` runs `:PlugInstall` against
  `init.vim` and needs the file on disk before `chezmoi apply` has materialized
  it. Removing `sync_neovim_config` is safe only if `chezmoi apply` is
  simultaneously reordered to precede `install_nvim_plugins` in both
  `fresh_install` and `update`.
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
# Dev toolchains lazy-loaders (nvm, rvm, ~/.cargo/env) — see Section 11
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
| `nvm` | Node version manager (sourced in `.zshrc`; brew `node` formula intentionally NOT installed — nvm owns Node) |
| `python@3.14` | Python 3 interpreter (`python3`, `pip3`); aliased as `python`, `python3` |
| `uv` | Fast Python package installer/resolver (alternative to pip/virtualenv); also manages Python versions |
| `pipx` | Run global CLI Python tools in isolated envs (e.g. `pipx install black`) |
| `rustup` | Rust toolchain installer (keg-only — invoke via `$(brew --prefix rustup)/bin/rustup`); manages `rustc`/`cargo`/`clippy`. Formula 1.29.0_2+ no longer ships `rustup-init` — use `rustup install stable` to bootstrap. |
| `rtk` | CLI proxy that compresses command outputs before they reach the LLM (60–90% token savings). First-party formula at `formulae.brew.sh/formula/rtk`; ships a prebuilt Rust binary, no Rust toolchain needed at install time. |
| `engram` (via `gentleman-programming/tap/engram`) | Persistent memory for AI coding agents (SQLite + FTS5, MCP server). Third-party tap — `install.sh` runs `brew tap gentleman-programming/tap` before `brew install`. Ships a Go binary with SQLite compiled in, no runtime dependencies. |

### Casks

Casks are grouped below to mirror the grouped `brew_install_if_missing` blocks in
`install.sh` (both `fresh_install` and `update`).

#### Browsers

| Cask | Purpose |
|---|---|
| `google-chrome` | Web browser |
| `firefox` | Web browser |

#### Communication & Messaging

| Cask | Purpose |
|---|---|
| `slack` | Team messaging |
| `whatsapp` | Messaging |
| `telegram` | Messaging |

#### AI Assistants

| Cask | Purpose |
|---|---|
| `chatgpt` | OpenAI ChatGPT desktop app |
| `claude` | Anthropic Claude desktop app (GUI) — **distinct from the `claude-code` CLI formula** |

#### Productivity & Utilities

| Cask | Purpose |
|---|---|
| `mos` | Smooth scrolling + independent scroll direction per device |
| `alfred` | Application launcher and productivity software (paid "Powerpack" for advanced features) |
| `contexts` | Window switcher — more productive Cmd-Tab / Alt-Tab alternative (paid) |
| `bettertouchtool` | Input-device customisation and window snapping automation (paid, trial-ware) |
| `moom` | Window resizing/zoom utility (paid, trial-ware) |
| `appcleaner` | Application uninstaller — removes apps and their associated support files |

#### Menu Bar & System Monitoring

| Cask | Purpose |
|---|---|
| `istat-menus` | System monitoring (CPU, memory, network, sensors) in the menu bar (paid, trial-ware) |
| `bartender` | Menu-bar icon organiser — hide/reorder status items (paid, trial-ware) |

#### Security & Networking

| Cask | Purpose |
|---|---|
| `1password` | Password manager |
| `nordvpn` | VPN client for secure/private internet access |

#### Developer Tools

| Cask | Purpose |
|---|---|
| `iterm2` | Terminal emulator |
| `font-jetbrains-mono` | Monospace font for NERDTree; referenced in iTerm2 prefs as `JetBrainsMono-Regular`. The font name must match exactly in the CFString plist entry. |
| `visual-studio-code` | VS Code editor (user settings symlinked from `devtools/vscode/settings.json`) |
| `docker-desktop` | Docker Desktop GUI for containerised development. **The `docker` formula (CLI-only) is intentionally NOT installed** — `docker-desktop --cask` is the sole source of `docker` on this machine. **Note:** as of 2024 Docker Inc. requires a paid subscription for larger organisations using Docker Desktop; personal/small-org use remains free. |
| `codex` | OpenAI Codex CLI (terminal coding agent, `codex` binary) — **distinct from the `chatgpt` cask**, which is the OpenAI ChatGPT desktop app. Listed here because it ships as a cask, not a formula. |

**Note:** `claude-code` (formula) installs the `claude` CLI binary; `claude` (cask) installs
the `Claude.app` desktop GUI app. They are unrelated Homebrew packages that happen to share
a vendor. Do not conflate them.

**Note on Amphetamine:** Amphetamine (keep-Mac-awake utility) is **intentionally NOT**
installed via Homebrew because it is distributed exclusively through the Mac App Store
(no cask exists). Install it manually from the App Store if desired. Alternatives
available as casks include `keepingyouawake` and `caffeine` (not installed by this repo).

**Note on Node:** `nvm` is the sole source of Node versions. The brew `node` formula is
intentionally **not** installed and is removed by `devtools/install.sh` if found. This is by
design — `nvm install <ver>` manages all Node versions in `~/.nvm/versions/`.

**Note on Rust:** `rustup` formula is **keg-only** (not symlinked to `/opt/homebrew/bin`).
`devtools/install.sh` invokes `$(brew --prefix rustup)/bin/rustup install stable` to bootstrap
the default toolchain into `~/.rustup/toolchains`. The shim binaries at
`/opt/homebrew/opt/rustup/bin` (and `~/.cargo/bin` for non-brew installs) are added to PATH
in `.zprofile`. Formula 1.29.0_2+ no longer ships `rustup-init`; use `rustup install stable`
instead.

**Note on rtk:** `rtk` is a first-party Homebrew formula (`formulae.brew.sh/formula/rtk`). It ships as a single Rust binary; `brew install rtk` includes the prebuilt binary — no Rust toolchain required at install time.

**Note on engram:** `engram` lives in a third-party tap (`gentleman-programming/tap/engram`). `install.sh` runs `brew tap gentleman-programming/tap` before `brew install gentleman-programming/tap/engram`. It ships as a single Go binary with SQLite + FTS5 compiled in — no Go toolchain or runtime dependencies required.

**Note on AI auxiliary tools (uv-managed):** `graphify` and `headroom` are installed via `uv tool install` (`graphifyy`; `headroom-ai[all]`) — NOT via Homebrew. `uv tool install` creates an isolated virtualenv per tool and symlinks the CLI into `~/.local/bin` (on PATH via `.zshenv`). This is **compliant with guardrail #8**: it installs a standalone manager-managed CLI (same pattern as the devtools orchestrator installing `uv` / `pipx`), NOT a `pip install` / `npm install` / `gem install` of a library into a project or system interpreter. Binaries land in `~/.local/bin`, not in any Python environment.

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

### 10.1 AI auxiliary tools (rtk, engram, graphify, headroom)

Binaries are installed by `install.sh` (both `fresh_install` and `update`):
- `rtk` — brew formula
- `engram` — brew 3rd-party tap (`gentleman-programming/tap/engram`)
- `graphify` — uv-managed (`uv tool install graphifyy`)
- `headroom` — uv-managed (`uv tool install "headroom-ai[all]"`)

**Agent integration (hooks / MCP config / skills) is NOT run by `install.sh`** — it's a distinct, manual step via `setup-ai-tools.sh`:

```sh
sh "$HOME/.dotfiles/setup-ai-tools.sh"
```

The script configures rtk, engram, and graphify for **both** Claude Code and opencode:

| Tool | Claude Code | opencode |
|---|---|---|
| rtk | `rtk init -g --auto-patch` | `rtk init -g --opencode --auto-patch` |
| engram | `claude plugin marketplace add Gentleman-Programming/engram && claude plugin install engram` | `engram setup opencode` |
| graphify | `graphify install` | `graphify install --platform opencode` |

`headroom` is **intentionally excluded** from `setup-ai-tools.sh` — `headroom wrap claude` launches a live wrapped session (interactive, runtime), not durable config. Run it manually per session when you want live compression:

```sh
headroom wrap claude    # starts proxy + MCP + launches wrapped Claude Code
headroom unwrap claude  # undo durable agent config writes
```

After running `setup-ai-tools.sh`, **restart both Claude Code and opencode** so rtk's PreToolUse hook, engram's MCP subprocess, and graphify's skill all load fresh.

**Undo:**
- `rtk init -g --uninstall`
- `claude plugin uninstall engram`
- `graphify uninstall`

---

## 11. Development Toolchains

End-to-end flow:

1. `devtools/install.sh` is invoked by `install.sh` (both `fresh_install` and `update`).
2. It installs the manager tool for each language:
   - **VSCode** — cask `visual-studio-code` + symlinked `settings.json` into the VSCode User dir.
   - **Node** — `brew install nvm`; **removes** any existing brew `node` formula so nvm owns Node; installs a default LTS.
   - **Ruby** — `rvm` via its official `curl -sSL https://get.rvm.io | bash -s stable` installer (same trust pattern as the Homebrew and Oh My Zsh bootstraps in `install.sh`).
   - **Python** — `brew install python@3.14` (`python3`, `pip3`), `uv` (fast pip/replacement), `pipx` (isolated CLI tools).
   - **Rust** — `brew install rustup` (keg-only), then `rustup install stable --profile default --no-self-update`.
3. Only the **manager** is installed; specific language versions are user-driven
   (`nvm install <ver>`, `rvm install <ver>`, `uv python install <ver>`,
   `rustup toolchain install <ver>`).

### Files

| File | Role |
|---|---|
| `devtools/install.sh` | Bootstrap: installs VSCode, Node/nvm, Ruby/rvm, Python/uv/pipx, Rust/rustup and symlinks VSCode user settings |
| `devtools/vscode/settings.json` | Managed VSCode user settings — symlinked into `~/Library/Application Support/Code/User/settings.json` (backed up if pre-existing) |

### Shell configuration rules — IMPORTANT

- **Never put `nvm` / `rvm` source statements in `dotfiles/.zshenv`.** `.zshenv` is sourced for
  every shell including non-interactive ones; sourcing nvm/rvm adds 250ms+ to every invocation
  (and runs on every `git` call from tools). They live in `dotfiles/.zshrc` instead, which is
  only sourced for interactive shells.
- **Source `rvm` AFTER `nvm`** in `.zshrc` so rvm's PATH adjustments (which prepend ruby gem
  bins) win over nvm's. Sourcing order matters.
- **`~/.cargo/bin` and `/opt/homebrew/opt/rustup/bin` are wired in `dotfiles/.zprofile`**.
  Both are needed: brew's `rustup` formula is keg-only (its shims live at the second path)
  while non-brew rustup installs populate `~/.cargo`. They must stay in `.zprofile` (login
  shell PATH) because macOS `path_helper` rebuilds PATH on login and would otherwise drop them.
- **`uv` and `pipx` require no shell init** — `uv` is a single binary on the brew PATH;
  `pipx ensurepath` prepends `~/.local/bin`, already on PATH via `.zshenv`.

---

## 12. `.gitignore`

```
docs/superpowers/
.worktrees/
```

If you create a git worktree for an experiment, it will be invisible to `git status` in the
main checkout. Delete the `.worktrees/` entry or remove the worktree entry from the file
if you need to track it.

---

## 13. Commit Conventions

Observed convention from `git log`:

| Prefix | Scope |
|---|---|
| `install:` | Changes to `install.sh` or its helper scripts |
| `docs:` | Changes to `CLAUDE.md`, `README.md`, or other documentation |
| `chezmoi:` | Changes to `chezmoi.toml` or managed files in `dotfiles/` |

Keep commit messages lowercase, imperative mood, max ~72 chars.
Do not commit directly to `main` — the user explicitly asks for `git push`.

---

## 14. Guardrails

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
   Homebrew and shell scripts only. The `devtools/install.sh` orchestrator (Section 11)
   was explicitly authorised by the user to install the **manager** tools (nvm, rvm, uv,
   pipx, rustup); it does not invoke `pip install` / `npm install` / `gem install` itself.
   Future additions to that surface still require explicit user authorisation.

---

## 15. Verification & Testing

After any change to `install.sh`, `macos/apply-settings.sh`, `iterm2/apply-iterm.sh`,
`claude/install.sh`, `devtools/install.sh`, `setup-ai-tools.sh`, or any `lib/*.sh` file:

```sh
# shellcheck (install shellcheck first if not present)
brew_install_if_missing ShellCheck shellcheck
shellcheck install.sh lib/common.sh lib/bootstrap.sh lib/brew-packages.sh lib/nvim.sh \
           macos/apply-settings.sh iterm2/apply-iterm.sh claude/install.sh \
           devtools/install.sh setup-ai-tools.sh
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
Do not copy logic from a helper into both orchestrators — extend the helper instead. The
per-group brew-install functions in `lib/brew-packages.sh` are the canonical example: add
new casks/formulas there rather than duplicating install calls across the two orchestrators.
When editing the inline bootstrap primitives at the top of `install.sh`, **also update
`lib/bootstrap.sh`** — the two copies must stay in sync (see §3 Pre-flight).

---

## 16. Key Gotchas / Lessons Learned

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
13. **`rustup` formula is keg-only** — `$(brew --prefix rustup)/bin/rustup` must be
    invoked directly (not `rustup` on PATH). Formula 1.29.0_2+ no longer ships
    `rustup-init`; use `rustup install stable` to bootstrap the default toolchain.
    `~/.rustup/toolchains/` holds the actual toolchain, and rustup's shims live at
    `/opt/homebrew/opt/rustup/bin` (wired in `.zprofile`). `~/.cargo/bin` is also wired
    in `.zprofile` for non-brew rustup installs.
14. **`nvm` must be the only Node source.** If brew's `node` formula coexists, PATH confusion
    results. `devtools/install.sh` removes any brew `node` formula before installing nvm.
15. **`nvm` / `rvm` source statements must live in `.zshrc`**, never `.zshenv` (sourced for
    every shell incl. non-interactive; adds 250ms+ to every invocation including `git` calls
    from other tools).
16. **rvm is installed via `curl | bash` from get.rvm.io** — same trust pattern as Homebrew
    and Oh My Zsh. RVM is the only tool in this repo not available via Homebrew.

17. **`uv tool install <pkg>` is not `pip install`.** It creates an isolated venv per CLI tool
    and symlinks the binary into `~/.local/bin` (already on PATH via `.zshenv`). This is
    compliant with guardrail #8 — it installs a manager-managed standalone CLI, not a
    project / system-interpreter library. `graphifyy` (note the double-y; the CLI is `graphify`)
    and `headroom-ai[all]` are installed this way.

18. **`engram` lives in a third-party brew tap.** `brew install gentleman-programming/tap/engram`
    does NOT auto-tap — `install.sh` runs `brew tap gentleman-programming/tap` explicitly before
    the `brew install`. The `brew_install_if_missing` helper's `brew install "$@" "$_pkg"` call
    passes the fully-qualified `tap/package` name as the package argument, but the tap must
    already exist or the install fails.

---

## 17. Development Workflow

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