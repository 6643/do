#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-record-resource-stream-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/record-resource-stream.wat"
core_wasm="$tmp_dir/record-resource-stream.wasm"
wit="$tmp_dir/record-resource-stream.wit"
embedded="$tmp_dir/record-resource-stream.embedded.wasm"
component="$tmp_dir/record-resource-stream.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/record-resource-stream-probe-component.do" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

cmp "$wit" "$repo_root/examples/p3-runtime/wit/record-resource-stream-probe.wit"
for marker in \
  '[record-stream-plan]' \
  '[record-resource-field-ticket]' \
  '[record-resource-release-ticket]' \
  '[resource-drop]ticket' \
  'call $release-record' \
  '"do:record-resource-stream-probe/source@0.1.0" "read-via-stream"' \
  '"do:record-resource-stream-probe/source@0.1.0" "[resource-drop]ticket"' \
  '"[async-lower][stream-read-0]read-via-stream"' \
  '"[async-lower][future-read-1]read-via-stream"'; do
  grep -Fq "$marker" "$core_wat"
done
if grep -Fq 'directory-entry' "$core_wat"; then
  exit 1
fi

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world record-resource-stream-probe --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

printf 'generic record-resource stream lowering passed\n'
