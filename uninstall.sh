#!/usr/bin/env bash
set -u

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/magazzino"
APP_DIR="$DATA_DIR/app"
SOURCE_LINE="source $APP_DIR/mag.sh"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/magazzino"
RC_FILES=("$HOME/.zshrc" "$HOME/.bashrc")
removed_from=()
KEEP_CONFIG=0

for arg in "$@"; do
    case "$arg" in
        --keep-config) KEEP_CONFIG=1 ;;
        *)
            echo -e "\e[1;31m==> Unknown option: $arg\e[0m"
            echo "Usage: ./uninstall.sh [--keep-config]"
            exit 1
            ;;
    esac
done

echo -e "\e[1;33m==> Uninstalling Magazzino...\e[0m"

if [ -d "$DATA_DIR" ]; then
    rm -rf "$DATA_DIR"
    echo -e "\e[1;32m==> Application and data files removed ($DATA_DIR).\e[0m"
fi

if [ -d "$CONFIG_DIR" ]; then
    remove_config=0
    if [ "$KEEP_CONFIG" -eq 0 ] && [ -t 0 ]; then
        printf '\e[1;33m==> Remove saved configuration (%s)? [y/N]: \e[0m' "$CONFIG_DIR"
        IFS= read -r answer || answer=""
        case "$answer" in
            y|Y|yes|YES|Yes) remove_config=1 ;;
        esac
    fi

    if [ "$remove_config" -eq 1 ]; then
        rm -rf "$CONFIG_DIR"
        echo -e "\e[1;32m==> Configuration folder removed.\e[0m"
    else
        echo -e "\e[1;34m==> Configuration kept at $CONFIG_DIR.\e[0m"
    fi
fi

for rc_file in "${RC_FILES[@]}"; do
    if [ -f "$rc_file" ] && grep -Fq "$SOURCE_LINE" "$rc_file"; then
        cp "$rc_file" "$rc_file.bak"
        awk -v source_line="$SOURCE_LINE" 'BEGIN { comment = "# Magazzino (Project Manager)" } $0 != comment && $0 != source_line { print }' "$rc_file" > "$rc_file.tmp"
        mv "$rc_file.tmp" "$rc_file"
        removed_from+=("$rc_file")
    fi
done

if [ "${#removed_from[@]}" -gt 0 ]; then
    echo -e "\e[1;32m==> Removed Magazzino lines from: ${removed_from[*]} (backups created with .bak).\e[0m"
else
    echo -e "\e[1;34m==> No Magazzino source lines found in the supported shell files.\e[0m"
fi

echo -e "\e[1;32m==> Uninstall complete. Restart the terminal for the changes to take effect.\e[0m"
