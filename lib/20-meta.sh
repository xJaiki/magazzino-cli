# 20-meta.sh — per-project metadata (pin, tags, desc).
# Flat TSV store: <absolute path>\t<field>\t<value>, one fact per line.

_mag_meta_file() {
  printf '%s' "$(_mag_data_dir)/meta"
}

_mag_meta_get() {
  local ppath="$1" field="$2" meta_file
  meta_file="$(_mag_meta_file)"

  [ -f "$meta_file" ] || return 0
  awk -F'\t' -v p="$ppath" -v f="$field" '$1 == p && $2 == f { print $3; exit }' "$meta_file"
}

_mag_meta_set() {
  local ppath="$1" field="$2" value="$3" meta_file
  meta_file="$(_mag_meta_file)"

  # Tabs and newlines would corrupt the store.
  value=$(printf '%s' "$value" | tr '\t\n' '  ')

  mkdir -p "$(_mag_data_dir)" || return 1
  touch "$meta_file"
  {
    awk -F'\t' -v p="$ppath" -v f="$field" '!($1 == p && $2 == f)' "$meta_file"
    printf '%s\t%s\t%s\n' "$ppath" "$field" "$value"
  } > "$meta_file.tmp" && mv "$meta_file.tmp" "$meta_file"
}

_mag_meta_del() {
  local ppath="$1" field="$2" meta_file
  meta_file="$(_mag_meta_file)"

  [ -f "$meta_file" ] || return 0
  awk -F'\t' -v p="$ppath" -v f="$field" '!($1 == p && $2 == f)' "$meta_file" > "$meta_file.tmp" && mv "$meta_file.tmp" "$meta_file"
}

_mag_meta_drop() {
  local ppath="$1" meta_file
  meta_file="$(_mag_meta_file)"

  [ -f "$meta_file" ] || return 0
  awk -F'\t' -v p="$ppath" '$1 != p' "$meta_file" > "$meta_file.tmp" && mv "$meta_file.tmp" "$meta_file"
}

_mag_meta_rename() {
  local old="$1" new="$2" meta_file
  meta_file="$(_mag_meta_file)"

  [ -f "$meta_file" ] || return 0
  awk -F'\t' -v OFS='\t' -v old="$old" -v new="$new" '$1 == old { $1 = new } { print }' "$meta_file" > "$meta_file.tmp" && mv "$meta_file.tmp" "$meta_file"
}

# Rewrites paths under a directory prefix (old and new WITHOUT trailing /).
_mag_meta_rename_prefix() {
  local old="$1" new="$2" meta_file
  meta_file="$(_mag_meta_file)"

  [ -f "$meta_file" ] || return 0
  awk -F'\t' -v OFS='\t' -v old="$old/" -v new="$new/" 'index($1, old) == 1 { $1 = new substr($1, length(old) + 1) } { print }' "$meta_file" > "$meta_file.tmp" && mv "$meta_file.tmp" "$meta_file"
}

_mag_pin_toggle() {
  local ppath="$1"
  if [ -n "$(_mag_meta_get "$ppath" pin)" ]; then
    _mag_meta_del "$ppath" pin
    _mag_warn "☆ Unpinned '$ppath'."
  else
    _mag_meta_set "$ppath" pin 1
    _mag_ok "★ Pinned '$ppath'."
  fi
}

_mag_meta_paths_with_tag() {
  local tag="$1" meta_file
  meta_file="$(_mag_meta_file)"

  [ -f "$meta_file" ] || return 0
  awk -F'\t' -v t="$tag" '$2 == "tags" {
    n = split($3, a, ",")
    for (i = 1; i <= n; i++) {
      gsub(/^ +| +$/, "", a[i])
      if (a[i] == t) { print $1; break }
    }
  }' "$meta_file"
}

_mag_meta_all_tags() {
  local meta_file
  meta_file="$(_mag_meta_file)"

  [ -f "$meta_file" ] || return 0
  awk -F'\t' '$2 == "tags" {
    n = split($3, a, ",")
    for (i = 1; i <= n; i++) {
      gsub(/^ +| +$/, "", a[i])
      if (a[i] != "") count[a[i]]++
    }
  }
  END { for (t in count) print t "\t" count[t] }' "$meta_file" | sort
}
