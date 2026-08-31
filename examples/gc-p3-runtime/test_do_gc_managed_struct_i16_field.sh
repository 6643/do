#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi
fixture="$repo_root/examples/gc-p3-runtime/managed-struct-i16-field.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-managed-struct-i16-field.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT


wat_path="$tmp_dir/managed-struct-i16-field.wat"
zig run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$wat_path" replace
"$toolchain_bin" parse-core "$wat_path" -o "$tmp_dir/managed-struct-i16-field.wasm"
"$toolchain_bin" compile-core-gc "$wat_path" -o "$tmp_dir/managed-struct-i16-field.compiled"

result=$("$toolchain_bin" invoke-core-gc "$wat_path" --export probe)
if [ "$result" != "27815" ]; then
  printf 'expected GC managed struct i16 field update result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC managed struct i16 field update passed: %s\n' "$result"
