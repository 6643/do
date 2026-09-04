#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-get-type.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-get-type.core.wat"
upstream_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit"

expected_mirror_sha256=31d0f12de7bb2c3caf63d618c55d030499460da4aa250d50cf9f2ff68e1bcb14
expected_upstream_sha256=8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f

for path in "$wit" "$core_wat" "$upstream_wit"; do
  [[ -f "$path" ]] || {
    printf 'missing ABI probe input: %s\n' "$path" >&2
    exit 1
  }
done

[[ "$(sha256sum "$wit" | awk '{print $1}')" == "$expected_mirror_sha256" ]] || {
  printf 'filesystem get-type WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$upstream_wit" | awk '{print $1}')" == "$expected_upstream_sha256" ]] || {
  printf 'pinned filesystem WIT source hash changed\n' >&2
  exit 1
}

grep -Fq 'package wasi:filesystem@0.3.0-rc-2025-09-16;' "$wit"
grep -Fq 'get-type: async func() -> result<descriptor-type, error-code>;' "$wit"
grep -Fq 'run: async func(directory: own<descriptor>) -> result<descriptor-type, error-code>;' "$wit"
grep -Fq 'world get-type-probe' "$wit"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-get-type-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

current_dummy="$tmp_dir/current-dummy.wat"
core_wasm="$tmp_dir/get-type.core.wasm"
embedded="$tmp_dir/get-type.embedded.wasm"
component="$tmp_dir/get-type.component.wasm"
component_wat="$tmp_dir/get-type.component.wat"
component_wit="$tmp_dir/get-type.component.wit"

"$toolchain_bin" embed-component-template "$wit" get-type-probe \
  --features component-async >"$current_dummy"

require_text() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || {
    printf 'missing ABI fragment in %s: %s\n' "$file" "$text" >&2
    exit 1
  }
}

require_canonical_dummy() {
  local file="$1"
  for fragment in \
    '(type (;0;) (func (param i32 i32) (result i32)))' \
    '(type (;1;) (func (param i32)))' \
    '(type (;2;) (func))' \
    '(type (;3;) (func (result i32)))' \
    '(type (;4;) (func (param i32 i32)))' \
    '(type (;5;) (func (param i32) (result i32)))' \
    '(type (;6;) (func (param i32 i32 i32) (result i32)))' \
    '(type (;7;) (func (param i32 i32 i32 i32) (result i32)))' \
    '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][method]descriptor.get-type"' \
    '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[resource-drop]descriptor"' \
    '"[export]$root" "[task-cancel]"' \
    '"$root" "[backpressure-inc]"' \
    '"$root" "[backpressure-dec]"' \
    '"$root" "[waitable-set-new]"' \
    '"$root" "[waitable-set-wait]"' \
    '"$root" "[waitable-set-poll]"' \
    '"$root" "[waitable-set-drop]"' \
    '"$root" "[waitable-join]"' \
    '"$root" "[thread-yield]"' \
    '"$root" "[subtask-drop]"' \
    '"$root" "[subtask-cancel]"' \
    '"$root" "[context-get-0]"' \
    '"$root" "[context-set-0]"' \
    '"[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16" "[task-return]run"' \
    '"[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run"' \
    '"[callback][async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run"'; do
    require_text "$file" "$fragment"
  done
}

require_canonical_dummy "$current_dummy"

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" \
  get-type-probe -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async
"$toolchain_bin" print-component "$component" >"$component_wat"
"$toolchain_bin" component-wit "$component" >"$component_wit"

require_text "$core_wat" ';; [get-type-call]'
require_text "$core_wat" ';; [get-type-ready]'
require_text "$core_wat" ';; [get-type-pending]'
require_text "$core_wat" ';; [get-type-error]'
require_text "$core_wat" ';; [get-type-cancel]'
require_text "$core_wat" ';; [descriptor-drop]'
require_text "$core_wat" ';; [result-layout]'
require_text "$core_wat" '"wasi:filesystem/types@0.3.0-rc-2025-09-16"'
require_text "$core_wat" '"[async-lower][method]descriptor.get-type"'
require_text "$core_wat" '(func $get-type (type $method))'
require_text "$core_wat" '"[resource-drop]descriptor"'
require_text "$core_wat" '(func $descriptor-drop (type $resource-drop))'
require_text "$component_wat" '"[async-lower][method]descriptor.get-type"'
require_text "$component_wat" '"[resource-drop]descriptor"'
require_text "$component_wat" '"[task-return]run"'
require_text "$component_wat" 'result $descriptor-type (error $error-code)'
require_text "$component_wit" 'get-type: async func() -> result<descriptor-type, error-code>;'
require_text "$component_wit" 'run: async func(directory: descriptor) -> result<descriptor-type, error-code>;'

printf 'D2 filesystem descriptor.get-type ABI passed\n'
printf 'toolchain-adapter=current-only\n'
printf 'mirror-sha256=%s upstream-sha256=%s\n' "$expected_mirror_sha256" "$expected_upstream_sha256"
printf 'async-import=[async-lower][method]descriptor.get-type core=(i32,i32)->i32\n'
printf 'result=descriptor-type|error-code tag/layout=component-variant\n'
printf 'resource-drop=[resource-drop]descriptor (i32)->nil\n'
