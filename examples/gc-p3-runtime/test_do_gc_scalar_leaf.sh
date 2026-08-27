#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-$repo_root/bin/do}
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
fixture="$repo_root/examples/gc-p3-runtime/scalar-leaf.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-scalar-leaf.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing executable do compiler: %s\n' "$do_bin" >&2
  exit 1
fi
if [ ! -x "$wasm_tools_bin" ]; then
  printf 'missing executable wasm-tools binary: %s\n' "$wasm_tools_bin" >&2
  exit 1
fi

wasm_tools_version=$("$wasm_tools_bin" --version 2>/dev/null || true)
case "$wasm_tools_version" in
  'wasm-tools 1.255.0'*) ;;
  *)
    printf 'unsupported wasm-tools version: %s (expected 1.255.0)\n' "${wasm_tools_version:-<unknown>}" >&2
    exit 1
    ;;
esac

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
"$wasm_tools_bin" parse "$wat_path" -o "$wasm_path"
if [ ! -s "$wasm_path" ]; then
  printf 'wasm-tools parse produced no Wasm: %s\n' "$fixture" >&2
  exit 1
fi
printf 'Do GC scalar leaf passed: %s\n' "$wasm_path"
