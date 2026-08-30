#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-stream-writer-producer-parameterized-forwarding-helper.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_path="$tmp_dir/stream-writer-producer-parameterized-forwarding-helper.wat"
wit_path="$tmp_dir/stream-writer-producer-parameterized-forwarding-helper.wit"
core_wasm="$tmp_dir/stream-writer-producer-parameterized-forwarding-helper.wasm"
embedded_path="$tmp_dir/stream-writer-producer-parameterized-forwarding-helper.embedded.wasm"
component_path="$tmp_dir/stream-writer-producer-parameterized-forwarding-helper.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
  --p3-wit-output "$wit_path" \
  "$repo_root/examples/p3-runtime/stream-probe-guest-producer-parameterized-forwarding-helper.do" \
  -o "$core_path"

cmp "$wit_path" "$repo_root/examples/p3-runtime/wit/stream-probe-guest-producer-parameterized-forwarding-helper.wit"
for marker in \
  '[writer-endpoint-mode] guest-producer' \
  '[writer-lease-transfer] async-helper' \
  '[writer-producer-index-offset] 52' \
  '[writer-producer-value-offset] 60' \
  '(type $async-run-i64-i32 (func (param i64 i32) (result i32)))' \
  '(func (export "[async-lift]produce") (type $async-run-i64-i32)'; do
  grep -Fq "$marker" "$core_path"
done
if grep -Fq '(func (export "[async-lift]forward_stream")' "$core_path" ||
  grep -Fq '(func (export "[async-lift]finish_stream")' "$core_path"; then
  printf 'parameterized forwarding helper must not add a helper Component export\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$core_path" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit_path" "$core_wasm" stream-writer-probe -o "$embedded_path"
"$toolchain_bin" new-component "$embedded_path" -o "$component_path"
"$toolchain_bin" validate-component "$component_path"

printf 'parameterized forwarding helper producer Component lowering passed\n'
