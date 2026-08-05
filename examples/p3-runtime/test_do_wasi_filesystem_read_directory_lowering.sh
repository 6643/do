#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-read-directory-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/read-directory.wat"
core_wasm="$tmp_dir/read-directory.wasm"
wit="$tmp_dir/read-directory.wit"
embedded="$tmp_dir/read-directory.embedded.wasm"
component="$tmp_dir/read-directory.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/wasi-filesystem-read-directory.do" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world read-directory-probe --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

for marker in \
  '"[async-lower][method]descriptor.read-directory"' \
  '"[async-lower][stream-read-0][method]descriptor.read-directory"' \
  '"[async-lower][future-read-1][method]descriptor.read-directory"' \
  'call $future-drop-readable' \
  'call $stream-drop-readable' \
  'call $descriptor-drop'; do
  grep -Fq "$marker" "$core_wat"
done

grep -Fq 'record directory-entry {' "$wit"
grep -Fq 'read-directory: async func() -> tuple<stream<directory-entry>, future<result<_, error-code>>>;' "$wit"

printf 'WASI G6.2 read-directory lowering passed\n'
