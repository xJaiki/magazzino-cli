# 50-nav.sh — jump, jump-back, editor, browser.

_mag_do_jump() {
  local rel="$1" root="$2"
  cd "$root/$rel" && _mag_record_recent "$root/$rel"
}

_mag_do_edit() {
  local rel="$1" root="$2" editor
  editor="$(_mag_editor)"

  if ! command -v "${editor%% *}" >/dev/null 2>&1; then
    _mag_err "Error: editor '$editor' not found in PATH. Set it with: mag config editor <cmd>"
    return 1
  fi

  cd "$root/$rel" || return 1
  _mag_record_recent "$root/$rel"
  eval "$editor ."
}

_mag_jump_back() {
  local last recent_file
  recent_file="$(_mag_recent_file)"
  last=$(sed -n '1p' "$recent_file" 2>/dev/null)

  # Already inside the most recent project: ping-pong to the previous one.
  if [ -n "$last" ]; then
    case "$PWD/" in
      "$last/"*)
        last=$(sed -n '2p' "$recent_file" 2>/dev/null)
        ;;
    esac
  fi

  if [ -z "$last" ]; then
    _mag_warn "No recent project to jump back to."
    return 1
  fi

  if [ ! -d "$last" ]; then
    _mag_warn "Last project '$last' no longer exists."
    _mag_recent_remove "$last"
    return 1
  fi

  cd "$last" && _mag_record_recent "$last"
}

# One tmux session per project: create it if missing, then attach/switch.
_mag_do_tmux() {
  local rel="$1" root="$2" sname

  if ! command -v tmux >/dev/null 2>&1; then
    _mag_err "Error: tmux not found in PATH."
    return 1
  fi

  # tmux session names cannot contain '.' or ':'
  sname=$(printf '%s' "$rel" | tr './:' '___')
  _mag_record_recent "$root/$rel"

  if ! tmux has-session -t "=$sname" 2>/dev/null; then
    tmux new-session -d -s "$sname" -c "$root/$rel" || return 1
  fi

  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "=$sname"
  else
    tmux attach-session -t "=$sname"
  fi
}

_mag_repo_web_url() {
  local ppath="$1" url remote

  url=$(git -C "$ppath" remote get-url origin 2>/dev/null)
  if [ -z "$url" ]; then
    # No 'origin': fall back to the first configured remote, if any.
    remote=$(git -C "$ppath" remote 2>/dev/null | head -1)
    if [ -n "$remote" ]; then
      url=$(git -C "$ppath" remote get-url "$remote" 2>/dev/null)
    fi
  fi
  [ -n "$url" ] || return 1

  case "$url" in
    git@*)
      # git@host:user/repo → https://host/user/repo (no ${var/pat/repl}:
      # bash and zsh disagree on backslashes in the replacement).
      url=${url#git@}
      url="https://${url%%:*}/${url#*:}"
      ;;
  esac
  printf '%s' "${url%.git}"
}

_mag_do_web() {
  local ppath="$1" url

  url=$(_mag_repo_web_url "$ppath")
  if [ -z "$url" ]; then
    _mag_err "Error: '${ppath/#$HOME/\~}' has no git remote — nothing to open in the browser."
    return 1
  fi

  _mag_info "→ $url"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1
  elif command -v open >/dev/null 2>&1; then
    open "$url"
  fi
}
