#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$repo_root/examples/p3-runtime/async-resource-result-component.do"
wit="$repo_root/src/build/p3_async_resource_probe.wit"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-async-resource-result.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_path="$tmp_dir/async-resource-result.wat"
wit_path="$tmp_dir/async-resource-result.wit"
embedded_path="$tmp_dir/async-resource-result.embedded.wasm"
component_path="$tmp_dir/async-resource-result.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" \
  --p3-async-component --p3-wit-output "$wit_path" -o "$core_path"

cmp "$wit" "$wit_path"
grep -Fq '[async-lower]send' "$core_path"
grep -Fq '[resource-drop]request' "$core_path"
grep -Fq '[resource-drop]response' "$core_path"
grep -Fq '[task-return]run' "$core_path"
grep -Fq '(type $async-frame (struct' "$core_path"
grep -Fq '(field $slot-result-ptr (mut i32))' "$core_path"
grep -Fq '(table $async-frames 0 (ref null $async-frame))' "$core_path"
grep -Fq '$result-buffer-for-handle' "$core_path"
grep -Fq '[resource-result-error-terminal]' "$core_path"
grep -Fq 'i32.const 0' "$core_path"
if grep -Fq 'global $frame-next' "$core_path"; then
  printf 'async resource Result lowering still uses the linear-memory frame allocator\n' >&2
  exit 1
fi

wasm-tools parse "$core_path" -o "$tmp_dir/async-resource-result.wasm"
wasm-tools component embed "$wit_path" "$tmp_dir/async-resource-result.wasm" \
  --world async-resource-probe -o "$embedded_path"
wasm-tools component new "$embedded_path" -o "$component_path"
wasm-tools validate "$component_path"
