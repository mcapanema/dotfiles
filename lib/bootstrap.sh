#!/bin/sh
# lib/bootstrap.sh — Homebrew, brew-managed git, and Command Line Tools
# pre-flight.  Sourced (never executed directly) by install.sh.
#
# These functions guarantee a working `git` on PATH before the repo is
# cloned.  They are the hard dependency of this repo — both fresh install
# (called before `git clone`) and update (called via ensure_build_tools for
# `git pull`) rely on them.
#
# NOTE: install.sh keeps an inline copy of these functions at the top of
# the file for the curl-bootstrap case where $DOTFILES_DIR/lib/ does not
# yet exist.  This file is the canonical source; the inline copy is
# re-sourced after the clone so the maintainer versions win.  Keep both
# in sync when editing.

# Constants used only by the bootstrap subsystem.
BREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

# ensure_brew_on_path — re-sources brew's shellenv so `brew` resolves.
# Used after a fresh brew install and at the top of every update run.
ensure_brew_on_path() {
    if [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    if ! cmd_available brew; then
        fail "Homebrew is installed but 'brew' is not on PATH."
    fi
}

# install_homebrew — installs Homebrew if missing, then ensures it is on
# PATH.  Idempotent.  Used both as a hard dependency of this repo (called
# before clone) and inside fresh_install.
install_homebrew() {
    if cmd_available brew; then
        ensure_brew_on_path
        return 0
    fi
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL "$BREW_INSTALL_URL")"
    ensure_brew_on_path
}

# ensure_brew_git — guarantees a Homebrew-managed git binary is present
# and resolvable.  Treats brew as a hard dependency of this repo so a
# freshly cloned machine does not depend on Apple's older CLT git.
ensure_brew_git() {
    install_homebrew
    _brew_prefix="$(brew --prefix)"
    if [ -x "$_brew_prefix/bin/git" ] && \
       "$_brew_prefix/bin/git" --version >/dev/null 2>&1; then
        info "brew git already available at $_brew_prefix/bin/git"
        return 0
    fi
    info "Installing git via Homebrew..."
    brew install git
}

# Pre-flight: build tools.
# On a completely fresh macOS install git is only available after the
# Command Line Tools package is installed.  CLT ships a git binary at
# /Library/Developer/CommandLineTools/usr/bin/git that is on PATH once
# xcode-select has been run.  This function:
#   1. Checks whether git already resolves (fast path on a configured box).
#   2. If not, tries to install CLT silently via softwareupdate(8)'s
#      --agree-to-license flag (works on macOS 13+ without user interaction).
#   3. Falls back to opening the standard GUI installer if step 2 fails.
#      The script blocks until the user dismisses the dialog or a 3-minute
#      timeout expires — this is the only interactive step that cannot be
#      avoided on a completely fresh machine.
ensure_build_tools() {
    if command -v git >/dev/null 2>&1; then
        info "git already available, skipping CLT setup."
        return 0
    fi

    info "git not found — ensuring Command Line Tools..."

    # Attempt silent install (no GUI) via softwareupdate(8).
    # --agree-to-license skips the licence prompt on macOS 13+.
    # We try twice because the package label may or may not carry a
    # version suffix (e.g. "Command Line Tools for Xcode" vs
    # "Command Line Tools for Xcode 26.5").
    for _ in 1 2; do
        softwareupdate --install --agree-to-license -r \
            "Command Line Tools for Xcode" >/dev/null 2>&1 && break
        sleep 2
    done

    # softwareupdate exits 0 even when there was nothing to install.
    # Verify git is actually on PATH rather than trusting the exit code.
    if command -v git >/dev/null 2>&1; then
        info "CLT / git is now available."
    else
        # Silent install didn't apply (no matching update).  Fall back to
        # the standard GUI installer.  The script blocks here until the
        # user dismisses the dialog or 3 minutes elapse.
        warn "Silent CLT install failed — opening GUI installer."
        warn "After installation finishes, dismiss the dialog."
        warn "This script will resume automatically."
        warn "If the dialog stays open longer than 3 minutes, Ctrl-C and"
        warn "re-run this script after CLT is installed."
        xcode-select --install || true
    fi

    # Poll for up to 3 minutes for git to appear after the GUI install.
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
             21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36; do
        sleep 5
        if command -v git >/dev/null 2>&1; then
            info "git is now available."
            return 0
        fi
    done

    fail "Command Line Tools did not become available after 3 minutes. " \
         "Install Xcode Command Line Tools manually and re-run this script."
}

# ensure_git — installs brew + brew-managed git as dependencies before any
# `git clone` of this repo.  If brew is somehow unreachable, falls back to
# the CLT-based path via ensure_build_tools.
ensure_git() {
    ensure_brew_git
    # Final sanity: `git` must actually resolve on PATH at this point.
    if ! command -v git >/dev/null 2>&1; then
        warn "brew-supplied git not on PATH — falling back to CLT."
        ensure_build_tools
    fi
    command -v git >/dev/null 2>&1 || \
        fail "git is not available; install Xcode CLT or Homebrew manually."
}
