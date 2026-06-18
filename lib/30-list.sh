# 30-list.sh — project listing.
# Output lines: "<colored display>\t<rel path>\t<root path>".
# Display is column-aligned: pin marker, [root] when multi-root, padded
# category (stable color), padded name, inline dim #tags.
# Ordering: pinned first, then by recency, then alphabetical.

_mag_project_list() {
  local root all nroots recent_file meta_file cache_file
  recent_file="$(_mag_recent_file)"
  meta_file="$(_mag_meta_file)"
  cache_file="$(_mag_status_cache_file)"

  _mag_status_refresh_async
  _mag_size_refresh_async

  all=$(
    while IFS= read -r root; do
      [ -d "$root" ] || continue
      (cd "$root" 2>/dev/null && find . -mindepth 2 -maxdepth 2 -type d 2>/dev/null \
        | grep -v '/\.' | sed 's|^\./||' | grep -v '^_archive/' | sort \
        | awk -v r="$root" '{ print $0 "\t" r }')
    done <<< "$(_mag_roots)"
  )
  [ -n "$all" ] || return 0

  nroots=$(_mag_root_count)

  # Single marker stream (a two-file awk would misfire on an empty file):
  #   C  category            (sorted unique, for stable colors)
  #   R  abs path            (recency order)
  #   P  abs path            (pinned)
  #   T  abs path \t tags    (tags to render inline)
  #   A  rel \t root         (all projects, alphabetical)
  {
    printf '%s\n' "$all" | cut -f1 | cut -d/ -f1 | sort -u | awk '{ print "C\t" $0 }'
    if [ -f "$recent_file" ]; then
      awk '$0 != "" { print "R\t" $0 }' "$recent_file"
    fi
    if [ -f "$meta_file" ]; then
      awk -F'\t' '$2 == "pin" { print "P\t" $1 }
                  $2 == "tags" { print "T\t" $1 "\t" $3 }' "$meta_file"
    fi
    if [ -f "$cache_file" ]; then
      awk -F'\t' '{ print "G\t" $0 }' "$cache_file"
    fi
    local size_cache
    size_cache="$(_mag_size_cache_file)"
    if [ -f "$size_cache" ]; then
      awk -F'\t' '{ print "Z\t" $0 }' "$size_cache"
    fi
    printf '%s\n' "$all" | awk '{ print "A\t" $0 }'
  } | awk -F'\t' -v multi="$nroots" '
    BEGIN { n = split("39 208 114 177 81 203 220 141 75 215 156 168", pal, " ") }
    $1 == "C" { color[$2] = pal[(ncat % n) + 1]; ncat++; next }
    $1 == "R" { if (!($2 in rrank)) rrank[$2] = ++nr; next }
    $1 == "P" { pinned[$2] = 1; next }
    $1 == "T" { tagsOf[$2] = $3; next }
    $1 == "G" { gdirty[$2] = $3; gahead[$2] = $4; next }
    $1 == "Z" { sizekb[$2] = $3; next }
    {
      na++
      arel[na] = $2; aroot[na] = $3; aid[na] = $3 "/" $2
    }
    END {
      # column widths for alignment
      for (i = 1; i <= na; i++) {
        split(arel[i], parts, "/")
        cl = length(parts[1]); if (cl > maxcat) maxcat = cl
        nl = length(arel[i]) - cl - 1; if (nl > maxname) maxname = nl
        nb = split(aroot[i], rp, "/")
        rl = length(rp[nb]); if (rl > maxroot) maxroot = rl
      }

      for (i = 1; i <= na; i++) if (aid[i] in pinned) emit(i, 1)
      for (r = 1; r <= nr; r++)
        for (i = 1; i <= na; i++)
          if (!(aid[i] in pinned) && (aid[i] in rrank) && rrank[aid[i]] == r) emit(i, 0)
      for (i = 1; i <= na; i++) if (!(aid[i] in pinned) && !(aid[i] in rrank)) emit(i, 0)
    }
    function emit(i, pin,   rel, root, cat, name, disp, parts, rp, nb, catp, namep, rootp, t, ta, m, j, tdisp, dot, kb, sdisp) {
      rel = arel[i]; root = aroot[i]
      split(rel, parts, "/"); cat = parts[1]
      name = substr(rel, length(cat) + 2)

      catp = sprintf("%-" maxcat "s", cat)
      namep = sprintf("%-" maxname "s", name)

      # status dot from the cache: yellow dirty, magenta unpushed,
      # green clean, dim dot for non-repos / unknown state
      dot = "\033[2m·\033[0m"
      if (aid[i] in gdirty) {
        if (gdirty[aid[i]] > 0) dot = "\033[1;33m●\033[0m"
        else if (gahead[aid[i]] > 0) dot = "\033[1;35m●\033[0m"
        else dot = "\033[1;32m●\033[0m"
      }

      disp = dot " " (pin ? "\033[1;33m★\033[0m " : "  ")
      if (multi > 1) {
        nb = split(root, rp, "/")
        rootp = sprintf("%-" maxroot "s", rp[nb])
        disp = disp "\033[2m[" rootp "]\033[0m "
      }
      disp = disp "\033[1;38;5;" color[cat] "m" catp "\033[0m  " namep

      t = tagsOf[aid[i]]
      if (t != "") {
        m = split(t, ta, ",")
        tdisp = ""
        for (j = 1; j <= m; j++) {
          gsub(/^ +| +$/, "", ta[j])
          if (ta[j] != "") tdisp = tdisp " \033[2m#" ta[j] "\033[0m"
        }
        disp = disp " " tdisp
      }

      if (aid[i] in sizekb) {
        kb = sizekb[aid[i]] + 0
        if (kb >= 1048576) sdisp = sprintf("%.1f GB", kb / 1048576)
        else if (kb >= 1024) sdisp = sprintf("%.1f MB", kb / 1024)
        else sdisp = kb " KB"
        disp = disp " \033[2m" sdisp "\033[0m"
      }

      print disp "\t" rel "\t" root
    }
  '
}
