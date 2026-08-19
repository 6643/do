#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-$repo_root/bin/do}
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
fixture="$repo_root/examples/gc-p3-runtime/inferred-list-storage.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-inferred-list-storage.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler executable: %s\n' "$do_bin" >&2
  exit 1
fi
if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
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
"$wasm_tools_bin" parse "$wat_path" -o "$wasm_path" >/dev/null
"$wasmtime_bin" run -W gc=y "$wasm_path"
printf 'Do GC inferred list storage passed\n'
