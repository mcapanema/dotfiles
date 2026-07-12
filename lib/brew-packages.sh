#!/bin/sh
# lib/brew-packages.sh — per-group brew install functions shared by
# fresh_install and update.  Sourced (never executed directly) by install.sh.
#
# Each per-group function encapsulates a category from CLAUDE.md §9
# (Browsers, Messaging, AI Assistants, Productivity, Menu Bar, Security,
# Developer Tools, CLI tools).  Calling the group functions from both
# orchestrators means a new cask is a 1-line change here rather than a
# 2-line change duplicated across fresh_install and update.
#
# brew_install_if_missing is non-tolerant by design: a failed `brew install`
# aborts the run under `set -e`.  This preserves the existing contract —
# a cask that fails to install on fresh install is a hard failure.  The
# tolerance-aware helpers (install_ai_aux_tools) only wrap uv-managed
# installs that already had a tolerance arg.

# install_core_casks — the casks that fresh_install installs eagerly so
# their defaults domain is registered before preferences are imported.
# Update does NOT call this (it assumes these casks persist once installed).
install_core_casks() {
    brew_install_if_missing "JetBrains Mono" font-jetbrains-mono --cask
    brew_install_if_missing "iTerm2" iterm2 --cask
}

# install_core_formulas — the brew formulas both paths ensure are present.
# Update calls this too because a formula may have been `brew uninstall`ed
# (unlike a cask, which persists once installed).
install_core_formulas() {
    brew_install_if_missing "zplug" zplug
    brew_install_if_missing "Neovim" neovim
    brew_install_if_missing "chezmoi" chezmoi
    brew_install_if_missing "Claude Code" claude-code
}

# Desktop apps — Browsers
install_browsers() {
    brew_install_if_missing "Google Chrome" google-chrome --cask
    brew_install_if_missing "Firefox" firefox --cask
}

# Desktop apps — Communication & Messaging
install_messaging() {
    brew_install_if_missing "Slack" slack --cask
    brew_install_if_missing "WhatsApp" whatsapp --cask
    brew_install_if_missing "Telegram" telegram --cask
}

# Desktop apps — AI Assistants
install_ai_assistants() {
    brew_install_if_missing "ChatGPT" chatgpt --cask
    brew_install_if_missing "Claude" claude --cask
    brew_install_if_missing "Codex" codex-app --cask
}

# Desktop apps — Productivity & Utilities
install_productivity() {
    brew_install_if_missing "Mos" mos --cask
    brew_install_if_missing "Alfred" alfred --cask
    brew_install_if_missing "Contexts" contexts --cask
    brew_install_if_missing "BetterTouchTool" bettertouchtool --cask
    brew_install_if_missing "Moom" moom --cask
    brew_install_if_missing "AppCleaner" appcleaner --cask
}

# Desktop apps — Menu Bar & System Monitoring
install_menu_bar() {
    brew_install_if_missing "iStat Menus" istat-menus --cask
    brew_install_if_missing "Bartender" bartender --cask
}

# Desktop apps — Security & Networking
install_security() {
    brew_install_if_missing "1Password" 1password --cask
    brew_install_if_missing "NordVPN" nordvpn --cask
}

# Desktop apps — Developer Tools
install_dev_tools() {
    brew_install_if_missing "Docker Desktop" docker-desktop --cask
}

# CLI tools (not desktop GUI apps).
install_cli_tools() {
    brew_install_if_missing "opencode CLI" opencode
    brew_install_if_missing "Codex CLI" codex --cask
}

# AI auxiliary tools — must run AFTER install_devtools so uv is on PATH
# for the graphify/headroom installs (uv is a devtools dependency).
# engram lives in a third-party tap — tap it explicitly before install.
#   $1: tolerance — "warn" surfaces failures, "true" swallows them.
install_ai_aux_tools() {
    _tolerance="${1:-warn}"
    brew_install_if_missing "rtk" rtk
    brew tap gentleman-programming/tap 2>/dev/null || true
    brew_install_if_missing "engram" gentleman-programming/tap/engram
    install_uv_tool "$_tolerance" "graphify" "graphifyy" "graphify"
    install_uv_tool "$_tolerance" "headroom" "headroom-ai[all]" "headroom"
}

# install_all_desktop_apps — convenience wrapper for the user-facing GUI
# apps.  Both fresh_install and update install the same set; the only
# difference is whether core_casks is called first (fresh only).
install_all_desktop_apps() {
    install_browsers
    install_messaging
    install_ai_assistants
    install_productivity
    install_menu_bar
    install_security
    install_dev_tools
    install_cli_tools
}
