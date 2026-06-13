# 60-lifecycle.sh — new, clone, mv, archive, rm.

_mag_cmd_new() {
  local cat="${1:-}" name="${2:-}" template="${3:-}"
  local root target_dir template_url=""

  if [ -z "$cat" ] || [ -z "$name" ]; then
    _mag_err "Error: missing parameters."
    echo -e "Usage: \033[1;32mmag n <category> <name> [template-name | template-url]\033[0m"
    return 1
  fi

  root=$(_mag_resolve_root "$cat") || root=$(_mag_primary_root)
  target_dir="$root/$cat/$name"

  if [ -n "$template" ]; then
    case "$template" in
      *://*|git@*|/*|.*|~*)
        template_url="$template"
        ;;
      *)
        template_url="$(_mag_template_lookup "$template")"
        if [ -z "$template_url" ]; then
          _mag_err "Error: unknown template '$template'. Register it with: mag config template $template <url>"
          return 1
        fi
        _mag_info "→ Using template '$template' → $template_url"
        ;;
    esac
  fi

  if [ -e "$target_dir" ]; then
    _mag_err "Error: '$target_dir' already exists. Choose a different name."
    return 1
  fi

  mkdir -p "$root/$cat" || return 1

  if [ -n "$template_url" ]; then
    if ! _mag_confirm_action "Template mode will reset .git history in the new project. Continue?"; then
      _mag_warn "Canceled by user."
      return 1
    fi

    _mag_info "→ Downloading template from $template_url..."
    if ! git clone "$template_url" "$target_dir" >/dev/null 2>&1; then
      rm -rf "$target_dir"
      _mag_err "Error: unable to clone the template."
      return 1
    fi

    rm -rf "$target_dir/.git"
    cd "$target_dir" || return 1
    git init >/dev/null 2>&1
    _mag_record_recent "$target_dir"
    _mag_ok "✓ Project '$name' cloned and cleaned successfully."
  else
    mkdir -p "$target_dir" || return 1
    cd "$target_dir" || return 1
    git init >/dev/null 2>&1
    _mag_record_recent "$target_dir"
    _mag_ok "✓ Empty project '$name' created under '$cat'."
  fi
}

_mag_cmd_clone() {
  local url="${1:-}" category="${2:-}"
  local root name target_dir sel

  if [ -z "$url" ]; then
    # With the gh CLI available, pick interactively from your own repos.
    if command -v gh >/dev/null 2>&1; then
      _mag_require_fzf || return 1
      url=$(gh repo list --limit 200 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null \
        | _mag_fzf --prompt='Clone from your GitHub: ')
      if [ -z "$url" ]; then
        _mag_warn "Canceled: no repository selected."
        return 1
      fi
    else
      _mag_err "Error: missing repository URL."
      echo -e "Usage: \033[1;32mmag clone <repo-url | user/repo> [category]\033[0m"
      echo -e "Tip: with the \033[1;33mgh\033[0m CLI installed, 'mag clone' alone picks from your GitHub repos."
      return 1
    fi
  fi

  # "user/repo" shorthand expands to GitHub; real URLs and paths pass through.
  case "$url" in
    *://*|git@*|/*|.*|~*) ;;
    */*)
      url="https://github.com/$url.git"
      _mag_info "→ Expanded to $url"
      ;;
  esac

  if [ -n "$category" ]; then
    category=${category%/}
    root=$(_mag_resolve_root "$category") || root=$(_mag_primary_root)
  else
    sel="$(_mag_pick_category)" || return 1
    if [ -z "$sel" ]; then
      _mag_warn "Canceled: no category selected."
      return 1
    fi
    category=${sel%%$'\t'*}
    root=${sel#*$'\t'}
  fi

  name="${url%/}"
  name="${name##*/}"
  name="${name%.git}"
  target_dir="$root/$category/$name"

  if [ -e "$target_dir" ]; then
    _mag_err "Error: '$target_dir' already exists."
    return 1
  fi

  mkdir -p "$root/$category" || return 1

  _mag_info "→ Cloning $url into $category/$name..."
  if ! git clone "$url" "$target_dir"; then
    _mag_err "Error: unable to clone the repository."
    return 1
  fi

  cd "$target_dir" || return 1
  _mag_record_recent "$target_dir"
  _mag_ok "✓ Cloned into '$category/$name' (history preserved)."
}

_mag_cmd_mv() {
  local src="${1:-}" dest="${2:-}"
  local root src_path name category target

  if [ -z "$src" ] || [ -z "$dest" ]; then
    _mag_err "Error: missing parameters."
    echo -e "Usage: \033[1;32mmag mv <category/name> <category[/new-name]>\033[0m"
    echo -e "       \033[1;32mmag mv <category> <new-category>\033[0m"
    return 1
  fi

  src=${src%/}
  dest=${dest%/}

  root=$(_mag_resolve_root "$src")
  if [ -z "$root" ]; then
    _mag_err "Error: '$src' not found in any root."
    return 1
  fi
  src_path="$root/$src"

  # Source with no slash is a whole category: rename it in one move.
  case "$src" in
    */*) ;;
    *)
      case "$dest" in
        */*)
          _mag_err "Error: the new category name cannot contain '/'."
          return 1
          ;;
      esac

      if [ -e "$root/$dest" ]; then
        _mag_err "Error: '$root/$dest' already exists."
        return 1
      fi

      mv "$src_path" "$root/$dest" || return 1
      _mag_recent_rename_prefix "$root/$src" "$root/$dest"
      _mag_meta_rename_prefix "$root/$src" "$root/$dest"
      _mag_ok "✓ Category '$src' renamed to '$dest'."
      return 0
      ;;
  esac

  name=${src##*/}

  case "$dest" in
    */*)
      category=${dest%/*}
      target="$root/$dest"
      ;;
    *)
      category=$dest
      target="$root/$dest/$name"
      ;;
  esac

  if [ -e "$target" ]; then
    _mag_err "Error: '$target' already exists."
    return 1
  fi

  mkdir -p "$root/$category" || return 1
  mv "$src_path" "$target" || return 1
  _mag_recent_rename "$src_path" "$target"
  _mag_meta_rename "$src_path" "$target"
  _mag_ok "✓ Moved '$src' → '${target#"$root"/}'."
}

_mag_do_archive() {
  local rel="$1" root="$2" target

  target="$root/_archive/$rel"

  if [ -e "$target" ]; then
    _mag_err "Error: '$target' already exists."
    return 1
  fi

  if ! _mag_confirm_action "Move '$rel' to '_archive/$rel'?"; then
    _mag_warn "Canceled by user."
    return 1
  fi

  mkdir -p "${target%/*}" || return 1
  mv "$root/$rel" "$target" || return 1
  _mag_recent_remove "$root/$rel"
  _mag_meta_rename "$root/$rel" "$target"
  _mag_ok "✓ Archived to '_archive/$rel'."
  _mag_info "Restore with: mag mv '_archive/$rel' '${rel%%/*}'"
}

_mag_do_rm() {
  local rel="$1" root="$2"

  case "$rel" in
    ''|/*|*..*)
      _mag_err "Error: refusing to delete suspicious path '$rel'."
      return 1
      ;;
  esac

  _mag_err "This will permanently delete '$root/$rel'."
  if ! _mag_confirm_action "Delete '$rel' forever?"; then
    _mag_warn "Canceled by user."
    return 1
  fi

  rm -rf "${root:?}/$rel" || return 1
  _mag_recent_remove "$root/$rel"
  _mag_meta_drop "$root/$rel"
  _mag_ok "✓ Project '$rel' deleted."
}
