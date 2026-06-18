# 25-cache.sh — git status cache for the list's status dots.
# Lines: <abs repo path>\t<dirty count>\t<ahead>\t<behind>
# Refreshed asynchronously (TTL 60s) so list rendering stays instant.

_mag_status_cache_file() {
  printf '%s' "$(_mag_data_dir)/status-cache"
}

_mag_status_refresh() {
  local cache tmp gitdir root repo dirty ab ahead behind
  cache="$(_mag_status_cache_file)"
  tmp="$cache.tmp.$$"

  mkdir -p "$(_mag_data_dir)" 2>/dev/null || return 0
  {
    while IFS=$'\t' read -r gitdir root; do
      [ -n "$gitdir" ] || continue
      repo=$(dirname "$gitdir")
      dirty=$(git -C "$repo" status --porcelain --untracked-files=all 2>/dev/null | grep -c .)
      ahead=0
      behind=0
      ab=$(git -C "$repo" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
      if [ -n "$ab" ]; then
        read -r behind ahead <<< "$ab"
      fi
      printf '%s\t%s\t%s\t%s\n' "$repo" "$dirty" "$ahead" "$behind"
    done <<< "$(_mag_repo_stream)"
  } > "$tmp" && mv "$tmp" "$cache"
}

# Fire-and-forget refresh, skipped while the cache is fresh (< 1 min).
_mag_status_refresh_async() {
  local cache
  cache="$(_mag_status_cache_file)"

  if [ -n "$(find "$cache" -mmin -1 2>/dev/null)" ]; then
    return 0
  fi
  ( _mag_status_refresh >/dev/null 2>&1 & )
}

_mag_size_cache_file() {
  printf '%s' "$(_mag_data_dir)/size-cache"
}

_mag_size_refresh() {
  local cache tmp root
  cache="$(_mag_size_cache_file)"
  tmp="$cache.tmp.$$"
  mkdir -p "$(_mag_data_dir)" 2>/dev/null || return 0
  {
    while IFS= read -r root; do
      [ -d "$root" ] || continue
      (cd "$root" 2>/dev/null && find . -mindepth 2 -maxdepth 2 -type d \
        | grep -v '/\.' | sed 's|^\./||' | grep -v '^_archive/' \
        | while IFS= read -r rel; do
            kb=$(du -sk "$root/$rel" 2>/dev/null | cut -f1)
            printf '%s\t%s\n' "$root/$rel" "${kb:-0}"
          done)
    done <<< "$(_mag_roots)"
  } > "$tmp" && mv "$tmp" "$cache"
}

# ponytail: TTL 5min for size — du is slow, stale-but-fast is fine
_mag_size_refresh_async() {
  local cache
  cache="$(_mag_size_cache_file)"
  if [ -n "$(find "$cache" -mmin -5 2>/dev/null)" ]; then
    return 0
  fi
  ( _mag_size_refresh >/dev/null 2>&1 & )
}

# Abs paths of repos with pending work (dirty or unpushed), per the cache.
_mag_status_dirty_paths() {
  local cache
  cache="$(_mag_status_cache_file)"
  [ -f "$cache" ] || return 0
  awk -F'\t' '$2 > 0 || $3 > 0 { print $1 }' "$cache"
}
