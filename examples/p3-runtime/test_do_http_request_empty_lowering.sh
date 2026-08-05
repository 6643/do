#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
fixture="$repo_root/examples/p3-runtime/http-request-empty.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-request-empty.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/request.wat"
wit="$tmp_dir/request.wit"
core_wasm="$tmp_dir/request.wasm"
embedded="$tmp_dir/request.embedded.wasm"
component="$tmp_dir/request.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[constructor]fields"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[static]request.new"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[future-new-1]request-new-payload"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[future-write-1]request-new-payload"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[future-drop-writable-1]request-new-payload"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[future-drop-readable-2]request-new-payload"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]request"' "$core_wat"

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world http-request-probe --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

printf 'WASI HTTP empty request lowering passed\n'
