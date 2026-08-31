#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-scalar-list-put.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT


for function_name in append_u32 append_f64; do
  wat_path="$tmp_dir/${function_name}.wat"
  zig run "$repo_root/src/build/gc_sync_probe.zig" -- "$repo_root/examples/gc-p3-runtime/scalar-list-put.do" "$wat_path" "$function_name"
  "$toolchain_bin" parse-core "$wat_path" -o "$tmp_dir/${function_name}.wasm"
  "$toolchain_bin" compile-core-gc "$wat_path" -o "$tmp_dir/${function_name}.compiled"
  result=$("$toolchain_bin" invoke-core-gc "$wat_path" --export probe)
  if [ "$result" != "27815" ]; then
    printf 'expected GC %s result 27815, got %s\n' "$function_name" "$result" >&2
    exit 1
  fi
  printf 'Do GC scalar-list put %s passed: %s\n' "$function_name" "$result"
done
