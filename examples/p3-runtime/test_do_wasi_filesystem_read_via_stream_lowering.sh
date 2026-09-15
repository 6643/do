#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-read-via-stream-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/read-via-stream.wat"
core_wasm="$tmp_dir/read-via-stream.wasm"
wit="$tmp_dir/read-via-stream.wit"
embedded="$tmp_dir/read-via-stream.embedded.wasm"
component="$tmp_dir/read-via-stream.component.wasm"
bounded_wat="$tmp_dir/read-via-stream-bounded.wat"
bounded_wit="$tmp_dir/read-via-stream-bounded.wit"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build \
  "$repo_root/examples/p3-runtime/wasi-filesystem-read-via-stream.do" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" read-via-stream-probe -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

for marker in \
  '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[method]descriptor.read-via-stream"' \
  '"[async-lower][stream-cancel-read-0][method]descriptor.read-via-stream"' \
  '"[async-lower][stream-read-0][method]descriptor.read-via-stream"' \
  '"[async-lower][future-cancel-read-1][method]descriptor.read-via-stream"' \
  '"[async-lower][future-read-1][method]descriptor.read-via-stream"' \
  'call $stream-drop-readable' \
  'call $future-drop-readable' \
  'call $descriptor-drop' \
  'local.get $code i32.const 2 i32.eq' \
  'i64.store'; do
  grep -Fq "$marker" "$core_wat"
done

if grep -Fq '[async-lower][method]descriptor.read-via-stream' "$core_wat"; then
  printf '%s\n' 'read-via-stream must use the synchronous method import' >&2
  exit 1
fi

grep -Fq 'read-via-stream: func(offset: u64) -> tuple<stream<u8>, future<result<_, error-code>>>;' "$wit"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build \
  "$repo_root/examples/p3-runtime/wasi-filesystem-read-via-stream-bounded.do" \
  --p3-async-component --p3-wit-output "$bounded_wit" -o "$bounded_wat"
grep -Fq 'i32.const 2' "$bounded_wat"

printf '%s\n' 'WASI D2 read-via-stream lowering passed'
