# 40-picker.sh — fzf wrapper, pickers, preview (tabbed) and helper scripts.

# Shared fzf styling. Callers append their own options (later ones win).
# Falls back to a plain style on fzf older than 0.53 (no --highlight-line).
_mag_fzf() {
  if [ -z "${_MAG_FZF_MODERN:-}" ]; then
    local v major minor
    v=$(fzf --version 2>/dev/null)
    major=${v%%.*}
    minor=${v#*.}
    minor=${minor%%[!0-9]*}
    if [ "${major:-0}" -gt 0 ] 2>/dev/null || [ "${minor:-0}" -ge 53 ] 2>/dev/null; then
      _MAG_FZF_MODERN=yes
    else
      _MAG_FZF_MODERN=no
    fi
  fi

  if [ "$_MAG_FZF_MODERN" = "yes" ]; then
    fzf --ansi --delimiter='\t' --layout=reverse --border=rounded \
      --highlight-line --info=inline-right --separator='─' --scrollbar \
      --pointer='▶' --prompt='❯ ' "$@"
  else
    fzf --ansi --delimiter='\t' --layout=reverse --prompt='> ' "$@"
  fi
}

_mag_preview_mode_file() {
  printf '%s' "$(_mag_data_dir)/preview-mode"
}

# Helper scripts run inside fzf/xargs subshells where our functions do not
# exist, so they are materialized in the data dir at load time.
_mag_ensure_helper_scripts() {
  local data_dir
  data_dir="$(_mag_data_dir)"
  mkdir -p "$data_dir" 2>/dev/null || return 0

  cat > "$data_dir/preview.sh" <<'PREVIEW'
#!/usr/bin/env bash
# magazzino picker preview: <rel> <root> <meta-file> <mode-file>
rel="$1" root="$2" meta="$3" modefile="${4:-}"
p="$root/$rel"

mode=$(cat "$modefile" 2>/dev/null)
mode=${mode:-0}

tabs=("info" "readme" "todo" "github")
bar=""
for i in 0 1 2 3; do
  if [ "$i" = "$mode" ]; then
    bar="$bar\033[1;36m[${tabs[$i]}]\033[0m "
  else
    bar="$bar\033[2m ${tabs[$i]} \033[0m "
  fi
done
echo -e "$bar\033[2m(^o)\033[0m"
echo

case "$mode" in
  1)
    readme=""
    for cand in "$p"/README.md "$p"/README.MD "$p"/readme.md "$p"/README "$p"/README.txt; do
      [ -f "$cand" ] && { readme="$cand"; break; }
    done
    if [ -z "$readme" ]; then
      echo "(no README found)"
    elif command -v glow >/dev/null 2>&1; then
      glow -s dark -w "${FZF_PREVIEW_COLUMNS:-80}" "$readme" 2>/dev/null
    elif command -v bat >/dev/null 2>&1; then
      bat --style=plain --color=always "$readme" 2>/dev/null
    else
      cat "$readme"
    fi
    ;;
  2)
    if command -v rg >/dev/null 2>&1; then
      rg -n --color=always -e 'TODO|FIXME|HACK' -g '!node_modules/' -g '!.git/' "$p" 2>/dev/null | head -60
    else
      grep -rn -E 'TODO|FIXME|HACK' --exclude-dir=node_modules --exclude-dir=.git "$p" 2>/dev/null | head -60
    fi
    [ -z "$(cd "$p" 2>/dev/null && (rg -l -e 'TODO|FIXME|HACK' -g '!node_modules/' . 2>/dev/null || grep -rl -E 'TODO|FIXME' --exclude-dir=node_modules . 2>/dev/null) | head -1)" ] && echo "(no TODO/FIXME found)"
    ;;
  3)
    if ! command -v gh >/dev/null 2>&1; then
      echo "(gh CLI not installed)"
    elif ! git -C "$p" remote get-url origin >/dev/null 2>&1; then
      echo "(no origin remote)"
    else
      echo -e "\033[1;34m── open PRs ──\033[0m"
      (cd "$p" && timeout 6 gh pr list --limit 5 2>/dev/null) || echo "(unavailable)"
      echo
      echo -e "\033[1;34m── recent CI runs ──\033[0m"
      (cd "$p" && timeout 6 gh run list --limit 3 2>/dev/null) || echo "(unavailable)"
    fi
    ;;
  *)
    branch=$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
      behind=0; ahead=0
      ab=$(git -C "$p" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
      [ -n "$ab" ] && read -r behind ahead <<< "$ab"
      dirty=$(git -C "$p" status --porcelain 2>/dev/null | grep -c .)

      line="\033[1;36m⎇ $branch\033[0m"
      [ "$ahead" -gt 0 ] && line="$line \033[1;35m↑$ahead\033[0m"
      [ "$behind" -gt 0 ] && line="$line \033[1;35m↓$behind\033[0m"
      if [ "$dirty" -gt 0 ]; then
        line="$line  \033[1;33m● $dirty modified\033[0m"
      else
        line="$line  \033[1;32m● clean\033[0m"
      fi
      echo -e "$line"
      echo
    fi

    if [ -f "$meta" ]; then
      desc=$(awk -F'\t' -v p="$p" '$1 == p && $2 == "desc" { print $3; exit }' "$meta")
      tags=$(awk -F'\t' -v p="$p" '$1 == p && $2 == "tags" { print $3; exit }' "$meta")
      [ -n "$desc" ] && printf '\033[3m%s\033[0m\n' "$desc"
      [ -n "$tags" ] && printf '\033[1;35m#\033[0m %s\n' "$tags"
      [ -n "$desc$tags" ] && echo
    fi

    echo -e "\033[1;34m── git ──\033[0m"
    git -C "$p" log --oneline --color=always -6 2>/dev/null || echo "(no commits yet)"
    echo
    echo -e "\033[1;34m── files ──\033[0m"
    ls -A1 "$p" 2>/dev/null
    ;;
esac
PREVIEW

  cat > "$data_dir/preview-cycle.sh" <<'CYCLE'
#!/usr/bin/env bash
f="$1"
m=$(cat "$f" 2>/dev/null)
m=$(( (${m:-0} + 1) % 4 ))
printf '%s' "$m" > "$f"
CYCLE

  cat > "$data_dir/pull-worker.sh" <<'WORKER'
#!/usr/bin/env bash
# magazzino parallel pull worker: <gitdir\troot> <counts-file> <nroots>
line="$1" counts="$2" multi="$3"
gitdir=${line%%$'\t'*}
root=${line#*$'\t'}
repo=$(dirname "$gitdir")
name=${repo#"$root"/}
if [ "$multi" -gt 1 ]; then
  name="[${root##*/}] $name"
fi

if ! git -C "$repo" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
  echo -e "  \033[1;33m−\033[0m $name (no upstream, skipped)"
  printf 'S' >> "$counts"
  exit 0
fi

before=$(git -C "$repo" rev-parse HEAD 2>/dev/null)
if git -C "$repo" pull --ff-only -q 2>/dev/null; then
  after=$(git -C "$repo" rev-parse HEAD 2>/dev/null)
  if [ "$before" = "$after" ]; then
    echo -e "  \033[2m·\033[0m $name already up to date"
    printf 'T' >> "$counts"
  else
    echo -e "  \033[1;32m✓\033[0m $name updated"
    printf 'U' >> "$counts"
  fi
else
  echo -e "  \033[1;31m✗\033[0m $name pull failed (dirty tree or diverged branch?)"
  printf 'F' >> "$counts"
fi
WORKER
}

_mag_preview_cmd() {
  printf 'bash %q {2} {3} %q %q' "$(_mag_data_dir)/preview.sh" "$(_mag_meta_file)" "$(_mag_preview_mode_file)"
}

_mag_preview_cycle_bind() {
  printf 'ctrl-o:execute-silent(bash %q %q)+refresh-preview' "$(_mag_data_dir)/preview-cycle.sh" "$(_mag_preview_mode_file)"
}

# Filters a list (stdin) keeping only entries whose abs path is in $1.
_mag_filter_list_by_paths() {
  local paths="$1"
  {
    printf '%s\n' "$paths" | awk 'NF { print "S\t" $0 }'
    awk '{ print "L\t" $0 }'
  } | awk -F'\t' '$1 == "S" { s[$2] = 1; next } { if (($4 "/" $3) in s) print substr($0, 3) }'
}

# Picks a project. Prints "<rel>\t<root>".
# query: substring on the rel path (direct hit when unique), or "@tag".
_mag_pick_project() {
  local prompt="$1" query="${2:-}"
  local list matches count tag

  list="$(_mag_project_list)"
  if [ -z "$list" ]; then
    _mag_warn "No projects found under: $(_mag_roots | paste -sd' ' -)" >&2
    return 1
  fi

  if [ -n "$query" ]; then
    case "$query" in
      @*)
        tag="${query#@}"
        matches=$(printf '%s\n' "$list" | _mag_filter_list_by_paths "$(_mag_meta_paths_with_tag "$tag")")
        if [ -z "$matches" ]; then
          _mag_err "Error: no project tagged '@$tag'." >&2
          return 1
        fi
        ;;
      *)
        matches=$(printf '%s\n' "$list" | awk -F'\t' -v q="$query" 'BEGIN { q = tolower(q) } index(tolower($2), q)')
        if [ -z "$matches" ]; then
          _mag_err "Error: no project matching '$query'." >&2
          return 1
        fi
        ;;
    esac

    count=$(printf '%s' "$matches" | grep -c .)
    if [ "$count" -eq 1 ]; then
      printf '%s\n' "$matches" | cut -f2,3
      return 0
    fi
    list="$matches"
  fi

  _mag_require_fzf || return 1

  printf '%s\n' "$list" | _mag_fzf --with-nth=1 --prompt="$prompt" \
    --preview "$(_mag_preview_cmd)" --preview-window=right,45%,border-left \
    --preview-label=' preview ' --bind "$(_mag_preview_cycle_bind)" | cut -f2,3
}

# Picks (or creates by typing) a category. Prints "<category>\t<root>".
_mag_pick_category() {
  local out sel query root list nroots

  _mag_require_fzf || return 1

  nroots=$(_mag_root_count)
  list=$(
    while IFS= read -r root; do
      [ -d "$root" ] || continue
      (cd "$root" 2>/dev/null && find . -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
        | sed 's|^\./||' | grep -v '^[._]' | sort \
        | awk -v r="$root" -v m="$nroots" '{
            if (m > 1) { nb = split(r, rp, "/"); print "[" rp[nb] "] " $0 "\t" $0 "\t" r }
            else print $0 "\t" $0 "\t" r
          }')
    done <<< "$(_mag_roots)"
  )

  out=$(printf '%s\n' "$list" | _mag_fzf --with-nth=1 \
    --prompt='Category (type a new name to create it): ' --print-query)
  query=$(printf '%s\n' "$out" | sed -n '1p')
  sel=$(printf '%s\n' "$out" | sed -n '2p')

  if [ -n "$sel" ]; then
    printf '%s\n' "$sel" | cut -f2,3
  elif [ -n "$query" ]; then
    printf '%s\t%s\n' "$query" "$(_mag_primary_root)"
  fi
}
