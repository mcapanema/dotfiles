# Chezmoi Dotfiles Repository — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a chezmoi-managed dotfiles repo that bootstraps a fresh macOS machine with ZSH + Oh My Zsh + zplug + Pure + Snazzy iTerm2 theme.

**Architecture:** Single GitHub repo at `github.com/mcapanema/dotfiles`. Chezmoi source at repo root. All managed files live under `dotfiles/` subdirectory (chezmoi's `{{ .sourceDir }}`).

---

## Global Constraints

- macOS Darwin (darwin arm64)
- ZSH 5.9
- Homebrew installed at `/opt/homebrew`
- All path references exact, no env var assumptions
- GitHub repo: `github.com/mcapanema/dotfiles`

---

## File Structure

```
dotfiles/
├── chezmoi.toml              # chezmoi config (sourcePath = repo root)
├── README.md                 # setup instructions
├── dotfiles/                 # managed home directory files
│   ├── .zshrc               # main shell config (oh-my-zsh + zplug + plugins)
│   ├── .zprofile            # login shell: Homebrew env
│   └── .zshenv              # base env vars (EDITOR, LANG, PATH)
├── iterm2/                   # terminal configuration
│   ├── Snazzy.itermcolors   # color scheme
│   └── com.googlecode.iterm2.plist  # full iTerm2 preferences
└── scripts/
    └── install.sh            # bootstraps fresh machine
```

---

### Task 1: Create chezmoi.toml

**Files:**
- Create: `chezmoi.toml`
- Modify: `README.md`

**Interfaces:**
- Produces: `chezmoi.toml` with `sourcePath` = repo root, `destination` = `$HOME`, `add` templateSymlinks enabled

- [ ] **Step 1: Write `chezmoi.toml`**

```toml
sourcePath = "/Users/murilo/Workspace/dotfiles"
destination = "/Users/murilo"

[edit]
  command = "code"

[add]
  templateSymlinks = true

[diff]
  pager = "less -R"
```

- [ ] **Step 2: Update README.md** with setup instructions for the repo structure

- [ ] **Step 3: Commit**

---

### Task 2: Create dotfiles/.zshenv

**Files:**
- Create: `dotfiles/.zshenv`

**Interfaces:**
- Produces: `~/.zshenv` — base env vars always loaded

- [ ] **Step 1: Write `dotfiles/.zshenv`**

```
export LANG=en_US.UTF-8
export EDITOR=vim
export VISUAL=vim

# Avoid duplicates in PATH
typeset -U PATH
```

- [ ] **Step 2: Commit**

---

### Task 3: Create dotfiles/.zprofile

**Files:**
- Create: `dotfiles/.zprofile`

**Interfaces:**
- Consumes: Homebrew shellenv output
- Produces: `~/.zprofile` — login shell, sets up Homebrew PATH

- [ ] **Step 1: Write `dotfiles/.zprofile`**

```zsh
# Homebrew shellenv — must be first
eval "$(/opt/homebrew/bin/brew shellenv zsh)"

# Re-add Cargo after macOS path_helper rebuilds PATH
case ":${PATH}:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) export PATH="$HOME/.cargo/bin:$PATH" ;;
esac
```

- [ ] **Step 2: Commit**

---

### Task 4: Create dotfiles/.zshrc

**Files:**
- Create: `dotfiles/.zshrc`

**Interfaces:**
- Consumes: `ZPLUG_HOME`, `$ZSH`
- Produces: `~/.zshrc` — oh-my-zsh sourced, zplug plugins loaded, pure prompt

- [ ] **Step 1: Write `dotfiles/.zshrc`**

```zsh
# Oh My Zsh configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=(git)
source $ZSH/oh-my-zsh.sh

# zplug configuration
export ZPLUG_HOME=$(brew --prefix)/opt/zplug
source $ZPLUG_HOME/init.zsh

zplug "mafredri/zsh-async", from:github
zplug "sindresorhus/pure", use:pure.zsh, from:github, as:theme
zplug "zsh-users/zsh-syntax-highlighting", as:plugin, defer:2
zplug "zsh-users/zsh-autosuggestions", as:plugin, defer:2

zplug load

# Auto-install plugins if missing
if ! zplug check --verbose; then
    printf "Install plugins? [y/N]: "
    if read -q; then
        echo; zplug install
    fi
fi

# Local bin
export PATH="$HOME/.local/bin:$PATH"
```

- [ ] **Step 2: Commit**

---

### Task 5: Download iTerm2 Snazzy color scheme

**Files:**
- Create: `iterm2/Snazzy.itermcolors`

**Interfaces:**
- Consumes: GitHub raw URL for Snazzy
- Produces: `iterm2/Snazzy.itermcolors` in source

- [ ] **Step 1: Download the theme**

```bash
mkdir -p iterm2
curl -o iterm2/Snazzy.itermcolors \
  https://raw.githubusercontent.com/sindresorhus/iterm2-snazzy/main/Snazzy.itermcolors
```

- [ ] **Step 2: Verify the file is valid XML**

```bash
head -5 iterm2/Snazzy.itermcolors
```

Expected: `<?xml version="1.0" encoding="UTF-8"?>`

- [ ] **Step 3: Commit**

---

### Task 6: Export iTerm2 full preferences

**Files:**
- Create: `iterm2/com.googlecode.iterm2.plist`

**Interfaces:**
- Consumes: Current iTerm2 plist from `~/Library/Preferences`
- Produces: Portable iTerm2 prefs in source directory

- [ ] **Step 1: Copy existing plist**

```bash
cp ~/Library/Preferences/com.googlecode.iterm2.plist iterm2/com.googlecode.iterm2.plist
```

- [ ] **Step 2: Commit**

---

### Task 7: Create bootstrap install script

**Files:**
- Create: `scripts/install.sh`

**Interfaces:**
- Consumes: Homebrew, chezmoi, GitHub repo URL
- Produces: Fully provisioned shell environment on a fresh machine

- [ ] **Step 1: Write `scripts/install.sh`**

```zsh
#!/bin/zsh
set -e

echo "==> Installing Homebrew..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo "==> Installing chezmoi..."
brew install chezmoi

echo "==> Initializing chezmoi from dotfiles repo..."
chezmoi init https://github.com/mcapanema/dotfiles
chezmoi apply

echo "==> Installing zplug..."
brew install zplug

echo "==> Installing plugins..."
zsh -i -c "zplug install"

echo "==> Importing iTerm2 preferences..."
open $(chezmoi source-path)/iterm2/Snazzy.itermcolors
cp $(chezmoi source-path)/iterm2/com.googlecode.iterm2.plist ~/Library/Preferences/

echo ""
echo "Done! Please:"
echo "  1. Restart iTerm2"
echo "  2. Select Snazzy theme: Preferences > Profiles > Colors > Color Presets > Snazzy"
echo "  3. Restart zsh"
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x scripts/install.sh
```

- [ ] **Step 3: Commit**