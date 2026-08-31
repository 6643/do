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
fixture="$repo_root/examples/gc-p3-runtime/inferred-list-storage.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-inferred-list-storage.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler executable: %s\n' "$do_bin" >&2
  exit 1
fi

wat_path="$tmp_dir/inferred-list-storage.wat"
wasm_path="$tmp_dir/inferred-list-storage.wasm"
DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" -o "$wat_path"
if rg -q '__arc_|__storage_|__struct_literal_tmp' "$wat_path"; then
  printf 'inferred list storage output contains legacy compiler markers\n' >&2
  exit 1
fi
if ! rg -q '\(local \$values \(ref null \$do_bytes\)\)' "$wat_path"; then
  printf 'inferred list storage output lacks typed values local\n' >&2
  exit 1
fi
if ! rg -q 'array.copy \$do_bytes \$do_bytes' "$wat_path" || ! rg -q 'array.set \$do_bytes' "$wat_path"; then
  printf 'inferred list storage output lacks copy/set lowering\n' >&2
  exit 1
fi
"$toolchain_bin" parse-core "$wat_path" -o "$wasm_path" >/dev/null
"$toolchain_bin" run-core-gc "$wasm_path"
printf 'Do GC inferred list storage passed\n'
