#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-record-resource-stream-nested-three-level-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/record-resource-stream-nested-three-level.wat"
core_wasm="$tmp_dir/record-resource-stream-nested-three-level.wasm"
wit="$tmp_dir/record-resource-stream-nested-three-level.wit"
embedded="$tmp_dir/record-resource-stream-nested-three-level.embedded.wasm"
component="$tmp_dir/record-resource-stream-nested-three-level.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/record-resource-stream-nested-three-level-probe-component.do" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

cmp "$wit" "$repo_root/examples/p3-runtime/wit/record-resource-stream-nested-three-level-probe.wit"
for marker in \
  '[record-stream-plan]' \
  '[record-resource-field-ticket]' \
  '[record-resource-release-ticket]' \
  '[resource-drop]ticket' \
  'call $release-record' \
  '"do:record-resource-stream-nested-three-level/source@0.1.0" "read-via-stream"' \
  '"do:record-resource-stream-nested-three-level/source@0.1.0" "[resource-drop]ticket"' \
  '"[async-lower][stream-read-0]read-via-stream"' \
  '"[async-lower][future-read-1]read-via-stream"'; do
  grep -Fq "$marker" "$core_wat"
done

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" \
  record-resource-stream-nested-three-level -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"

printf 'generic three-level nested-resource record-stream lowering passed\n'
