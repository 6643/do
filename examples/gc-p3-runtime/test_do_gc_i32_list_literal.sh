#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
fixture="$repo_root/examples/gc-p3-runtime/i32-list-literal.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-i32-list.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

wat_path="$tmp_dir/i32-list-literal.wat"
zig run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$wat_path" make
"$wasm_tools_bin" parse "$wat_path" -o "$tmp_dir/i32-list-literal.wasm"
"$wasmtime_bin" compile -W gc=y -o "$tmp_dir/i32-list-literal.compiled" "$wat_path"
result=$("$wasmtime_bin" -W gc=y --invoke probe "$wat_path")
if [ "$result" != "27815" ]; then
  printf 'expected GC i32 list literal result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC i32 list literal passed: %s\n' "$result"
