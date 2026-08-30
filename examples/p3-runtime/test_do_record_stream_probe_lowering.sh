#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-record-stream-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/record-stream.wat"
core_wasm="$tmp_dir/record-stream.wasm"
wit="$tmp_dir/record-stream.wit"
embedded="$tmp_dir/record-stream.embedded.wasm"
component="$tmp_dir/record-stream.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/record-stream-probe-component.do" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

cmp "$wit" "$repo_root/examples/p3-runtime/wit/record-stream-probe.wit"
for marker in \
  '[record-stream-plan]' \
  '[record-loop-state]' \
  '[record-read-index]' \
  '[record-field-id-offset]' \
  '[record-field-label-ptr-offset]' \
  '[record-field-label-len-offset]' \
  'call $cleanup' \
  '"do:record-stream-probe/source@0.1.0" "read-via-stream"' \
  '"[async-lower][stream-read-0]read-via-stream"' \
  '"[async-lower][future-read-1]read-via-stream"'; do
  grep -Fq "$marker" "$core_wat"
done
if grep -Fq 'directory-entry' "$core_wat"; then
  exit 1
fi

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" \
  record-stream-probe -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"

printf 'generic record-stream lowering passed\n'
