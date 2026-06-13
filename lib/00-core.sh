# 00-core.sh — paths, output helpers, config, roots, templates, plugins.

_mag_data_dir() {
  printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/magazzino"
}

_mag_config_dir() {
  printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/magazzino"
}

_mag_config_file() {
  printf '%s' "$(_mag_config_dir)/config"
}

_mag_templates_file() {
  printf '%s' "$(_mag_config_dir)/templates"
}

_mag_plugins_dir() {
  printf '%s' "$(_mag_config_dir)/commands"
}

_mag_err()  { echo -e "\033[1;31m$*\033[0m" >&2; }
_mag_ok()   { echo -e "\033[1;32m$*\033[0m"; }
_mag_warn() { echo -e "\033[1;33m$*\033[0m"; }
_mag_info() { echo -e "\033[1;34m$*\033[0m"; }

_mag_is_interactive_shell() {
  case "$-" in
    *i*) [ -t 0 ] && [ -t 1 ] ;;
    *) return 1 ;;
  esac
}

_mag_confirm_action() {
  local prompt="$1"
  local answer

  if ! _mag_is_interactive_shell; then
    return 0
  fi

  printf '\033[1;33m%s [y/N]: \033[0m' "$prompt"
  IFS= read -r answer || return 1

  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

_mag_require_fzf() {
  if ! command -v fzf >/dev/null 2>&1; then
    _mag_err "Error: fzf not found in PATH. Run 'mag doctor'."
    return 1
  fi
}

# ---------------------------------------------------------------- config ---

_mag_load_config() {
  local config_file line value
  config_file="$(_mag_config_file)"

  [ -f "$config_file" ] || return 0

  # Parsed as plain key=value lines, never sourced: the config can never
  # execute code in the user's shell.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      MAGAZZINO_PROJECTS_DIR=*)
        value=${line#MAGAZZINO_PROJECTS_DIR=}
        # Legacy v1 format stored the value double-quoted with escapes.
        case "$value" in
          \"*\")
            value=${value#\"}
            value=${value%\"}
            value=${value//\\\"/\"}
            value=${value//\\\\/\\}
            ;;
        esac
        MAGAZZINO_PROJECTS_DIR="$value"
        ;;
      MAGAZZINO_ROOTS=*)
        MAGAZZINO_ROOTS=${line#MAGAZZINO_ROOTS=}
        ;;
      MAGAZZINO_EDITOR=*)
        MAGAZZINO_EDITOR=${line#MAGAZZINO_EDITOR=}
        ;;
    esac
  done < "$config_file"
}

_mag_has_config() {
  [ -f "$(_mag_config_file)" ]
}

_mag_write_config() {
  local config_file roots_line
  config_file="$(_mag_config_file)"

  mkdir -p "$(_mag_config_dir)" || return 1
  {
    printf 'MAGAZZINO_PROJECTS_DIR=%s\n' "$(_mag_primary_root)"
    roots_line=$(_mag_roots | paste -sd: -)
    case "$roots_line" in
      *:*) printf 'MAGAZZINO_ROOTS=%s\n' "$roots_line" ;;
    esac
    if [ -n "${MAGAZZINO_EDITOR:-}" ]; then
      printf 'MAGAZZINO_EDITOR=%s\n' "$MAGAZZINO_EDITOR"
    fi
  } > "$config_file"
}

# ----------------------------------------------------------------- roots ---

_mag_roots() {
  local roots="${MAGAZZINO_ROOTS:-${MAGAZZINO_PROJECTS_DIR:-$HOME/projects}}"
  printf '%s\n' "$roots" | tr ':' '\n' | grep -v '^$'
}

_mag_primary_root() {
  _mag_roots | head -1
}

_mag_root_count() {
  _mag_roots | grep -c .
}

# First root that contains the given relative path, if any.
_mag_resolve_root() {
  local rel="$1" root
  while IFS= read -r root; do
    if [ -d "$root/$rel" ]; then
      printf '%s' "$root"
      return 0
    fi
  done <<< "$(_mag_roots)"
  return 1
}

_mag_set_primary_root() {
  local ppath="$1" rest
  rest=$(_mag_roots | tail -n +2 | paste -sd: -)
  MAGAZZINO_PROJECTS_DIR="$ppath"
  if [ -n "$rest" ]; then
    MAGAZZINO_ROOTS="$ppath:$rest"
  else
    MAGAZZINO_ROOTS=""
  fi
}

_mag_editor() {
  printf '%s' "${MAGAZZINO_EDITOR:-code}"
}

# ---------------------------------------------------------------- wizard ---

_mag_prompt_projects_dir() {
  local current answer
  current="$(_mag_primary_root)"

  echo -e "\033[1;36m╭─ Magazzino setup wizard\033[0m"
  echo -e "\033[1;34m│ Choose the base directory for your projects.\033[0m"
  printf '\033[1;34m╰─ Projects directory [%s]: \033[0m' "$current"
  IFS= read -r answer || return 1

  if [ -z "$answer" ]; then
    answer="$current"
  fi

  answer=${answer/#\~/$HOME}
  answer=${answer%/}

  if [ -z "$answer" ]; then
    _mag_err "Error: invalid path."
    return 1
  fi

  if ! mkdir -p "$answer"; then
    _mag_err "Error: unable to create '$answer'."
    return 1
  fi

  _mag_set_primary_root "$answer"

  if ! _mag_write_config; then
    _mag_err "Error: unable to save the configuration."
    return 1
  fi

  _mag_ok "✓ Projects directory saved to '$answer'."
}

_mag_setup_or_update_config() {
  local requested="${1:-}" normalized

  if [ -n "$requested" ]; then
    normalized=${requested/#\~/$HOME}
    normalized=${normalized%/}

    if [ -z "$normalized" ]; then
      _mag_err "Error: invalid path."
      return 1
    fi

    if ! mkdir -p "$normalized"; then
      _mag_err "Error: unable to create '$normalized'."
      return 1
    fi

    _mag_set_primary_root "$normalized"

    if ! _mag_write_config; then
      _mag_err "Error: unable to save the configuration."
      return 1
    fi

    _mag_ok "✓ Configuration updated: '$normalized'."
    return 0
  fi

  _mag_prompt_projects_dir
}

# ------------------------------------------------------------- templates ---

_mag_template_lookup() {
  local name="$1" templates_file
  templates_file="$(_mag_templates_file)"

  [ -f "$templates_file" ] || return 1
  awk -v n="$name" 'index($0, n "=") == 1 { print substr($0, length(n) + 2); exit }' "$templates_file"
}

# --------------------------------------------------------------- plugins ---

# Drop a file in ~/.config/magazzino/commands/<name>.sh defining a function
# mag_cmd_<name>() and 'mag <name>' will call it.
_mag_load_plugins() {
  local plugin_dir f
  plugin_dir="$(_mag_plugins_dir)"

  [ -d "$plugin_dir" ] || return 0

  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt local_options null_glob 2>/dev/null
  fi

  for f in "$plugin_dir"/*.sh; do
    [ -f "$f" ] || continue
    . "$f"
  done
}

_mag_plugin_list() {
  local plugin_dir
  plugin_dir="$(_mag_plugins_dir)"
  [ -d "$plugin_dir" ] || return 0
  ls "$plugin_dir" 2>/dev/null | sed -n 's/\.sh$//p'
}
