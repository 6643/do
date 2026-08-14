#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-managed-remaining-scalars.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

run_probe() {
  local type_name="$1"
  local fixture="$repo_root/examples/gc-p3-runtime/managed-struct-${type_name}-field.do"
  local wat_path="$tmp_dir/managed-struct-${type_name}-field.wat"
  zig run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$wat_path" replace
  "$wasm_tools_bin" parse "$wat_path" -o "$tmp_dir/managed-struct-${type_name}-field.wasm"
  "$wasmtime_bin" compile -W gc=y -o "$tmp_dir/managed-struct-${type_name}-field.compiled" "$wat_path"
  local result
  result=$("$wasmtime_bin" -W gc=y --invoke probe "$wat_path")
  if [ "$result" != "27815" ]; then
    printf 'expected GC managed struct %s field result 27815, got %s\n' "$type_name" "$result" >&2
    exit 1
  fi
  printf 'Do GC managed struct %s field update passed: %s\n' "$type_name" "$result"
}

for type_name in i8 u16 u64 isize usize; do
  run_probe "$type_name"
done
