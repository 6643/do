#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-stat-at.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-stat-at-cancel.wit"
clock_wit="$repo_root/examples/p3-runtime/wit/wasi-clocks-wall-clock.wit"
upstream_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-stat-at.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-stat-at-cancel.core.wat"

expected_clock_sha256=6c6d8706c22c3f7548cfddf87cd176d37a6accc4eb8cc03d7b4fb2eaa06019e6
expected_mirror_sha256=92afa427efedc960fd60ce2edbd3ced26521225ae8857377554956646a1059bd
expected_cancel_mirror_sha256=420fb95fae7505e568414e55f19dc2f89f5b32e015e8d999166e38b48e4a4a49
expected_upstream_sha256=8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f

for path in "$wit" "$cancel_wit" "$clock_wit" "$upstream_wit" "$core_wat" "$cancel_core_wat"; do
  [[ -f "$path" ]] || {
    printf 'missing stat-at ABI probe input: %s\n' "$path" >&2
    exit 1
  }
done

[[ "$(sha256sum "$clock_wit" | awk '{print $1}')" == "$expected_clock_sha256" ]] || {
  printf 'wall-clock WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$wit" | awk '{print $1}')" == "$expected_mirror_sha256" ]] || {
  printf 'filesystem stat-at WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$cancel_wit" | awk '{print $1}')" == "$expected_cancel_mirror_sha256" ]] || {
  printf 'filesystem stat-at cancel WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$upstream_wit" | awk '{print $1}')" == "$expected_upstream_sha256" ]] || {
  printf 'pinned filesystem WIT source hash changed\n' >&2
  exit 1
}

grep -Fq 'package wasi:filesystem@0.3.0-rc-2025-09-16;' "$wit"
grep -Fq 'use wasi:clocks/wall-clock@0.3.0-rc-2025-09-16.{datetime};' "$wit"
grep -Fq 'flags path-flags' "$wit"
grep -Fq 'record descriptor-stat' "$wit"
grep -Fq 'stat-at: async func(' "$wit"
grep -Fq 'path-flags: path-flags' "$wit"
grep -Fq 'path: string' "$wit"
grep -Fq 'run: async func(' "$wit"
grep -Fq 'world stat-at-probe' "$wit"
grep -Fq 'world stat-at-cancel-probe' "$cancel_wit"
grep -Fq 'cancel: async func();' "$cancel_wit"

tmp_dir=$(mktemp -d /tmp/do-d2-filesystem-stat-at-abi.XXXXXX)
trap 'rm -rf -- "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/regular/deps/clocks" "$tmp_dir/cancel/deps/clocks"
cp "$wit" "$tmp_dir/regular/wasi-filesystem-stat-at.wit"
cp "$cancel_wit" "$tmp_dir/cancel/wasi-filesystem-stat-at-cancel.wit"
cp "$clock_wit" "$tmp_dir/regular/deps/clocks/wall-clock.wit"
cp "$clock_wit" "$tmp_dir/cancel/deps/clocks/wall-clock.wit"

"$toolchain_bin" embed-component-template "$tmp_dir/regular" stat-at-probe \
  --features component-async >"$tmp_dir/current-regular.wat"
"$toolchain_bin" embed-component-template "$tmp_dir/cancel" stat-at-cancel-probe \
  --features component-async >"$tmp_dir/current-cancel.wat"

require_text() {
  local file="$1"
  local fragment="$2"
  grep -Fq -- "$fragment" "$file" || {
    printf 'missing ABI fragment in %s: %s\n' "$file" "$fragment" >&2
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
  require_regex "$file" '\(type \(;[0-9]+;\) \(func \(param i32 i32 i32 i32 i32\) \(result i32\)\)\)'
  require_regex "$file" '\(type \(;[0-9]+;\) \(func \(param i32 i32 i64 i64 i32 i64 i32 i32 i64 i32 i32 i64 i32\)\)'
  require_text "$file" '(import "wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][method]descriptor.stat-at"'
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

require_core_layout() {
  local file="$1"
  for fragment in \
    '(type $method (func (param i32 i32 i32 i32 i32) (result i32)))' \
    '(type $task-return-stat-at (func (param i32 i32 i64 i64 i32 i64 i32 i32 i64 i32 i32 i64 i32)))' \
    '0 waitable:i32, 4 descriptor:i32, 8 path-flags:i32,' \
    '12 path-ptr:i32, 16 path-len:i32, 20 status:i32,' \
    '24 result-tag:u8, 32 descriptor-type:u8' \
    '132 callback-subtask-handle:i32.' \
    ';; [stat-at-result-area]' \
    ';; [stat-at-path-copy]' \
    ';; [stat-at-ready]' \
    ';; [stat-at-pending]' \
    ';; [stat-at-error]' \
    ';; [descriptor-drop]'; do
    require_text "$file" "$fragment"
  done
  if [[ "$file" == "$cancel_core_wat" ]]; then
    require_text "$file" ';; [subtask-cancel]'
  fi
}

require_dummy "$tmp_dir/current-regular.wat"
require_cancel_dummy "$tmp_dir/current-cancel.wat"
require_core_layout "$core_wat"
require_core_layout "$cancel_core_wat"

core_tmp="$tmp_dir/stat-at.core.wasm"
cancel_core_tmp="$tmp_dir/stat-at-cancel.core.wasm"
"$toolchain_bin" parse-core "$core_wat" -o "$core_tmp"
"$toolchain_bin" validate-core "$core_tmp"
"$toolchain_bin" parse-core "$cancel_core_wat" -o "$cancel_core_tmp"
"$toolchain_bin" validate-core "$cancel_core_tmp"

assemble_component() {
  local input_dir="$1"
  local world="$2"
  local core="$3"
  local name="$4"
  local embedded="$tmp_dir/$name.embedded.wasm"
  local component="$tmp_dir/$name.component.wasm"
  local component_wat="$tmp_dir/$name.component.wat"
  local component_wit="$tmp_dir/$name.component.wit"

  "$toolchain_bin" embed-component "$input_dir" "$core" "$world" -o "$embedded"
  "$toolchain_bin" new-component "$embedded" -o "$component"
  "$toolchain_bin" validate-component "$component" --features component-async
  "$toolchain_bin" print-component "$component" >"$component_wat"
  "$toolchain_bin" component-wit "$component" >"$component_wit"

  require_text "$component_wat" '"[async-lower][method]descriptor.stat-at"'
  require_text "$component_wat" '"[resource-drop]descriptor"'
  require_text "$component_wat" '"[task-return]run"'
  require_text "$component_wat" 'string-encoding=utf8 async'
  [[ $(grep -cF '"[async-lower][method]' "$component_wat") -eq 2 ]] || {
    printf 'unexpected filesystem async method count in %s\n' "$component_wat" >&2
    exit 1
  }
  for forbidden in stat get-type get-flags sync sync-data metadata-hash; do
    if grep -Fq "descriptor.$forbidden\"" "$component_wat"; then
      printf 'unexpected filesystem method in %s: descriptor.%s\n' \
        "$component_wat" "$forbidden" >&2
      exit 1
    fi
  done
  require_text "$component_wit" 'stat-at: async func(path-flags: path-flags, path: string) -> result<descriptor-stat, error-code>;'
  require_text "$component_wit" 'run: async func(file: descriptor, path-flags: path-flags, path: string) -> result<descriptor-stat, error-code>;'
  require_text "$component_wit" 'flags path-flags {'
  if [[ "$world" == stat-at-cancel-probe ]]; then
    require_text "$component_wat" '"[async-lower][subtask-cancel]"'
    require_text "$component_wat" '"[task-return]cancel"'
    require_text "$component_wit" 'cancel: async func();'
  fi
}

assemble_component "$tmp_dir/regular" stat-at-probe "$core_tmp" stat-at
assemble_component "$tmp_dir/cancel" stat-at-cancel-probe "$cancel_core_tmp" stat-at-cancel

printf 'D2 filesystem descriptor.stat-at WIT ABI capability passed\n'
printf 'toolchain-adapter=current-only\n'
printf 'clock-mirror-sha256=%s stat-at-mirror-sha256=%s cancel-mirror-sha256=%s upstream-sha256=%s\n' \
  "$expected_clock_sha256" "$expected_mirror_sha256" "$expected_cancel_mirror_sha256" "$expected_upstream_sha256"
printf 'async-import=[async-lower][method]descriptor.stat-at core=(i32,i32,i32,i32,i32)->i32\n'
printf 'arguments=descriptor:i32 path-flags:i32 path-ptr:i32 path-len:i32 result-area:i32\n'
printf 'task-return-run=(i32,i32,i64,i64,i32,i64,i32,i32,i64,i32,i32,i64,i32) result=descriptor-stat|error-code\n'
printf 'resource-drop=[resource-drop]descriptor (i32)->nil string-lowering=ptr,len utf8\n'
printf 'cancel=[async-lower][subtask-cancel] + [task-return]cancel (test-only)\n'
