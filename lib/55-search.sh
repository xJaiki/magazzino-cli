# 55-search.sh — full-text search across every project (mag grep).

_mag_cmd_grep() {
  local query="$*"
  local root results sel file rest line editor preview_cmd

  if [ -z "$query" ]; then
    _mag_err "Error: missing search query."
    echo -e "Usage: \033[1;32mmag grep <query>\033[0m"
    return 1
  fi

  _mag_require_fzf || return 1

  results=$(
    while IFS= read -r root; do
      [ -d "$root" ] || continue
      if command -v rg >/dev/null 2>&1; then
        rg --line-number --no-heading --smart-case \
          -g '!node_modules/' -g '!.git/' -g '!_archive/' -g '!dist/' \
          -e "$query" "$root" 2>/dev/null
      else
        grep -rn -i -E "$query" \
          --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=_archive \
          "$root" 2>/dev/null
      fi
    done <<< "$(_mag_roots)"
  )

  if [ -z "$results" ]; then
    _mag_warn "No matches for '$query'."
    return 1
  fi

  if command -v bat >/dev/null 2>&1; then
    preview_cmd='bat --color=always --style=numbers --highlight-line {2} {1} 2>/dev/null'
  else
    preview_cmd='awk -v c={2} "NR >= c - 8 && NR <= c + 20 { if (NR == c) printf \"> \"; else printf \"  \"; print }" {1} 2>/dev/null'
  fi

  sel=$(printf '%s\n' "$results" | _mag_fzf --delimiter=':' \
    --prompt='grep ❯ ' --preview "$preview_cmd" \
    --preview-window="right,50%,border-left,+{2}-8" --preview-label=' match ')
  [ -n "$sel" ] || return 0

  file=${sel%%:*}
  rest=${sel#*:}
  line=${rest%%:*}

  editor="$(_mag_editor)"
  if ! command -v "${editor%% *}" >/dev/null 2>&1; then
    _mag_err "Error: editor '$editor' not found in PATH. Set it with: mag config editor <cmd>"
    echo "Match: $file:$line"
    return 1
  fi

  case "${editor%% *}" in
    code|code-insiders|codium)
      eval "$editor -g $(printf '%q' "$file"):$line"
      ;;
    vim|nvim|vi|hx|helix|micro|nano)
      eval "$editor +$line $(printf '%q' "$file")"
      ;;
    *)
      eval "$editor $(printf '%q' "$file")"
      ;;
  esac
}
