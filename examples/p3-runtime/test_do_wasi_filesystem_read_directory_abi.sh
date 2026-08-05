#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit_root="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-g6-2-read-directory-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

case "$(wasm-tools --version)" in
  "wasm-tools 1.254.0 (bb58fdf91 "*) ;;
  *)
    printf 'unexpected wasm-tools version: %s\n' "$(wasm-tools --version)" >&2
    exit 1
    ;;
esac

wat="$tmp_dir/filesystem.wat"
core_wasm="$tmp_dir/filesystem.wasm"
component="$tmp_dir/filesystem.component.wasm"
component_wit="$tmp_dir/filesystem.component.wit"

wasm-tools component embed "$wit_root" \
  --world wasi:filesystem/imports \
  --dummy-names legacy --async-callback \
  --features cm-async,cm-more-async-builtins \
  -t -o "$wat"

require_wat() {
  if ! grep -Fq -- "$1" "$wat"; then
    printf 'missing read-directory ABI fragment: %s\n' "$1" >&2
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
    printf 'read-directory ABI import has unexpected type: %s -> type %s\n' "$import_name" "$type_index" >&2
    exit 1
    ;;
  esac
}

# The generated type indices are stable for the pinned wasm-tools snapshot:
# type 3 is () -> i64, type 4 is (i32) -> i32, type 5 is
# (i32, i32, i32) -> i32, type 7 is (i32, i32) -> i32, and type 0 is
# (i32) -> nil. Keep these assertions close to the import names so a toolchain
# ABI change fails at the probe rather than being silently accepted.
require_wat '(type (;0;) (func (param i32)))'
require_wat '(type (;3;) (func (result i64)))'
require_wat '(type (;4;) (func (param i32) (result i32)))'
require_wat '(type (;5;) (func (param i32 i32 i32) (result i32)))'
require_wat '(type (;7;) (func (param i32 i32) (result i32)))'

require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][method]descriptor.read-directory" (func'
require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[stream-new-0][method]descriptor.read-directory" (func'
require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[stream-cancel-read-0][method]descriptor.read-directory" (func'
require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[stream-cancel-write-0][method]descriptor.read-directory" (func'
require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[stream-drop-readable-0][method]descriptor.read-directory" (func'
require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[stream-drop-writable-0][method]descriptor.read-directory" (func'
require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][stream-read-0][method]descriptor.read-directory" (func'
require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[future-new-1][method]descriptor.read-directory" (func'
require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[future-cancel-read-1][method]descriptor.read-directory" (func'
require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[future-cancel-write-1][method]descriptor.read-directory" (func'
require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[future-drop-readable-1][method]descriptor.read-directory" (func'
require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][future-read-1][method]descriptor.read-directory" (func'

require_import_type '[async-lower][method]descriptor.read-directory' 7
require_import_type '[stream-new-0][method]descriptor.read-directory' 3
require_import_type '[async-lower][stream-read-0][method]descriptor.read-directory' 5
require_import_type '[future-new-1][method]descriptor.read-directory' 3
require_import_type '[async-lower][future-read-1][method]descriptor.read-directory' 7
require_import_type '[future-drop-readable-1][method]descriptor.read-directory' 0

wasm-tools parse "$wat" -o "$core_wasm"
wasm-tools component new "$core_wasm" -o "$component"
wasm-tools component wit "$component" > "$component_wit"

grep -Fq 'read-directory: async func() -> tuple<stream<directory-entry>, future<result<_, error-code>>>;' "$component_wit"
grep -Fq 'record directory-entry {' "$component_wit"
grep -Fq 'type: descriptor-type,' "$component_wit"
grep -Fq 'name: string,' "$component_wit"

printf 'WASI G6.2 read-directory ABI probe passed\n'
