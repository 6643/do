#!/usr/bin/env bash
set -euo pipefail
# Verification Status: verified

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
zig_bin=${ZIG_BIN:-zig}
probe=$repo_root/src/gc_marshal_map_probe_main.zig
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-map.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -f "$probe" ]; then
  printf 'missing map marshal probe: %s\n' "$probe" >&2
  exit 1
fi
if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi

for value_kind in u32 text; do
  for direction in lower lift; do
    wat_path=$tmp_dir/${value_kind}-${direction}.wat
    wasm_path=$tmp_dir/${value_kind}-${direction}.wasm
    if [ "$value_kind" = u32 ]; then
      "$zig_bin" run "$probe" -- "$direction" "$wat_path"
    else
      "$zig_bin" run "$probe" -- "$direction" "$value_kind" "$wat_path"
    fi
    "$toolchain_bin" parse-core "$wat_path" -o "$wasm_path"
    "$toolchain_bin" validate-core "$wasm_path"
  done
done

printf 'u32 and text map Core WAT parse/validate passed for lower and lift\n'
