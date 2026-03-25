# fnm configuration
if command -v fnm &> /dev/null; then
  eval "$(fnm env --use-on-cd)"
fi

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
