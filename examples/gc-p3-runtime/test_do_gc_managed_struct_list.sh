#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi
zig_bin=${ZIG_BIN:-zig}
fixture="$repo_root/examples/gc-p3-runtime/managed-struct-list.do"
tmp_dir=$(mktemp -d "$repo_root/.gc-managed-struct-list.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT


wat_path="$tmp_dir/managed-struct-list.wat"
"$zig_bin" run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$wat_path" make_boxes
"$toolchain_bin" parse-core "$wat_path" -o "$tmp_dir/managed-struct-list.wasm"
"$toolchain_bin" compile-core-gc "$wat_path" -o "$tmp_dir/managed-struct-list.compiled"

result=$("$toolchain_bin" invoke-core-gc "$wat_path" --export probe)
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
"$toolchain_bin" parse-core "$append_wat_path" -o "$tmp_dir/managed-struct-list-append.wasm"
"$toolchain_bin" compile-core-gc "$append_wat_path" -o "$tmp_dir/managed-struct-list-append.compiled"
append_result=$("$toolchain_bin" invoke-core-gc "$append_wat_path" --export probe)
if [ "$append_result" != "27815" ]; then
  printf 'expected GC managed struct list append result 27815, got %s\n' "$append_result" >&2
  exit 1
fi
printf 'Do GC managed struct list append passed: %s\n' "$append_result"
