#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-stream-writer-producer-helper-two-hop-descriptor.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
core_path="$tmp_dir/stream-writer-producer-helper-two-hop.wat"
wit_path="$tmp_dir/stream-writer-producer-helper-two-hop.wit"
core_wasm="$tmp_dir/stream-writer-producer-helper-two-hop.wasm"
embedded_path="$tmp_dir/stream-writer-producer-helper-two-hop.embedded.wasm"
component_path="$tmp_dir/stream-writer-producer-helper-two-hop.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
  --p3-wit-output "$wit_path" \
  "$repo_root/examples/p3-runtime/stream-probe-guest-producer-helper-two-hop.do" \
  -o "$core_path"

cmp "$wit_path" "$repo_root/examples/p3-runtime/wit/stream-probe-guest-producer.wit"
for marker in \
  'do:stream-probe/sink@0.1.0' \
  '[writer-queue-pump]' \
  '[writer-lease-transfer] async-helper' \
  '[writer-endpoint-mode] guest-producer' \
  '[stream-drop-writable-0]write-via-stream'; do
  grep -Fq "$marker" "$core_path"
done
grep -Fq '(data (i32.const 512) "\41\42")' "$core_path"

wasm-tools parse "$core_path" -o "$core_wasm"
wasm-tools component embed "$wit_path" "$core_wasm" \
  --world stream-writer-probe -o "$embedded_path"
wasm-tools component new "$embedded_path" -o "$component_path"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component_path"

printf 'two-hop async-helper producer lease lowering passed\n'
