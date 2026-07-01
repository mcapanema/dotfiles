# Homebrew shellenv — must be first
eval "$(/opt/homebrew/bin/brew shellenv zsh)"

# Re-add Cargo after macOS path_helper rebuilds PATH
case ":${PATH}:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) export PATH="$HOME/.cargo/bin:$PATH" ;;
esac