#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-$repo_root/bin/do}
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
fixture="$repo_root/examples/gc-p3-runtime/scalar-control-flow.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-scalar-control-flow.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler: %s\n' "$do_bin" >&2
  exit 1
fi
wat_path="$tmp_dir/scalar-control-flow.wat"
wasm_path="$tmp_dir/scalar-control-flow.wasm"
DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" -o "$wat_path"
"$toolchain_bin" parse-core "$wat_path" -o "$wasm_path"

rg -q ';; gc-sync ' "$wat_path"
rg -q ';; gc-root branch_join' "$wat_path"
rg -q ';; gc-root guard_join' "$wat_path"
rg -q '\(func \$choose ' "$wat_path"
rg -q '\(func \$guard ' "$wat_path"
rg -q '\(func \$choose_chain ' "$wat_path"
if rg -q '__arc_' "$wat_path"; then
  printf 'scalar control-flow WAT contains an obsolete ARC marker: %s\n' "$wat_path" >&2
  exit 1
fi
test -s "$wasm_path"
printf 'Do GC scalar control-flow gate passed\n'
