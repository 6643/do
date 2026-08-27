#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-$repo_root/bin/do}
wasm_tools_bin=${WASM_TOOLS_BIN:-$(command -v wasm-tools || true)}
fixture="$repo_root/examples/gc-p3-runtime/scalar-call-graph.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-scalar-call-graph.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler: %s\n' "$do_bin" >&2
  exit 1
fi
if [ -z "$wasm_tools_bin" ] || [ ! -x "$wasm_tools_bin" ]; then
  printf 'missing wasm-tools executable\n' >&2
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

wat_path="$tmp_dir/scalar-call-graph.wat"
wasm_path="$tmp_dir/scalar-call-graph.wasm"
DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" -o "$wat_path"
"$wasm_tools_bin" parse "$wat_path" -o "$wasm_path"

rg -q ';; gc-sync ' "$wat_path"
rg -q 'call \$leaf' "$wat_path"
rg -q 'call \$middle' "$wat_path"
if rg -q '__arc_' "$wat_path"; then
  printf 'scalar call-graph WAT contains an obsolete ARC marker: %s\n' "$wat_path" >&2
  exit 1
fi
test -s "$wasm_path"
printf 'Do GC scalar call-graph gate passed\n'
