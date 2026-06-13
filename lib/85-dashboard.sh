# 85-dashboard.sh — the interactive dashboard ('mag' with no arguments).
# A loop around fzf with --expect keybindings: actions that change state
# return to the list (redrawn), navigation actions leave the dashboard.
# Tab cycles the views: all → pinned → dirty → recent → archive.

_mag_dash_pause() {
  printf '\033[2m[press enter to return to the dashboard]\033[0m '
  IFS= read -r
}

# Archived projects, same line format as the regular list.
_mag_archive_list() {
  local root
  while IFS= read -r root; do
    [ -d "$root/_archive" ] || continue
    (cd "$root" 2>/dev/null && find . -mindepth 3 -maxdepth 3 -type d -path './_archive/*' 2>/dev/null \
      | sed 's|^\./||' | sort \
      | awk -v r="$root" '{ print "\033[2m" $0 "\033[0m\t" $0 "\t" r }')
  done <<< "$(_mag_roots)"
}

_mag_dash_view_list() {
  local view="$1"
  case "$view" in
    pinned)
      _mag_project_list | _mag_filter_list_by_paths "$(awk -F'\t' '$2 == "pin" { print $1 }' "$(_mag_meta_file)" 2>/dev/null)"
      ;;
    dirty)
      [ -f "$(_mag_status_cache_file)" ] || _mag_status_refresh
      _mag_project_list | _mag_filter_list_by_paths "$(_mag_status_dirty_paths)"
      ;;
    recent)
      _mag_project_list | _mag_filter_list_by_paths "$(cat "$(_mag_recent_file)" 2>/dev/null)"
      ;;
    archive)
      _mag_archive_list
      ;;
    *)
      _mag_project_list
      ;;
  esac
}

_mag_dash_next_view() {
  case "$1" in
    all) printf 'pinned' ;;
    pinned) printf 'dirty' ;;
    dirty) printf 'recent' ;;
    recent) printf 'archive' ;;
    *) printf 'all' ;;
  esac
}

_mag_dashboard() {
  local list out key sel rel root header nproj label view=all

  _mag_require_fzf || { _mag_cmd_help; return 1; }

  printf '0' > "$(_mag_preview_mode_file)" 2>/dev/null

  # Two-line legend grouped by intent (fzf renders ANSI in --header).
  header=$(printf '\033[1;33m↵\033[0m jump    \033[1;33m^e\033[0m editor   \033[1;33m^t\033[0m tmux     \033[1;33m^w\033[0m web      \033[1;33mesc\033[0m quit\n\033[1;33m⇥\033[0m view    \033[1;33m^y\033[0m pin      \033[1;33m^a\033[0m archive  \033[1;33m^s\033[0m status   \033[1;33m^p\033[0m pull   \033[1;33m^o\033[0m preview')

  while true; do
    list=$(_mag_dash_view_list "$view")

    if [ -z "$list" ]; then
      if [ "$view" = "all" ]; then
        _mag_warn "No projects yet. Create one with 'mag n <category> <name>' or 'mag clone'."
        return 0
      fi
      # empty filtered view: skip ahead to the next one
      view=$(_mag_dash_next_view "$view")
      continue
    fi

    nproj=$(printf '%s\n' "$list" | grep -c .)
    label=" MAGAZZINO v$MAG_VERSION · ${view}: $nproj "

    out=$(printf '%s\n' "$list" | _mag_fzf --with-nth=1 \
      --prompt="magazzino/$view ❯ " --header="$header" \
      --border-label="$label" --border-label-pos=3 \
      --expect=tab,ctrl-e,ctrl-t,ctrl-w,ctrl-y,ctrl-a,ctrl-s,ctrl-p \
      --preview "$(_mag_preview_cmd)" --preview-window=right,45%,border-left \
      --preview-label=' preview ' --bind "$(_mag_preview_cycle_bind)") || break

    # With --expect the key is the first line and the selection the last;
    # validating the key keeps us safe against stray FZF_DEFAULT_OPTS.
    key=$(printf '%s\n' "$out" | sed -n '1p')
    sel=$(printf '%s\n' "$out" | sed -n '$p')
    case "$key" in
      ''|tab|ctrl-e|ctrl-t|ctrl-w|ctrl-y|ctrl-a|ctrl-s|ctrl-p) ;;
      *) key='' ;;
    esac

    if [ "$key" = "tab" ]; then
      view=$(_mag_dash_next_view "$view")
      continue
    fi

    [ -n "$sel" ] && [ "$sel" != "$key" ] || break

    rel=$(printf '%s' "$sel" | cut -f2)
    root=$(printf '%s' "$sel" | cut -f3)

    case "$key" in
      '')
        _mag_do_jump "$rel" "$root"
        break
        ;;
      ctrl-e)
        _mag_do_edit "$rel" "$root"
        break
        ;;
      ctrl-t)
        _mag_do_tmux "$rel" "$root" || _mag_dash_pause
        break
        ;;
      ctrl-w)
        _mag_do_web "$root/$rel" || _mag_dash_pause
        ;;
      ctrl-y)
        _mag_pin_toggle "$root/$rel" >/dev/null
        ;;
      ctrl-a)
        if [ "$view" = "archive" ]; then
          # in the archive view ^a restores instead of archiving
          _mag_cmd_mv "$rel" "${rel#_archive/}"
        else
          _mag_do_archive "$rel" "$root"
        fi
        _mag_dash_pause
        ;;
      ctrl-s)
        _mag_cmd_status ""
        _mag_dash_pause
        ;;
      ctrl-p)
        _mag_cmd_pull ""
        _mag_dash_pause
        ;;
    esac
  done
}
