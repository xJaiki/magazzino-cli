#!/usr/bin/env bash
# Magazzino — entry point.
# Source this file from your shell rc; it loads every module in lib/.

MAG_VERSION="1.2.1"

# Resolve our own location in both bash (BASH_SOURCE) and zsh (%x).
_MAG_SRC="${BASH_SOURCE[0]:-${(%):-%x}}"
_MAG_HOME="$(cd "$(dirname "$_MAG_SRC")" && pwd)"
unset _MAG_SRC

if [ ! -d "$_MAG_HOME/lib" ]; then
  echo "magazzino: lib/ directory not found next to mag.sh ($_MAG_HOME)" >&2
  return 1 2>/dev/null || exit 1
fi

for _mag_lib in "$_MAG_HOME"/lib/*.sh; do
  . "$_mag_lib"
done
unset _mag_lib

_mag_load_config
_mag_load_plugins
_mag_ensure_helper_scripts
_mag_setup_completion
