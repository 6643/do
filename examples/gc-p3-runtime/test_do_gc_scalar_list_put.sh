#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-scalar-list-put.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

for function_name in append_u32 append_f64; do
  wat_path="$tmp_dir/${function_name}.wat"
  zig run "$repo_root/src/build/gc_sync_probe.zig" -- "$repo_root/examples/gc-p3-runtime/scalar-list-put.do" "$wat_path" "$function_name"
  "$wasm_tools_bin" parse "$wat_path" -o "$tmp_dir/${function_name}.wasm"
  "$wasmtime_bin" compile -W gc=y -o "$tmp_dir/${function_name}.compiled" "$wat_path"
  result=$("$wasmtime_bin" -W gc=y --invoke probe "$wat_path")
  if [ "$result" != "27815" ]; then
    printf 'expected GC %s result 27815, got %s\n' "$function_name" "$result" >&2
    exit 1
  fi
  printf 'Do GC scalar-list put %s passed: %s\n' "$function_name" "$result"
done
