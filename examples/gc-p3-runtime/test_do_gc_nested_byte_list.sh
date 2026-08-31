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
fixture="$repo_root/examples/gc-p3-runtime/nested-byte-list.do"
tmp_dir=$(mktemp -d "$repo_root/.gc-nested-byte-list.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT


wat_path="$tmp_dir/nested-byte-list.wat"
zig run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$wat_path" make_nested
"$toolchain_bin" parse-core "$wat_path" -o "$tmp_dir/nested-byte-list.wasm"
"$toolchain_bin" compile-core-gc "$wat_path" -o "$tmp_dir/nested-byte-list.compiled"

result=$("$toolchain_bin" invoke-core-gc "$wat_path" --export probe)
if [ "$result" != "27815" ]; then
  printf 'expected nested GC byte-list result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC nested byte-list passed: %s\n' "$result"
