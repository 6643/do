#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-remaining-scalars.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT


run_probe() {
  local type_name="$1" function_name="$2"
  local fixture="$repo_root/examples/gc-p3-runtime/${type_name}-list.do"
  local wat_path="$tmp_dir/${type_name}-${function_name}.wat"
  zig run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$wat_path" "$function_name"
  "$toolchain_bin" parse-core "$wat_path" -o "$tmp_dir/${type_name}-${function_name}.wasm"
  "$toolchain_bin" compile-core-gc "$wat_path" -o "$tmp_dir/${type_name}-${function_name}.compiled"
  local result
  result=$("$toolchain_bin" invoke-core-gc "$wat_path" --export probe)
  if [ "$result" != "27815" ]; then
    printf 'expected GC %s %s result 27815, got %s\n' "$type_name" "$function_name" "$result" >&2
    exit 1
  fi
  printf 'Do GC %s %s passed: %s\n' "$type_name" "$function_name" "$result"
}

for type_name in i8 u16 u64 isize usize; do
  run_probe "$type_name" make_values
  run_probe "$type_name" update
done
