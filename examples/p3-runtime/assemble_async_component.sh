#!/usr/bin/env bash
set -euo pipefail

# Current Component assembly entrypoint. Tool identity and capability checks are
# centralized in the repository's current-only Zig adapter.
if (($# != 4)); then
    printf 'usage: %s <wit> <core-wasm> <world> <component-wasm>\n' "$0" >&2
    exit 2
fi

wit_path=$1
core_path=$2
world_name=$3
component_path=$4
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLCHAIN_BIN="${DO_TOOLCHAIN_BIN:-$ROOT_DIR/bin/do-toolchain}"
[[ -x "$TOOLCHAIN_BIN" ]] || {
    printf 'missing do-toolchain executable: %s\n' "$TOOLCHAIN_BIN" >&2
    exit 1
}

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-wasmtime-p3.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT
embedded_path="$work_dir/embedded.wasm"

"$TOOLCHAIN_BIN" embed-component "$wit_path" "$core_path" "$world_name" -o "$embedded_path"
"$TOOLCHAIN_BIN" new-component "$embedded_path" -o "$component_path"
"$TOOLCHAIN_BIN" validate-component "$component_path"

printf 'target=wasmtime-p3 toolchain-adapter=current-only async-names=legacy callback=enabled\n'
