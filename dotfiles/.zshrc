# ----------------------------------------------------------------------
# Shell behaviour
# ----------------------------------------------------------------------
set -o vi                       " Vi keybindings for the line editor
bindkey -v                      " Ensure vi keymap is active (coexists with set -o vi)
alias rm='nocorrect rm'         " Prevent zsh spell-checker from correcting 'rm'

# ----------------------------------------------------------------------
# Oh My Zsh configuration
# ----------------------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=(git)
source $ZSH/oh-my-zsh.sh

# zplug configuration
export ZPLUG_HOME=$(brew --prefix)/opt/zplug
source $ZPLUG_HOME/init.zsh

zplug "mafredri/zsh-async", use:async.zsh, from:github
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