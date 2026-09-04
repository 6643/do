#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-set-size.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-set-size-cancel.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-set-size.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-set-size-cancel.core.wat"
upstream_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit"

expected_mirror_sha256=f09241f8fcf4b94e1a684553b439b592f254c83c7d23a3708930040a2324c3f4
expected_cancel_mirror_sha256=7030161e35a18fe40220cb2701864141a00a6c8d897cdfc8291839f2b742cc67
expected_upstream_sha256=8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f

for path in "$wit" "$cancel_wit" "$core_wat" "$cancel_core_wat" "$upstream_wit"; do
  [[ -f "$path" ]] || {
    printf 'missing set-size ABI probe input: %s\n' "$path" >&2
    exit 1
  }
done

[[ "$(sha256sum "$wit" | awk '{print $1}')" == "$expected_mirror_sha256" ]] || {
  printf 'filesystem set-size WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$cancel_wit" | awk '{print $1}')" == "$expected_cancel_mirror_sha256" ]] || {
  printf 'filesystem set-size cancel WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$upstream_wit" | awk '{print $1}')" == "$expected_upstream_sha256" ]] || {
  printf 'pinned filesystem WIT source hash changed\n' >&2
  exit 1
}

grep -Fq 'package wasi:filesystem@0.3.0-rc-2025-09-16;' "$wit"
grep -Fq 'type filesize = u64;' "$wit"
grep -Fq 'set-size: async func(size: filesize) -> result<_, error-code>;' "$wit"
grep -Fq 'run: async func(file: own<descriptor>, size: filesize) -> result<_, error-code>;' "$wit"
grep -Fq 'world set-size-probe' "$wit"
grep -Fq 'world set-size-cancel-probe' "$cancel_wit"
grep -Fq 'cancel: async func();' "$cancel_wit"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-set-size-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

current_dummy="$tmp_dir/current-dummy.wat"
current_cancel_dummy="$tmp_dir/current-cancel-dummy.wat"
"$toolchain_bin" embed-component-template "$wit" set-size-probe \
  --features component-async >"$current_dummy"
"$toolchain_bin" embed-component-template "$cancel_wit" set-size-cancel-probe \
  --features component-async >"$current_cancel_dummy"

require_text() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || {
    printf 'missing ABI fragment in %s: %s\n' "$file" "$expected" >&2
    exit 1
  }
}

require_regex() {
  local file="$1"
  local expression="$2"
  grep -Eq -- "$expression" "$file" || {
    printf 'missing ABI pattern in %s: %s\n' "$file" "$expression" >&2
    exit 1
  }
}

require_dummy() {
  local file="$1"
  require_regex "$file" '\(type \(;[0-9]+;\) \(func \(param i32 i64 i32\) \(result i32\)\)'
  require_text "$file" '(import "wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][method]descriptor.set-size"'
  require_text "$file" '(import "wasi:filesystem/types@0.3.0-rc-2025-09-16" "[resource-drop]descriptor"'
  require_text "$file" '(import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16" "[task-return]run"'
  [[ $(grep -cF '[async-lower][method]' "$file") -eq 1 ]] || {
    printf 'unexpected filesystem async method count in %s\n' "$file" >&2
    exit 1
  }
}

require_cancel_dummy() {
  local file="$1"
  require_dummy "$file"
  require_text "$file" '(import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16" "[task-return]cancel"'
  require_text "$file" '(import "$root" "[subtask-cancel]"'
}

require_dummy "$current_dummy"
require_cancel_dummy "$current_cancel_dummy"

require_core_layout() {
  local file="$1"
  for fragment in \
    ';; [set-size-result-area]' \
    ';; [set-size-ready]' \
    ';; [set-size-pending]' \
    ';; [set-size-error]' \
    '(func $descriptor-drop'; do
    require_text "$file" "$fragment"
  done
  require_text "$file" '"wasi:filesystem/types@0.3.0-rc-2025-09-16"'
  require_text "$file" '"[async-lower][method]descriptor.set-size"'
  require_text "$file" '"[resource-drop]descriptor"'
  if [[ "$file" == "$cancel_core_wat" ]]; then
    require_text "$file" ';; [subtask-cancel]'
  fi
}

require_core_layout "$core_wat"
require_core_layout "$cancel_core_wat"

core_tmp="$tmp_dir/set-size.core.wasm"
cancel_core_tmp="$tmp_dir/set-size-cancel.core.wasm"
"$toolchain_bin" parse-core "$core_wat" -o "$core_tmp"
"$toolchain_bin" validate-core "$core_tmp"
"$toolchain_bin" parse-core "$cancel_core_wat" -o "$cancel_core_tmp"
"$toolchain_bin" validate-core "$cancel_core_tmp"

assemble_component() {
  local input_wit="$1"
  local world="$2"
  local core="$3"
  local name="$4"
  local embedded="$tmp_dir/$name.embedded.wasm"
  local component="$tmp_dir/$name.component.wasm"
  local component_wat="$tmp_dir/$name.component.wat"
  local component_wit="$tmp_dir/$name.component.wit"

  "$toolchain_bin" embed-component "$input_wit" "$core" "$world" -o "$embedded"
  "$toolchain_bin" new-component "$embedded" -o "$component"
  "$toolchain_bin" validate-component "$component" --features component-async
  "$toolchain_bin" print-component "$component" >"$component_wat"
  "$toolchain_bin" component-wit "$component" >"$component_wit"

  require_text "$component_wat" '"[async-lower][method]descriptor.set-size"'
  require_text "$component_wat" '"[resource-drop]descriptor"'
  require_text "$component_wat" '"[task-return]run"'
  [[ $(grep -cF '"[async-lower][method]' "$component_wat") -eq 2 ]] || {
    printf 'unexpected filesystem async method count in %s\n' "$component_wat" >&2
    exit 1
  }
  for forbidden in get-type get-flags sync sync-data stat stat-at metadata-hash metadata-hash-at open-at; do
    if grep -Fq "descriptor.$forbidden\"" "$component_wat"; then
      printf 'unexpected filesystem method in %s: descriptor.%s\n' \
        "$component_wat" "$forbidden" >&2
      exit 1
    fi
  done
  require_text "$component_wit" 'set-size: async func(size: filesize) -> result<_, error-code>;'
  require_text "$component_wit" 'run: async func(file: descriptor, size: filesize) -> result<_, error-code>;'
  require_text "$component_wit" 'type filesize = u64;'
  if [[ "$world" == set-size-cancel-probe ]]; then
    require_text "$component_wat" '"[async-lower][subtask-cancel]"'
    require_text "$component_wat" '"[task-return]cancel"'
    require_text "$component_wit" 'cancel: async func();'
  fi
}

assemble_component "$wit" set-size-probe "$core_tmp" set-size
assemble_component "$cancel_wit" set-size-cancel-probe "$cancel_core_tmp" set-size-cancel

printf 'D2 filesystem descriptor.set-size ABI capability passed\n'
printf 'toolchain-adapter=current-only\n'
printf 'set-size-mirror-sha256=%s cancel-mirror-sha256=%s upstream-sha256=%s\n' \
  "$expected_mirror_sha256" "$expected_cancel_mirror_sha256" "$expected_upstream_sha256"
printf 'async-import=[async-lower][method]descriptor.set-size core=(i32,i64,i32)->i32\n'
printf 'arguments=descriptor:i32 size:i64 result-area:i32 result=unit|error-code\n'
printf 'resource-drop=[resource-drop]descriptor (i32)->nil\n'
printf 'cancel=[async-lower][subtask-cancel] + [task-return]cancel (test-only)\n'
