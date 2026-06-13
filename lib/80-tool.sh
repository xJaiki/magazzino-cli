# 80-tool.sh — config, tag/desc commands, doctor, update, changelog, help.

_mag_cmd_config() {
  local a="${1:-}" b="${2:-}" c="${3:-}"

  case "$a" in
    editor)
      if [ -z "$b" ]; then
        echo -e "Current editor: \033[1;32m$(_mag_editor)\033[0m"
        echo -e "Usage: \033[1;32mmag config editor <command>\033[0m"
        return 0
      fi
      MAGAZZINO_EDITOR="$b"
      _mag_write_config || { _mag_err "Error: unable to save the configuration."; return 1; }
      _mag_ok "✓ Editor set to '$b'."
      ;;

    template|templates)
      local templates_file
      templates_file="$(_mag_templates_file)"

      if [ -z "$b" ]; then
        if [ -s "$templates_file" ]; then
          echo -e "\033[1;36m╭─ MAGAZZINO TEMPLATES\033[0m"
          awk -F'=' '{ printf "  \033[1;33m%-16s\033[0m %s\n", $1, substr($0, length($1) + 2) }' "$templates_file"
        else
          _mag_warn "No templates registered."
        fi
        echo -e "Usage: \033[1;32mmag config template <name> <url>\033[0m (set), \033[1;32mmag config template <name> -d\033[0m (remove)"
        return 0
      fi

      if [ -z "$c" ]; then
        c="$(_mag_template_lookup "$b")"
        if [ -n "$c" ]; then
          echo -e "\033[1;33m$b\033[0m → $c"
        else
          _mag_err "Error: template '$b' not found."
          return 1
        fi
        return 0
      fi

      mkdir -p "$(_mag_config_dir)" || return 1
      touch "$templates_file"

      if [ "$c" = "-d" ]; then
        if [ -z "$(_mag_template_lookup "$b")" ]; then
          _mag_err "Error: template '$b' not found."
          return 1
        fi
        awk -v n="$b" 'index($0, n "=") != 1' "$templates_file" > "$templates_file.tmp" && mv "$templates_file.tmp" "$templates_file"
        _mag_ok "✓ Template '$b' removed."
        return 0
      fi

      { awk -v n="$b" 'index($0, n "=") != 1' "$templates_file"; printf '%s=%s\n' "$b" "$c"; } > "$templates_file.tmp" && mv "$templates_file.tmp" "$templates_file"
      _mag_ok "✓ Template '$b' → $c"
      ;;

    root|roots)
      local ppath roots_new
      case "$b" in
        ""|list)
          echo -e "\033[1;36m╭─ MAGAZZINO ROOTS\033[0m"
          _mag_roots | awk '{ if (NR == 1) print "  \033[1;33m" $0 "\033[0m \033[2m(primary)\033[0m"; else print "  " $0 }'
          echo -e "Usage: \033[1;32mmag config root add <path>\033[0m, \033[1;32mmag config root rm <path>\033[0m"
          ;;
        add)
          if [ -z "$c" ]; then
            _mag_err "Error: missing path."
            return 1
          fi
          ppath=${c/#\~/$HOME}
          ppath=${ppath%/}
          if ! mkdir -p "$ppath"; then
            _mag_err "Error: unable to create '$ppath'."
            return 1
          fi
          if _mag_roots | grep -Fxq -- "$ppath"; then
            _mag_warn "Root '$ppath' is already configured."
            return 0
          fi
          MAGAZZINO_ROOTS="$(_mag_roots | paste -sd: -):$ppath"
          _mag_write_config || return 1
          _mag_ok "✓ Root added: $ppath"
          ;;
        rm|remove)
          if [ -z "$c" ]; then
            _mag_err "Error: missing path."
            return 1
          fi
          ppath=${c/#\~/$HOME}
          ppath=${ppath%/}
          if ! _mag_roots | grep -Fxq -- "$ppath"; then
            _mag_err "Error: '$ppath' is not a configured root."
            return 1
          fi
          if [ "$(_mag_root_count)" -le 1 ]; then
            _mag_err "Error: cannot remove the last root."
            return 1
          fi
          roots_new=$(_mag_roots | grep -Fxv -- "$ppath" | paste -sd: -)
          MAGAZZINO_ROOTS="$roots_new"
          MAGAZZINO_PROJECTS_DIR="${roots_new%%:*}"
          _mag_write_config || return 1
          _mag_ok "✓ Root removed: $ppath (projects there are untouched)"
          ;;
        *)
          _mag_err "Error: unknown root action '$b'."
          return 1
          ;;
      esac
      ;;

    "")
      _mag_prompt_projects_dir
      ;;

    *)
      _mag_setup_or_update_config "$a"
      ;;
  esac
}

_mag_cmd_tag() {
  local query="${1:-}" tags="${2:-}" sel rel root ppath current

  if [ -z "$query" ]; then
    echo -e "\033[1;36m╭─ MAGAZZINO TAGS\033[0m"
    current=$(_mag_meta_all_tags)
    if [ -n "$current" ]; then
      printf '%s\n' "$current" | awk -F'\t' '{ printf "  \033[1;35m@%-14s\033[0m %s project(s)\n", $1, $2 }'
    else
      echo "  (no tags yet)"
    fi
    echo -e "Usage: \033[1;32mmag tag <name> <tag1,tag2>\033[0m (set), \033[1;32mmag tag <name>\033[0m (show), \033[1;32mmag tag <name> -d\033[0m (clear)"
    echo -e "Filter with: \033[1;32mmag j @tag\033[0m"
    return 0
  fi

  sel=$(_mag_pick_project 'Tag project: ' "$query") || return 1
  [ -n "$sel" ] || return 0
  rel=${sel%%$'\t'*}
  root=${sel#*$'\t'}
  ppath="$root/$rel"

  if [ -z "$tags" ]; then
    current="$(_mag_meta_get "$ppath" tags)"
    echo -e "\033[1;33m$rel\033[0m: ${current:-(no tags)}"
    return 0
  fi

  if [ "$tags" = "-d" ]; then
    _mag_meta_del "$ppath" tags
    _mag_ok "✓ Tags cleared on '$rel'."
    return 0
  fi

  _mag_meta_set "$ppath" tags "$tags"
  _mag_ok "✓ Tagged '$rel' with: $tags"
}

_mag_cmd_desc() {
  local query="${1:-}"
  [ $# -gt 0 ] && shift
  local text="$*" sel rel root ppath current

  if [ -z "$query" ]; then
    _mag_err "Error: missing project name."
    echo -e "Usage: \033[1;32mmag desc <name> [text | -d]\033[0m"
    return 1
  fi

  sel=$(_mag_pick_project 'Describe project: ' "$query") || return 1
  [ -n "$sel" ] || return 0
  rel=${sel%%$'\t'*}
  root=${sel#*$'\t'}
  ppath="$root/$rel"

  if [ -z "$text" ]; then
    current="$(_mag_meta_get "$ppath" desc)"
    echo -e "\033[1;33m$rel\033[0m: ${current:-(no description)}"
    return 0
  fi

  if [ "$text" = "-d" ]; then
    _mag_meta_del "$ppath" desc
    _mag_ok "✓ Description cleared on '$rel'."
    return 0
  fi

  _mag_meta_set "$ppath" desc "$text"
  _mag_ok "✓ Description set on '$rel'."
}

_mag_cmd_doctor() {
  local required_missing=0 optional_missing=0
  local cmd config_file editor root stray_count plugins
  local optline opt_cmd opt_desc cache_file cache_age

  config_file="$(_mag_config_file)"
  editor="$(_mag_editor)"

  echo -e "\033[1;36m╭─ MAGAZZINO DOCTOR v$MAG_VERSION\033[0m"
  echo -e "\033[1;34m│ Checking dependencies and local setup\033[0m"

  for cmd in git fzf; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo -e "\033[1;32m├─ ✓\033[0m $cmd found"
    else
      required_missing=$((required_missing + 1))
      echo -e "\033[1;31m├─ ✗\033[0m $cmd missing"
    fi
  done

  if command -v "${editor%% *}" >/dev/null 2>&1; then
    echo -e "\033[1;32m├─ ✓\033[0m editor '$editor' found (used by 'mag c')"
  else
    optional_missing=$((optional_missing + 1))
    echo -e "\033[1;33m├─ !\033[0m editor '$editor' missing (set one with 'mag config editor <cmd>')"
  fi

  for optline in \
    "gh:interactive 'mag clone' and the github preview tab" \
    "tmux:project sessions ('mag t', ^t in the dashboard)" \
    "rg:faster 'mag grep' and the todo preview tab" \
    "bat:highlighted previews (grep matches, README fallback)" \
    "glow:rendered README in the preview tab" \
    "xdg-open:opening repo pages in the browser ('mag web')"; do
    opt_cmd=${optline%%:*}
    opt_desc=${optline#*:}
    if command -v "$opt_cmd" >/dev/null 2>&1; then
      echo -e "\033[1;32m├─ ✓\033[0m $opt_cmd found \033[2m($opt_desc)\033[0m"
    else
      optional_missing=$((optional_missing + 1))
      echo -e "\033[1;33m├─ !\033[0m $opt_cmd missing \033[2m($opt_desc)\033[0m"
    fi
  done

  if [ -f "$_MAG_HOME/mag.sh" ] && [ -d "$_MAG_HOME/lib" ]; then
    echo -e "\033[1;32m├─ ✓\033[0m loaded from: $_MAG_HOME"
  fi

  if [ -f "$(_mag_data_dir)/source-repo" ]; then
    echo -e "\033[1;32m├─ ✓\033[0m update source: $(cat "$(_mag_data_dir)/source-repo")"
  else
    echo -e "\033[1;33m├─ !\033[0m update source unknown: 'mag update' needs a reinstall"
  fi

  if [ -f "$config_file" ]; then
    echo -e "\033[1;32m├─ ✓\033[0m config file found: $config_file"
  else
    echo -e "\033[1;33m├─ !\033[0m config file missing: run 'mag config'"
  fi

  cache_file="$(_mag_status_cache_file)"
  if [ -f "$cache_file" ]; then
    cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
    echo -e "\033[1;32m├─ ✓\033[0m status cache updated ${cache_age}s ago"
  else
    echo -e "\033[1;33m├─ !\033[0m status cache missing: run 'mag refresh' (or open the dashboard once)"
  fi

  while IFS= read -r root; do
    if [ -d "$root" ]; then
      echo -e "\033[1;32m├─ ✓\033[0m root exists: $root"
      stray_count=$(find "$root" -mindepth 2 -maxdepth 2 -name ".git" 2>/dev/null | grep -c .)
      if [ "$stray_count" -gt 0 ]; then
        echo -e "\033[1;33m├─ !\033[0m $stray_count repo(s) sit directly in '$root' and are invisible to mag"
        echo -e "\033[1;34m│\033[0m   expected layout is <category>/<project>: fix with 'mag mv <name> <category>'"
      fi
    else
      echo -e "\033[1;33m├─ !\033[0m root missing: $root"
    fi
  done <<< "$(_mag_roots)"

  plugins=$(_mag_plugin_list | paste -sd' ' -)
  if [ -n "$plugins" ]; then
    echo -e "\033[1;32m├─ ✓\033[0m plugins loaded: $plugins"
  fi

  if [ "$required_missing" -eq 0 ]; then
    echo -e "\033[1;32m╰─ Health check passed\033[0m"
  else
    echo -e "\033[1;31m╰─ Health check failed: $required_missing required dependency missing\033[0m"
  fi

  if [ "$optional_missing" -gt 0 ]; then
    echo -e "\033[1;34mNote:\033[0m missing optional tools only disable the features listed next to them."
  fi
}

_mag_cmd_update() {
  local source_file src old_version
  source_file="$(_mag_data_dir)/source-repo"

  src=""
  if [ -f "$source_file" ]; then
    src="$(cat "$source_file")"
  fi

  if [ -z "$src" ] || [ ! -f "$src/mag.sh" ]; then
    _mag_err "Error: update source unknown. Run ./install.sh from the repo once."
    return 1
  fi

  if git -C "$src" rev-parse --git-dir >/dev/null 2>&1 && [ -n "$(git -C "$src" remote 2>/dev/null)" ]; then
    _mag_info "→ Pulling latest changes from $src..."
    if ! git -C "$src" pull --ff-only; then
      _mag_err "Error: git pull failed. Resolve it in '$src' and retry."
      return 1
    fi
  else
    _mag_warn "No git remote configured: installing the local copy."
  fi

  if [ "$src" != "$_MAG_HOME" ]; then
    cp "$src/mag.sh" "$_MAG_HOME/mag.sh" || return 1
    rm -rf "$_MAG_HOME/lib"
    cp -r "$src/lib" "$_MAG_HOME/lib" || return 1
    if [ -d "$src/changelogs" ]; then
      rm -rf "$_MAG_HOME/changelogs"
      cp -r "$src/changelogs" "$_MAG_HOME/changelogs"
    fi
  fi

  old_version="$MAG_VERSION"
  . "$_MAG_HOME/mag.sh"

  if [ "$old_version" = "$MAG_VERSION" ]; then
    _mag_ok "✓ Already up to date (v$MAG_VERSION)."
  else
    _mag_ok "✓ Updated v$old_version → v$MAG_VERSION (reloaded in this shell)."
    _mag_info "See what changed with: mag changelog"
  fi
}

_mag_cmd_changelog() {
  local arg="${1:-}" cl_dir file cl_version

  cl_dir="$_MAG_HOME/changelogs"

  if [ ! -d "$cl_dir" ]; then
    _mag_err "Error: changelogs not found. Reinstall with ./install.sh or run 'mag update'."
    return 1
  fi

  case "$arg" in
    list|ls|all)
      echo -e "\033[1;36m╭─ MAGAZZINO CHANGELOGS\033[0m"
      ls "$cl_dir" 2>/dev/null | sed -n 's/^v\(.*\)\.md$/  v\1/p' | sort -V
      echo -e "Show one with: \033[1;32mmag changelog <version>\033[0m"
      return 0
      ;;
    "")
      cl_version="$MAG_VERSION"
      ;;
    *)
      cl_version="${arg#v}"
      ;;
  esac

  file="$cl_dir/v$cl_version.md"
  if [ ! -f "$file" ]; then
    _mag_err "Error: no changelog for v$cl_version. Available:"
    ls "$cl_dir" 2>/dev/null | sed -n 's/^v\(.*\)\.md$/  v\1/p' | sort -V
    return 1
  fi

  echo ""
  cat "$file"
  echo ""
}

_mag_cmd_aliases() {
  echo -e "\033[1;36m╭─ MAGAZZINO ALIASES\033[0m"
  echo -e "\033[1;33m├─ j\033[0m <-> jump"
  echo -e "\033[1;33m├─ c\033[0m <-> code"
  echo -e "\033[1;33m├─ w\033[0m <-> web"
  echo -e "\033[1;33m├─ n\033[0m <-> new"
  echo -e "\033[1;33m├─ cl\033[0m <-> clone"
  echo -e "\033[1;33m├─ m\033[0m <-> mv <-> move"
  echo -e "\033[1;33m├─ ar\033[0m <-> archive"
  echo -e "\033[1;33m├─ rm\033[0m <-> remove"
  echo -e "\033[1;33m├─ t\033[0m <-> tmux"
  echo -e "\033[1;33m├─ g\033[0m <-> grep"
  echo -e "\033[1;33m├─ s\033[0m <-> status"
  echo -e "\033[1;33m├─ p\033[0m <-> pull"
  echo -e "\033[1;33m├─ ch\033[0m <-> changelog"
  echo -e "\033[1;33m├─ u\033[0m <-> update"
  echo -e "\033[1;33m├─ v\033[0m <-> version"
  echo -e "\033[1;33m├─ cfg\033[0m <-> config <-> setup"
  echo -e "\033[1;33m├─ d\033[0m <-> doctor"
  echo -e "\033[1;33m├─ h\033[0m <-> help"
  echo -e "\033[1;33m╰─ a\033[0m <-> aliases"
}

_mag_cmd_help() {
  echo ""
  echo -e "\033[1;36m╭─ MAGAZZINO v$MAG_VERSION\033[0m \033[1;34m─ shell-native project manager\033[0m"
  echo -e "\033[1;36m│\033[0m  \033[2mroots:\033[0m $(_mag_roots | paste -sd' ' -)   \033[2meditor:\033[0m $(_mag_editor)"
  echo -e "\033[1;36m│\033[0m"
  echo -e "\033[1;36m│\033[0m  \033[1;37mDashboard\033[0m"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag\033[0m                         Dashboard: ⇥ cycles views (all/pinned/dirty/recent/archive)"
  echo -e "\033[1;36m│\033[0m"
  echo -e "\033[1;36m│\033[0m  \033[1;37mNavigate\033[0m"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag j [name|@tag]\033[0m           Jump to a project (direct if unique match)"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag -\033[0m                       Jump back to the last used project"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag c [name]\033[0m                Open a project in your editor"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag t [name]\033[0m                Open/switch to the project tmux session"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag web [name|.]\033[0m            Open the repo page in the browser (.: current)"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag grep <query>\033[0m            Search text across every project, open in editor"
  echo -e "\033[1;36m│\033[0m"
  echo -e "\033[1;36m│\033[0m  \033[1;37mManage\033[0m"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag n <cat> <name> [tpl]\033[0m    New project (template name or URL)"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag clone [url] [cat]\033[0m       Clone a repo (user/repo shorthand; no url + gh: pick)"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag mv <src> <dest>\033[0m         Move/rename a project or a category"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag archive [name]\033[0m          Move a project to _archive"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag rm [name]\033[0m               Delete a project (asks confirmation)"
  echo -e "\033[1;36m│\033[0m"
  echo -e "\033[1;36m│\033[0m  \033[1;37mMeta\033[0m"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag pin [name]\033[0m              Pin/unpin a project to the top of the list"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag tag [name] [tags|-d]\033[0m    Tag a project; filter with 'mag j @tag'"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag desc <name> [text|-d]\033[0m   Set a one-line description (shown in preview)"
  echo -e "\033[1;36m│\033[0m"
  echo -e "\033[1;36m│\033[0m  \033[1;37mSync\033[0m"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag s [j|f]\033[0m                 Pending changes (j: jump into one, f: fetch first)"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag pull [cat]\033[0m              Pull all repos in parallel (fast-forward only)"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag refresh\033[0m                 Refresh the status-dot cache now"
  echo -e "\033[1;36m│\033[0m"
  echo -e "\033[1;36m│\033[0m  \033[1;37mTool\033[0m"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag config [path]\033[0m           Set the primary projects root"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag config root ...\033[0m         Manage multiple project roots"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag config editor <cmd>\033[0m     Set the editor used by 'mag c'"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag config template ...\033[0m     Manage named templates for 'mag n'"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag update\033[0m                  Self-update from the source repo"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag changelog [v|list]\033[0m      Show release notes"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag doctor\033[0m                  Run setup health checks"
  echo -e "\033[1;36m│\033[0m    \033[1;33mmag version\033[0m \033[1;33mmag aliases\033[0m     Version / alias list"
  echo -e "\033[1;36m╰─\033[0m"
  echo ""
}
