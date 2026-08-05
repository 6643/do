#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-stream-writer-descriptor.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_path="$tmp_dir/stream-writer.wat"
wit_path="$tmp_dir/stream-writer.wit"
core_wasm="$tmp_dir/stream-writer.wasm"
embedded_path="$tmp_dir/stream-writer.embedded.wasm"
component_path="$tmp_dir/stream-writer.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
    --p3-wit-output "$wit_path" \
    "$repo_root/examples/p3-runtime/stream-probe-writer-component.do" \
    -o "$core_path"

grep -Fq 'do:stream-probe/sink@0.1.0' "$core_path"
grep -Fq 'package do:stream-probe@0.1.0' "$wit_path"
grep -Fq 'interface sink' "$wit_path"
grep -Fq 'world stream-writer-probe' "$wit_path"

wasm-tools parse "$core_path" -o "$core_wasm"
wasm-tools component embed "$wit_path" "$core_wasm" --world stream-writer-probe -o "$embedded_path"
wasm-tools component new "$embedded_path" -o "$component_path"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component_path"

printf 'descriptor-owned stream writer lowering passed\n'
