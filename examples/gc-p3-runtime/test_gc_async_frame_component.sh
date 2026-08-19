#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-$repo_root/bin/do}
wasm_tools_bin=${WASM_TOOLS_BIN:-/home/_/.local/bin/wasm-tools}
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
fixture="$repo_root/examples/p3-runtime/two-await-component.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-async-frame-component.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler: %s\n' "$do_bin" >&2
  exit 1
fi
if [ ! -x "$wasm_tools_bin" ]; then
  printf 'missing wasm-tools executable: %s\n' "$wasm_tools_bin" >&2
  exit 1
fi
if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing Wasmtime executable: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

expected_wasm_tools='wasm-tools 1.255.0 (76e20611d 2026-07-30)'
actual_wasm_tools=$($wasm_tools_bin --version)
if [ "$actual_wasm_tools" != "$expected_wasm_tools" ]; then
  printf 'unexpected wasm-tools version: expected %s, got %s\n' \
    "$expected_wasm_tools" "$actual_wasm_tools" >&2
  exit 1
fi

wat_path="$tmp_dir/two-await.wat"
wit_path="$tmp_dir/two-await.wit"
core_path="$tmp_dir/two-await.core.wasm"
embedded_path="$tmp_dir/two-await.embedded.wasm"
component_path="$tmp_dir/two-await.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
  --p3-wait-for-component --p3-wit-output "$wit_path" -o "$wat_path"

if grep -Fq '__arc_' "$wat_path"; then
  printf 'bounded async GC frame output contains ARC markers\n' >&2
  exit 1
fi
for marker in \
  '(type $async-frame (struct' \
  '(table $async-frames 0 (ref null $async-frame))' \
  'table.get $async-frames' \
  'struct.get $async-frame $waitable-set'; do
  if ! grep -Fq "$marker" "$wat_path"; then
    printf 'bounded async GC frame output is missing marker: %s\n' "$marker" >&2
    exit 1
  fi
done
if grep -Fq 'global $frame-next' "$wat_path"; then
  printf 'bounded async GC frame output still uses linear-memory frame allocation\n' >&2
  exit 1
fi

"$wasm_tools_bin" parse "$wat_path" -o "$core_path"
"$wasmtime_bin" compile -W gc=y -o "$tmp_dir/two-await.compiled" "$wat_path"
"$wasm_tools_bin" component embed "$wit_path" "$wat_path" --world probe -o "$embedded_path"
"$wasm_tools_bin" component new "$embedded_path" -o "$component_path"
"$wasm_tools_bin" validate "$component_path"

printf 'Do bounded async GC frame/table component passed: fixture=%s wasm-tools=%s\n' \
  "$(basename "$fixture")" "$actual_wasm_tools"
