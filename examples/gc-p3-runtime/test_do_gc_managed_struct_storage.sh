#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-$repo_root/bin/do}
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
fixture="$repo_root/examples/gc-p3-runtime/managed-struct-storage.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-managed-struct-storage.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler executable: %s\n' "$do_bin" >&2
  exit 1
fi
if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
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
"$wasm_tools_bin" parse "$wat_path" -o "$wasm_path" >/dev/null
"$wasmtime_bin" run -W gc=y "$wasm_path"
printf 'Do GC managed struct storage passed\n'
