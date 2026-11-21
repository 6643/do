#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
toolchain_bin="$repo_root/bin/do-toolchain"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-write-via-stream.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/write-via-stream.wat"
core_wasm="$tmp_dir/write-via-stream.wasm"
wit="$tmp_dir/write-via-stream.wit"
embedded="$tmp_dir/write-via-stream.embedded.wasm"
component="$tmp_dir/write-via-stream.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build \
  "$repo_root/src/build/test/compile_ok/821_wasi_filesystem_write_via_stream_component.do" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" write-via-stream-probe -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

for marker in \
  '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][method]descriptor.write-via-stream"' \
  '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[stream-new-0][method]descriptor.write-via-stream"' \
  '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][stream-write-0][method]descriptor.write-via-stream"' \
  '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[stream-drop-writable-0][method]descriptor.write-via-stream"' \
  '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[resource-drop]descriptor"' \
  'i64.store' \
  'call $close-writer' \
  'call $stream-cancel-write' \
  '[filesystem-write-via-stream]'; do
  rg -Fq "$marker" "$core_wat"
done

if rg -Fq 'stream.forward' "$core_wat"; then
  printf '%s\n' 'compiler-generated write-via-stream route must not import stream.forward' >&2
  exit 1
fi

rg -Fq 'write-via-stream: async func(data: stream<u8>, offset: u64)' "$wit"
rg -Fq 'run: async func(file: own<descriptor>, offset: u64);' "$wit"
rg -Fq 'cancel: async func();' "$wit"

printf '%s\n' 'WASI D2 write-via-stream compiler lowering passed'
