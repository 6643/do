#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-stream-writer-producer-parameterized.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_path="$tmp_dir/stream-writer-producer-parameterized.wat"
wit_path="$tmp_dir/stream-writer-producer-parameterized.wit"
core_wasm="$tmp_dir/stream-writer-producer-parameterized.wasm"
embedded_path="$tmp_dir/stream-writer-producer-parameterized.embedded.wasm"
component_path="$tmp_dir/stream-writer-producer-parameterized.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
  --p3-wit-output "$wit_path" \
  "$repo_root/examples/p3-runtime/stream-probe-guest-producer-parameterized.do" \
  -o "$core_path"

cmp "$wit_path" "$repo_root/examples/p3-runtime/wit/stream-probe-guest-producer-parameterized.wit"
grep -Fq '[writer-endpoint-mode] guest-producer' "$core_path"
grep -Fq '[writer-producer-value-offset] 60' "$core_path"
grep -Fq '(type $async-run-i64-i32 (func (param i64 i32) (result i32)))' "$core_path"
grep -Fq '(func (export "[async-lift]produce") (type $async-run-i64-i32)' "$core_path"
grep -Fq 'i32.store8' "$core_path"
grep -Fq 'i32.load8_u' "$core_path"
grep -Fq '(data (i32.const 512) "\00")' "$core_path"
grep -Fq 'call $writer-source-complete-countdown' "$core_path"

"$toolchain_bin" parse-core "$core_path" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit_path" "$core_wasm" stream-writer-probe -o "$embedded_path"
"$toolchain_bin" new-component "$embedded_path" -o "$component_path"
"$toolchain_bin" validate-component "$component_path"

printf 'parameterized dynamic producer Component lowering passed\n'
