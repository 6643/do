#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
zig_bin=${ZIG_BIN:-zig}
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
fixture="$repo_root/examples/gc-p3-runtime/managed-struct-list.do"
tmp_dir=$(mktemp -d "$repo_root/.gc-managed-struct-list.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

wat_path="$tmp_dir/managed-struct-list.wat"
"$zig_bin" run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$wat_path" make_boxes
"$wasm_tools_bin" parse "$wat_path" -o "$tmp_dir/managed-struct-list.wasm"
"$wasmtime_bin" compile -W gc=y -o "$tmp_dir/managed-struct-list.compiled" "$wat_path"

result=$("$wasmtime_bin" -W gc=y --invoke probe "$wat_path")
if [ "$result" != "27815" ]; then
  printf 'expected GC managed struct list result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC managed struct list passed: %s\n' "$result"

append_wat_path="$tmp_dir/managed-struct-list-append.wat"
"$zig_bin" run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$append_wat_path" append
if rg -q '__arc_' "$append_wat_path"; then
  printf 'managed struct list append output contains ARC markers\n' >&2
  exit 1
fi
if ! rg -q 'array.new_default \$do_list_box' "$append_wat_path" ||
   ! rg -q 'array.copy \$do_list_box \$do_list_box' "$append_wat_path" ||
   ! rg -q 'array.set \$do_list_box' "$append_wat_path"; then
  printf 'managed struct list append output lacks typed copy/set lowering\n' >&2
  exit 1
fi
"$wasm_tools_bin" parse "$append_wat_path" -o "$tmp_dir/managed-struct-list-append.wasm"
"$wasmtime_bin" compile -W gc=y -o "$tmp_dir/managed-struct-list-append.compiled" "$append_wat_path"
append_result=$("$wasmtime_bin" -W gc=y --invoke probe "$append_wat_path")
if [ "$append_result" != "27815" ]; then
  printf 'expected GC managed struct list append result 27815, got %s\n' "$append_result" >&2
  exit 1
fi
printf 'Do GC managed struct list append passed: %s\n' "$append_result"
