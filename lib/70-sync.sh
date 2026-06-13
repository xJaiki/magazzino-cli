# 70-sync.sh — status (with fetch and interactive jump) and parallel pull.

# Lists ".git" markers (dir or file: worktrees use a file) at the fixed
# <category>/<project> depth for every root. Output: "<gitdir>\t<root>".
_mag_repo_stream() {
  local root
  while IFS= read -r root; do
    [ -d "$root" ] || continue
    find "$root" -mindepth 3 -maxdepth 3 -name ".git" 2>/dev/null | awk -v r="$root" '{ print $0 "\t" r }'
  done <<< "$(_mag_roots)"
}

_mag_cmd_status() {
  local mode="${1:-}"
  local dirty_count=0 scanned_count=0
  local total_staged=0 total_unstaged=0 total_untracked=0 total_ahead=0
  local entries="" nroots
  local gitdir root repo rel disp porcelain counts staged unstaged untracked
  local ahead behind ab extra pick

  nroots=$(_mag_root_count)

  while IFS=$'\t' read -r gitdir root; do
    [ -n "$gitdir" ] || continue
    scanned_count=$((scanned_count + 1))
    repo=$(dirname "$gitdir")
    rel=${repo#"$root"/}

    if [ "$mode" = "f" ] || [ "$mode" = "fetch" ]; then
      git -C "$repo" fetch -q 2>/dev/null
    fi

    porcelain=$(git -C "$repo" status --porcelain --untracked-files=all 2>/dev/null)

    ahead=0
    behind=0
    ab=$(git -C "$repo" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
    if [ -n "$ab" ]; then
      read -r behind ahead <<< "$ab"
    fi

    if [ -n "$porcelain" ] || [ "$ahead" -gt 0 ]; then
      dirty_count=$((dirty_count + 1))

      counts=$(printf '%s\n' "$porcelain" | awk 'BEGIN { s=0; u=0; t=0 } /^\?\?/ { t++; next } /^$/ { next } { x=substr($0,1,1); y=substr($0,2,1); if (x != " " && x != "?") s++; if (y != " " && y != "?") u++; } END { printf "%d %d %d", s, u, t }')
      read -r staged unstaged untracked <<< "$counts"

      total_staged=$((total_staged + staged))
      total_unstaged=$((total_unstaged + unstaged))
      total_untracked=$((total_untracked + untracked))
      total_ahead=$((total_ahead + ahead))

      extra=""
      if [ "$ahead" -gt 0 ]; then
        extra=" \033[1;35m↑$ahead\033[0m"
      fi
      if [ "$behind" -gt 0 ]; then
        extra="$extra \033[1;35m↓$behind\033[0m"
      fi

      disp="$rel"
      if [ "$nroots" -gt 1 ]; then
        disp="\033[2m[${root##*/}]\033[0m $rel"
      fi

      entries="$entries  \033[1;33m•\033[0m $disp \033[1;34m(staged:$staged unstaged:$unstaged untracked:$untracked)\033[0m$extra\t$rel\t$root\n"
    fi
  done <<< "$(_mag_repo_stream)"

  if [ "$mode" = "j" ] || [ "$mode" = "jump" ]; then
    if [ "$dirty_count" -eq 0 ]; then
      _mag_ok "No repositories with pending changes."
      return 0
    fi

    _mag_require_fzf || return 1

    pick=$(printf '%b' "$entries" | _mag_fzf --with-nth=1 --prompt='Jump to dirty repo: ' | cut -f2,3)
    if [ -n "$pick" ]; then
      _mag_do_jump "${pick%%$'\t'*}" "${pick#*$'\t'}"
    fi
    return 0
  fi

  echo -e "\033[1;34m🔍 Uncommitted or unpushed Git changes\033[0m\n"

  if [ "$dirty_count" -eq 0 ]; then
    echo -e "  \033[1;32mNo repositories with pending changes.\033[0m"
  else
    printf '%b' "$entries" | cut -f1
    echo ""
    echo -e "\033[1;36mSummary:\033[0m scanned:$scanned_count dirty:$dirty_count staged:$total_staged unstaged:$total_unstaged untracked:$total_untracked unpushed:$total_ahead"
    echo -e "\033[1;34mTip:\033[0m 'mag s j' jumps into one of these repos."
  fi
  echo ""
}

_mag_cmd_pull() {
  local category="${1:-}" stream label root nroots worker counts_file
  local scanned pulled uptodate skipped failed c

  nroots=$(_mag_root_count)
  worker="$(_mag_data_dir)/pull-worker.sh"

  if [ -n "$category" ]; then
    category=${category%/}
    root=$(_mag_resolve_root "$category")
    if [ -z "$root" ]; then
      _mag_err "Error: category '$category' not found in any root."
      return 1
    fi
    stream=$(find "$root/$category" -mindepth 2 -maxdepth 2 -name ".git" 2>/dev/null | awk -v r="$root" '{ print $0 "\t" r }')
    label="$category"
  else
    stream=$(_mag_repo_stream)
    label="all projects"
  fi

  scanned=$(printf '%s' "$stream" | grep -c .)
  if [ "$scanned" -eq 0 ]; then
    echo -e "  \033[1;33mNo git repositories found.\033[0m"
    return 0
  fi

  echo -e "\033[1;34m⇣ Pulling $label ($scanned repos, 4 in parallel)\033[0m\n"

  counts_file=$(mktemp)
  # Workers print their own result line as they finish (that is the
  # progress) and append one status char to the counts file.
  printf '%s\n' "$stream" | xargs -d '\n' -r -P 4 -I{} bash "$worker" {} "$counts_file" "$nroots"

  c=$(cat "$counts_file" 2>/dev/null)
  rm -f "$counts_file"
  pulled=$(printf '%s' "$c" | tr -cd 'U' | wc -c)
  uptodate=$(printf '%s' "$c" | tr -cd 'T' | wc -c)
  skipped=$(printf '%s' "$c" | tr -cd 'S' | wc -c)
  failed=$(printf '%s' "$c" | tr -cd 'F' | wc -c)

  echo ""
  echo -e "\033[1;36mSummary:\033[0m scanned:$scanned updated:$pulled up-to-date:$uptodate skipped:$skipped failed:$failed"

  # repo states changed: refresh the status-dot cache right away
  ( _mag_status_refresh >/dev/null 2>&1 & )

  if [ "$failed" -gt 0 ]; then
    return 1
  fi
}
