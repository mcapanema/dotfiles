# Homebrew shellenv — must be first
eval "$(/opt/homebrew/bin/brew shellenv zsh)"

# rustup is installed via the keg-only brew formula — its shim binaries
# (rustc, cargo, rustfmt, clippy, ...) live at $(brew --prefix rustup)/bin.
# Add that dir to PATH.  macOS path_helper rebuilds PATH on login and would
# otherwise drop it, so it stays in .zprofile (login-shell PATH).
case ":${PATH}:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) [ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH" ;;
esac
case ":${PATH}:" in
  *":/opt/homebrew/opt/rustup/bin:"*) ;;
  *) [ -d "/opt/homebrew/opt/rustup/bin" ] && export PATH="/opt/homebrew/opt/rustup/bin:$PATH" ;;
esac