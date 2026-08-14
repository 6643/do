#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
zig_bin=${ZIG_BIN:-zig}
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
fixture="$repo_root/examples/gc-p3-runtime/managed-struct-payload.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-managed-struct-payload.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

wat_path="$tmp_dir/managed-struct-payload.wat"
"$zig_bin" run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$wat_path" update
"$wasm_tools_bin" parse "$wat_path" -o "$tmp_dir/managed-struct-payload.wasm"
"$wasmtime_bin" compile -W gc=y -o "$tmp_dir/managed-struct-payload.compiled" "$wat_path"

result=$("$wasmtime_bin" -W gc=y --invoke probe "$wat_path")
if [ "$result" != "27815" ]; then
  printf 'expected GC managed struct payload update result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC managed struct payload update passed: %s\n' "$result"
