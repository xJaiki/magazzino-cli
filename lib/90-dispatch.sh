# 90-dispatch.sh — the mag() entry function.

mag() {
  local sel rel root

  # First-run wizard, except for commands that work without a configured root.
  case "${1:-}" in
    cfg|config|setup|v|version|d|doctor|a|aliases|u|update|ch|changelog|h|help) ;;
    *)
      if ! _mag_has_config && _mag_is_interactive_shell; then
        _mag_setup_or_update_config || return 1
      fi
      ;;
  esac

  case "${1:-}" in
    "")
      if _mag_is_interactive_shell && command -v fzf >/dev/null 2>&1; then
        _mag_dashboard
      else
        _mag_cmd_help
      fi
      ;;

    h|help)
      _mag_cmd_help
      ;;

    j|jump)
      sel=$(_mag_pick_project 'Jump to project: ' "${2:-}") || return 1
      [ -n "$sel" ] || return 0
      _mag_do_jump "${sel%%$'\t'*}" "${sel#*$'\t'}"
      ;;

    -)
      _mag_jump_back
      ;;

    t|tmux)
      sel=$(_mag_pick_project 'tmux session: ' "${2:-}") || return 1
      [ -n "$sel" ] || return 0
      _mag_do_tmux "${sel%%$'\t'*}" "${sel#*$'\t'}"
      ;;

    g|grep)
      shift
      _mag_cmd_grep "$@"
      ;;

    refresh)
      _mag_status_refresh && _mag_ok "✓ Status cache refreshed."
      ;;

    c|code)
      sel=$(_mag_pick_project "Open in $(_mag_editor): " "${2:-}") || return 1
      [ -n "$sel" ] || return 0
      _mag_do_edit "${sel%%$'\t'*}" "${sel#*$'\t'}"
      ;;

    w|web)
      if [ "${2:-}" = "." ]; then
        if git -C "$PWD" rev-parse --git-dir >/dev/null 2>&1; then
          _mag_do_web "$PWD"
        else
          _mag_err "Error: the current directory is not a git repository."
          return 1
        fi
        return 0
      fi
      sel=$(_mag_pick_project 'Open repo page: ' "${2:-}") || return 1
      [ -n "$sel" ] || return 0
      rel=${sel%%$'\t'*}
      root=${sel#*$'\t'}
      _mag_do_web "$root/$rel"
      ;;

    n|new)
      _mag_cmd_new "${2:-}" "${3:-}" "${4:-}"
      ;;

    cl|clone)
      _mag_cmd_clone "${2:-}" "${3:-}"
      ;;

    m|mv|move)
      _mag_cmd_mv "${2:-}" "${3:-}"
      ;;

    ar|archive)
      sel=$(_mag_pick_project 'Archive project: ' "${2:-}") || return 1
      [ -n "$sel" ] || return 0
      _mag_do_archive "${sel%%$'\t'*}" "${sel#*$'\t'}"
      ;;

    rm|remove)
      if ! _mag_is_interactive_shell; then
        _mag_err "Error: 'mag rm' requires an interactive shell for confirmation. Use 'mag archive' instead."
        return 1
      fi
      sel=$(_mag_pick_project 'Delete project: ' "${2:-}") || return 1
      [ -n "$sel" ] || return 0
      _mag_do_rm "${sel%%$'\t'*}" "${sel#*$'\t'}"
      ;;

    pin)
      sel=$(_mag_pick_project 'Pin/unpin project: ' "${2:-}") || return 1
      [ -n "$sel" ] || return 0
      rel=${sel%%$'\t'*}
      root=${sel#*$'\t'}
      _mag_pin_toggle "$root/$rel"
      ;;

    tag)
      _mag_cmd_tag "${2:-}" "${3:-}"
      ;;

    desc)
      shift
      _mag_cmd_desc "$@"
      ;;

    s|status)
      _mag_cmd_status "${2:-}"
      ;;

    p|pull)
      _mag_cmd_pull "${2:-}"
      ;;

    cfg|config|setup)
      _mag_cmd_config "${2:-}" "${3:-}" "${4:-}"
      ;;

    d|doctor)
      _mag_cmd_doctor
      ;;

    a|aliases)
      _mag_cmd_aliases
      ;;

    u|update)
      _mag_cmd_update
      ;;

    ch|changelog)
      _mag_cmd_changelog "${2:-}"
      ;;

    v|version)
      echo "Magazzino v$MAG_VERSION"
      ;;

    *)
      if command -v "mag_cmd_$1" >/dev/null 2>&1; then
        local _mag_plugin="mag_cmd_$1"
        shift
        "$_mag_plugin" "$@"
      else
        _mag_err "Unknown command: $1"
        echo -e "Run \033[1;32mmag help\033[0m for the command list."
        return 1
      fi
      ;;
  esac
}
