#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-stream-writer-producer-parameterized-four-hop.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_path="$tmp_dir/stream-writer-producer-parameterized-four-hop.wat"
wit_path="$tmp_dir/stream-writer-producer-parameterized-four-hop.wit"
core_wasm="$tmp_dir/stream-writer-producer-parameterized-four-hop.wasm"
embedded_path="$tmp_dir/stream-writer-producer-parameterized-four-hop.embedded.wasm"
component_path="$tmp_dir/stream-writer-producer-parameterized-four-hop.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
  --p3-wit-output "$wit_path" \
  "$repo_root/examples/p3-runtime/stream-probe-guest-producer-parameterized-four-hop.do" \
  -o "$core_path"

cmp "$wit_path" "$repo_root/examples/p3-runtime/wit/stream-probe-guest-producer-parameterized-four-hop.wit"
for marker in \
  '[writer-endpoint-mode] guest-producer' \
  '[writer-lease-transfer] async-helper' \
  '[writer-producer-index-offset] 52' \
  '[writer-producer-value-offset] 60' \
  '(type $async-run-i64-i32 (func (param i64 i32) (result i32)))' \
  '(func (export "[async-lift]produce") (type $async-run-i64-i32)'; do
  grep -Fq "$marker" "$core_path"
done
for helper in outer_stream entry_stream forward_stream middle_stream finish_stream; do
  if grep -Fq "(func (export \"[async-lift]$helper\")" "$core_path"; then
    printf 'parameterized four-hop helper must not add a helper Component export\n' >&2
    exit 1
  fi
done

wasm-tools parse "$core_path" -o "$core_wasm"
wasm-tools component embed "$wit_path" "$core_wasm" \
  --world stream-writer-probe -o "$embedded_path"
wasm-tools component new "$embedded_path" -o "$component_path"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component_path"

printf 'parameterized four-hop forwarding helper producer Component lowering passed\n'
