export LANG=en_US.UTF-8
export EDITOR=nvim
export VISUAL=nvim
export Nvim_As_Edit="true"

# Avoid duplicates in PATH
typeset -U PATH

# Add ~/.local/bin to PATH so symlinks (vim, vi → nvim) take priority
# over any system vim that may live in /usr/bin or /usr/local/bin.
[ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH"

# Source Claude API config from chezmoi-managed template
# (chezmoi generates this file on first apply; skip if not present yet)
if [ -f "$HOME/.local/share/chezmoi/claude/templates/.zshenv" ]; then
    source "$HOME/.local/share/chezmoi/claude/templates/.zshenv"
fi