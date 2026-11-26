#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

if (( $# < 2 )); then
    printf 'Usage: %s /path/to/title.exe /path/to/victory.exe [VIctory run options]\n' "$0" >&2
    exit 2
fi
command -v umu-run >/dev/null || { echo 'Install umu-launcher first.' >&2; exit 1; }

title=$(realpath -e -- "$1")
runtime=$(realpath -e -- "$2")
shift 2
if [[ ! -f "$title" || ! -f "$runtime" ]]; then
    echo 'Both arguments must point to executables.' >&2
    exit 2
fi

export PROTONPATH="${PROTONPATH:?Set PROTONPATH to your GE-Proton installation}"
export WINEPREFIX="${WINEPREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/victory/proton-ge}"
export GAMEID="${GAMEID:-umu-victory}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d12,d3d12core,dxgi,d3dcompiler_47=n}"
export STEAM_COMPAT_INSTALL_PATH="${STEAM_COMPAT_INSTALL_PATH:-$(dirname -- "$runtime")}"
export PRESSURE_VESSEL_FILESYSTEMS_RO="$(dirname -- "$title")${PRESSURE_VESSEL_FILESYSTEMS_RO:+:$PRESSURE_VESSEL_FILESYSTEMS_RO}"

export VICTORY_FRAME_INTERVAL_MS="${VICTORY_FRAME_INTERVAL_MS:-0}"
export VICTORY_LIBRARY_EARLY="${VICTORY_LIBRARY_EARLY:-0}"
export VICTORY_HEAP_WORKER="${VICTORY_HEAP_WORKER:-1}"
export VICTORY_TEXTURE_NO_WAIT="${VICTORY_TEXTURE_NO_WAIT:-1}"

windows_title=${title//\//\\}
windows_runtime=${runtime//\//\\}
exec umu-run "Z:$windows_runtime" run "Z:$windows_title" --execute "$@"
