export LANG=en_US.UTF-8
export EDITOR=vim
export VISUAL=vim

# Avoid duplicates in PATH
typeset -U PATH

# Source Claude API config from chezmoi-managed template
if [ -f "$HOME/.local/share/chezmoi/claude/templates/.zshenv" ]; then
    source "$HOME/.local/share/chezmoi/claude/templates/.zshenv"
fi