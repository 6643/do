#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi
fixture="$repo_root/examples/gc-p3-runtime/managed-struct-set.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-managed-struct-set.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT


wat_path="$tmp_dir/managed-struct-set.wat"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" --gc-core -o "$wat_path"
"$toolchain_bin" parse-core "$wat_path" -o "$tmp_dir/managed-struct-set.wasm"
"$toolchain_bin" compile-core-gc "$wat_path" -o "$tmp_dir/managed-struct-set.compiled"

result=$("$toolchain_bin" invoke-core-gc "$wat_path" --export probe)
if [ "$result" != "27815" ]; then
  printf 'expected GC managed struct persistent update result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC managed struct persistent update passed: %s\n' "$result"
