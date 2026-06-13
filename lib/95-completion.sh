# 95-completion.sh — tab completion for the first argument.
# zsh needs compinit already loaded when mag.sh is sourced.

_mag_setup_completion() {
  local words
  words="j jump c code t tmux w web g grep n new cl clone m mv move ar archive rm remove pin tag desc s status p pull refresh u update v version cfg config setup ch changelog d doctor a aliases h help"

  if [ -n "${ZSH_VERSION:-}" ]; then
    if command -v compdef >/dev/null 2>&1; then
      _mag_complete() {
        if [ "$CURRENT" -eq 2 ]; then
          # shellcheck disable=SC2086
          compadd -- j jump c code t tmux w web g grep n new cl clone m mv move ar archive rm remove pin tag desc s status p pull refresh u update v version cfg config setup ch changelog d doctor a aliases h help
        fi
      }
      compdef _mag_complete mag
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    complete -W "$words" mag 2>/dev/null
  fi
}
