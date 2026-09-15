#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
wit_root="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-filesystem-read-via-stream-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wat="$tmp_dir/filesystem.wat"
core_wasm="$tmp_dir/filesystem.wasm"
component="$tmp_dir/filesystem.component.wasm"
component_wit="$tmp_dir/filesystem.component.wit"

"$toolchain_bin" embed-component-template "$wit_root" wasi:filesystem/imports \
  --features component-async > "$wat"

require_wat() {
  if ! grep -Fq -- "$1" "$wat"; then
    printf 'missing read-via-stream ABI fragment: %s\n' "$1" >&2
    exit 1
  fi
}

require_import_type() {
  local import_name="$1"
  local type_index="$2"
  local line
  line=$(grep -F "\"wasi:filesystem/types@0.3.0-rc-2025-09-16\" \"$import_name\" (func " "$wat" || true)
  case "$line" in
    *"(type $type_index)))"*) ;;
    *)
      printf 'read-via-stream ABI import has unexpected type: %s -> type %s\n' "$import_name" "$type_index" >&2
      exit 1
      ;;
  esac
}

# The pinned current template emits a synchronous Component method. Its Core
# arguments are descriptor, filesize (u64), and the tuple result-area pointer.
require_wat '(type (;1;) (func (param i32 i64 i32)))'
require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[method]descriptor.read-via-stream" (func'
require_import_type '[method]descriptor.read-via-stream' 1

if grep -Fq '[async-lower][method]descriptor.read-via-stream' "$wat"; then
  printf 'read-via-stream unexpectedly lowered as an async method\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$wat" -o "$core_wasm"
"$toolchain_bin" new-component "$core_wasm" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async
"$toolchain_bin" component-wit "$component" > "$component_wit"

grep -Fq 'read-via-stream: func(offset: filesize) -> tuple<stream<u8>, future<result<_, error-code>>>;' "$component_wit"

printf 'WASI filesystem read-via-stream ABI probe passed\n'
