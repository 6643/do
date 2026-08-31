#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-$repo_root/bin/do}
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
fixture="$repo_root/examples/gc-p3-runtime/scalar-leaf.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-scalar-leaf.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing executable do compiler: %s\n' "$do_bin" >&2
  exit 1
fi
wat_path="$tmp_dir/scalar-leaf.wat"
wasm_path="$tmp_dir/scalar-leaf.wasm"
DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" -o "$wat_path"
if ! rg -q ';; gc-sync ' "$wat_path"; then
  printf 'scalar-leaf WAT lacks the GC marker: %s\n' "$wat_path" >&2
  exit 1
fi
if rg -q '__arc_' "$wat_path"; then
  printf 'scalar-leaf WAT contains an ARC marker: %s\n' "$wat_path" >&2
  exit 1
fi
rg -q '\(func \$identity' "$wat_path"
rg -q '\(func \$sum_values' "$wat_path"
"$toolchain_bin" parse-core "$wat_path" -o "$wasm_path"
if [ ! -s "$wasm_path" ]; then
  printf 'Core parse produced no Wasm: %s\n' "$fixture" >&2
  exit 1
fi
printf 'Do GC scalar leaf passed: %s\n' "$wasm_path"
