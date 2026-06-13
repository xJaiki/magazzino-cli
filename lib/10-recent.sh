# 10-recent.sh — recency history. Entries are absolute project paths.

_mag_recent_file() {
  printf '%s' "$(_mag_data_dir)/recent"
}

_mag_record_recent() {
  local entry="$1" data_dir recent_file
  data_dir="$(_mag_data_dir)"
  recent_file="$(_mag_recent_file)"

  mkdir -p "$data_dir" 2>/dev/null || return 0
  {
    printf '%s\n' "$entry"
    if [ -f "$recent_file" ]; then
      grep -Fxv -- "$entry" "$recent_file"
    fi
  } | head -50 > "$recent_file.tmp" && mv "$recent_file.tmp" "$recent_file"
}

_mag_recent_remove() {
  local entry="$1" recent_file
  recent_file="$(_mag_recent_file)"

  [ -f "$recent_file" ] || return 0
  grep -Fxv -- "$entry" "$recent_file" > "$recent_file.tmp"
  mv "$recent_file.tmp" "$recent_file"
}

_mag_recent_rename() {
  local old="$1" new="$2" recent_file
  recent_file="$(_mag_recent_file)"

  [ -f "$recent_file" ] || return 0
  awk -v old="$old" -v new="$new" '$0 == old { print new; next } { print }' "$recent_file" > "$recent_file.tmp" && mv "$recent_file.tmp" "$recent_file"
}

# Rewrites entries under a directory prefix (old and new WITHOUT trailing /).
_mag_recent_rename_prefix() {
  local old="$1" new="$2" recent_file
  recent_file="$(_mag_recent_file)"

  [ -f "$recent_file" ] || return 0
  awk -v old="$old/" -v new="$new/" 'index($0, old) == 1 { print new substr($0, length(old) + 1); next } { print }' "$recent_file" > "$recent_file.tmp" && mv "$recent_file.tmp" "$recent_file"
}
