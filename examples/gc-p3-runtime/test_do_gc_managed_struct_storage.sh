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
do_bin=${DO_BIN:-$repo_root/bin/do}
fixture="$repo_root/examples/gc-p3-runtime/managed-struct-storage.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-managed-struct-storage.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler executable: %s\n' "$do_bin" >&2
  exit 1
fi

wat_path="$tmp_dir/managed-struct-storage.wat"
wasm_path="$tmp_dir/managed-struct-storage.wasm"
DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" -o "$wat_path"
if rg -q '__arc_|__storage_|__struct_literal_tmp' "$wat_path"; then
  printf 'managed struct storage output contains legacy compiler markers\n' >&2
  exit 1
fi
if ! rg -q ';; gc-sync |\$box|gc-root local_bind' "$wat_path"; then
  printf 'managed struct storage output lacks GC markers\n' >&2
  exit 1
fi
"$toolchain_bin" parse-core "$wat_path" -o "$wasm_path" >/dev/null
"$toolchain_bin" run-core-gc "$wasm_path"
printf 'Do GC managed struct storage passed\n'
