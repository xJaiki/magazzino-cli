#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DATA_DIR="$DATA_HOME/magazzino"
APP_DIR="$DATA_DIR/app"
LEGACY_V2_DIR="$DATA_HOME/magazzino2"
SOURCE_LINE="source $APP_DIR/mag.sh"
LEGACY_V1_LINE="source $DATA_DIR/mag.sh"
LEGACY_V2_LINE="source $LEGACY_V2_DIR/app/mag.sh"
PRIMARY_RC="$HOME/.zshrc"
SECONDARY_RC="$HOME/.bashrc"

case "$(basename "${SHELL:-zsh}")" in
    bash)
        PRIMARY_RC="$HOME/.bashrc"
        SECONDARY_RC="$HOME/.zshrc"
        ;;
esac

RC_FILES=("$PRIMARY_RC")
if [ -f "$SECONDARY_RC" ]; then
    RC_FILES+=("$SECONDARY_RC")
fi

updated_rc_files=()
legacy_removed_from=()

if [ ! -f "$SCRIPT_DIR/mag.sh" ] || [ ! -d "$SCRIPT_DIR/lib" ]; then
    echo -e "\e[1;31m==> Error: mag.sh and lib/ not found next to install.sh.\e[0m"
    exit 1
fi

VERSION="$(grep -m1 '^MAG_VERSION=' "$SCRIPT_DIR/mag.sh" | cut -d'"' -f2)"

echo -e "\e[1;36m==> Installing Magazzino v${VERSION:-unknown}...\e[0m"

echo -e "\e[1;34m==> Step 1/4: Checking dependencies...\e[0m"

missing_required=0
for cmd in git fzf; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e "\e[1;32m    ✓ $cmd found\e[0m"
    else
        missing_required=$((missing_required + 1))
        echo -e "\e[1;31m    ✗ $cmd missing\e[0m"
    fi
done

if [ "$missing_required" -gt 0 ]; then
    echo -e "\e[1;33m==> Warning: install the missing dependencies above, then run 'mag doctor'.\e[0m"
fi

echo -e "\e[1;34m==> Step 2/4: Migrating previous installations...\e[0m"

# Legacy v1 kept its app files at the root of the data dir.
if [ -f "$DATA_DIR/mag.sh" ]; then
    rm -f "$DATA_DIR/mag.sh" "$DATA_DIR/source-repo"
    rm -rf "$DATA_DIR/changelogs"
    echo -e "\e[1;33m    legacy v1 app files removed from $DATA_DIR\e[0m"
fi

# Legacy v1 recency used relative paths; this version uses absolute ones.
if [ -f "$DATA_DIR/recent" ] && grep -q '^[^/]' "$DATA_DIR/recent" 2>/dev/null; then
    rm -f "$DATA_DIR/recent"
    echo -e "\e[1;33m    legacy v1 recency file removed (incompatible format)\e[0m"
fi

# The 2.0 preview lived in its own dir: carry its data over, then drop it.
if [ -d "$LEGACY_V2_DIR" ]; then
    mkdir -p "$DATA_DIR"
    for data_file in recent meta; do
        if [ -f "$LEGACY_V2_DIR/$data_file" ] && [ ! -f "$DATA_DIR/$data_file" ]; then
            cp "$LEGACY_V2_DIR/$data_file" "$DATA_DIR/$data_file"
            echo -e "\e[1;32m    migrated $data_file from the 2.0 preview\e[0m"
        fi
    done
    rm -rf "$LEGACY_V2_DIR"
    echo -e "\e[1;33m    2.0 preview directory removed ($LEGACY_V2_DIR)\e[0m"
fi

echo -e "\e[1;34m==> Step 3/4: Copying files...\e[0m"

mkdir -p "$APP_DIR"
cp "$SCRIPT_DIR/mag.sh" "$APP_DIR/mag.sh"
rm -rf "$APP_DIR/lib"
cp -r "$SCRIPT_DIR/lib" "$APP_DIR/lib"
if [ -d "$SCRIPT_DIR/changelogs" ]; then
    rm -rf "$APP_DIR/changelogs"
    cp -r "$SCRIPT_DIR/changelogs" "$APP_DIR/changelogs"
fi
# Remember where the repo lives so 'mag update' can pull and reinstall.
printf '%s\n' "$SCRIPT_DIR" > "$DATA_DIR/source-repo"

echo -e "\e[1;34m==> Step 4/4: Updating shell startup files...\e[0m"

for rc_file in "${RC_FILES[@]}"; do
    touch "$rc_file"

    # Older installs define the same 'mag' function: retire their lines.
    if grep -Fq "$LEGACY_V1_LINE" "$rc_file" || grep -Fq "$LEGACY_V2_LINE" "$rc_file"; then
        cp "$rc_file" "$rc_file.bak"
        awk -v l1="$LEGACY_V1_LINE" -v l2="$LEGACY_V2_LINE" \
            '$0 != l1 && $0 != l2 && $0 != "# Magazzino (Project Manager)" && $0 != "# Magazzino 2 (Project Manager)" { print }' \
            "$rc_file" > "$rc_file.tmp"
        mv "$rc_file.tmp" "$rc_file"
        legacy_removed_from+=("$rc_file")
    fi

    if ! grep -Fqx "$SOURCE_LINE" "$rc_file"; then
        printf '\n# Magazzino (Project Manager)\n%s\n' "$SOURCE_LINE" >> "$rc_file"
        updated_rc_files+=("$rc_file")
    fi
done

if [ "${#legacy_removed_from[@]}" -gt 0 ]; then
    echo -e "\e[1;33m==> Older Magazzino source lines removed from: ${legacy_removed_from[*]} (backups: .bak).\e[0m"
fi

if [ "${#updated_rc_files[@]}" -gt 0 ]; then
    echo -e "\e[1;32m==> Added Magazzino to: ${updated_rc_files[*]}.\e[0m"
else
    echo -e "\e[1;33m==> Magazzino is already configured in the supported shell files.\e[0m"
fi

echo -e "\e[1;34m==> Install summary\e[0m"
echo -e "\e[1;32m   version:\e[0m v${VERSION:-unknown}"
echo -e "\e[1;32m   install dir:\e[0m $APP_DIR"
echo -e "\e[1;32m   update source:\e[0m $SCRIPT_DIR"
echo -e "\e[1;32m   startup file:\e[0m $PRIMARY_RC"
echo -e "\e[1;32m==> Done. Restart the terminal, or run: source $PRIMARY_RC\e[0m"
echo -e "\e[1;34m==> Type 'mag' for the dashboard, 'mag help' for the command list, 'mag update' to update.\e[0m"
