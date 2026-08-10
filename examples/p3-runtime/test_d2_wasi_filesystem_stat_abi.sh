#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-stat.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-stat-cancel.wit"
clock_wit="$repo_root/examples/p3-runtime/wit/wasi-clocks-wall-clock.wit"
upstream_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-stat.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-stat-cancel.core.wat"

expected_current_version='wasm-tools 1.255.0 (76e20611d 2026-07-30)'
expected_current_sha256=6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013
expected_clock_sha256=6c6d8706c22c3f7548cfddf87cd176d37a6accc4eb8cc03d7b4fb2eaa06019e6
expected_mirror_sha256=4f5ee39cad9280cdcd308550978ba0006503f5952d61304fc5130a74df5ea121
expected_cancel_mirror_sha256=caf50d3fb78cca697ed05cbe02aa86794359ba1e8d576ba5156857d2ffb5af28
expected_upstream_sha256=8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f

current_wasm_tools=wasm-tools
command -v "$current_wasm_tools" >/dev/null || {
  printf 'missing executable: %s\n' "$current_wasm_tools" >&2
  exit 1
}

for path in "$wit" "$cancel_wit" "$clock_wit" "$upstream_wit"; do
  [[ -f "$path" ]] || {
    printf 'missing WIT probe input: %s\n' "$path" >&2
    exit 1
  }
done

for path in "$core_wat" "$cancel_core_wat"; do
  [[ -f "$path" ]] || {
    printf 'missing hand-authored Core WAT probe: %s\n' "$path" >&2
    exit 1
  }
done

actual_current_version=$($current_wasm_tools --version)
actual_current_sha256=$(sha256sum "$(command -v "$current_wasm_tools")" | awk '{print $1}')
[[ "$actual_current_version" == "$expected_current_version" ]] || {
  printf 'wasm-tools version mismatch: expected %s, got %s\n' \
    "$expected_current_version" "$actual_current_version" >&2
  exit 1
}
[[ "$actual_current_sha256" == "$expected_current_sha256" ]] || {
  printf 'wasm-tools hash mismatch: expected %s, got %s\n' \
    "$expected_current_sha256" "$actual_current_sha256" >&2
  exit 1
}

[[ "$(sha256sum "$clock_wit" | awk '{print $1}')" == "$expected_clock_sha256" ]] || {
  printf 'wall-clock WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$wit" | awk '{print $1}')" == "$expected_mirror_sha256" ]] || {
  printf 'filesystem stat WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$cancel_wit" | awk '{print $1}')" == "$expected_cancel_mirror_sha256" ]] || {
  printf 'filesystem stat cancel WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$upstream_wit" | awk '{print $1}')" == "$expected_upstream_sha256" ]] || {
  printf 'pinned filesystem WIT source hash changed\n' >&2
  exit 1
}

grep -Fq 'package wasi:filesystem@0.3.0-rc-2025-09-16;' "$wit"
grep -Fq 'use wasi:clocks/wall-clock@0.3.0-rc-2025-09-16.{datetime};' "$wit"
grep -Fq 'record descriptor-stat' "$wit"
grep -Fq 'stat: async func() -> result<descriptor-stat, error-code>;' "$wit"
grep -Fq 'run: async func(file: own<descriptor>) -> result<descriptor-stat, error-code>;' "$wit"
grep -Fq 'world stat-probe' "$wit"
grep -Fq 'world stat-cancel-probe' "$cancel_wit"
grep -Fq 'cancel: async func();' "$cancel_wit"

tmp_dir=$(mktemp -d /tmp/do-d2-filesystem-stat-abi.XXXXXX)
trap 'rm -rf -- "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/regular/deps/clocks" "$tmp_dir/cancel/deps/clocks"
cp "$wit" "$tmp_dir/regular/wasi-filesystem-stat.wit"
cp "$cancel_wit" "$tmp_dir/cancel/wasi-filesystem-stat-cancel.wit"
cp "$clock_wit" "$tmp_dir/regular/deps/clocks/wall-clock.wit"
cp "$clock_wit" "$tmp_dir/cancel/deps/clocks/wall-clock.wit"

"$current_wasm_tools" component embed "$tmp_dir/regular" --world stat-probe \
  --dummy-names legacy --async-callback \
  --features cm-async,cm-more-async-builtins -t >"$tmp_dir/current-regular.wat"
"$current_wasm_tools" component embed "$tmp_dir/cancel" --world stat-cancel-probe \
  --dummy-names legacy --async-callback \
  --features cm-async,cm-more-async-builtins -t >"$tmp_dir/current-cancel.wat"

require_text() {
  local file="$1"
  local fragment="$2"
  grep -Fq -- "$fragment" "$file" || {
    printf 'missing ABI fragment in %s: %s\n' "$file" "$fragment" >&2
    exit 1
  }
}

require_regular_dummy() {
  local file="$1"
  for fragment in \
    '(type (;0;) (func (param i32 i32) (result i32)))' \
    '(type (;1;) (func (param i32)))' \
    '(type (;2;) (func))' \
    '(type (;3;) (func (result i32)))' \
    '(type (;4;) (func (param i32 i32)))' \
    '(type (;5;) (func (param i32) (result i32)))' \
    '(type (;6;) (func (param i32 i32 i64 i64 i32 i64 i32 i32 i64 i32 i32 i64 i32)))' \
    '(import "wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][method]descriptor.stat"' \
    '(import "wasi:filesystem/types@0.3.0-rc-2025-09-16" "[resource-drop]descriptor"' \
    '(import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16" "[task-return]run"'; do
    require_text "$file" "$fragment"
  done
  [[ $(grep -cF '[async-lower][method]' "$file") -eq 1 ]] || {
    printf 'unexpected filesystem async method count in %s\n' "$file" >&2
    exit 1
  }
}

require_cancel_dummy() {
  local file="$1"
  require_regular_dummy "$file"
  for fragment in \
    '(type (;7;) (func (param i32 i32 i32) (result i32)))' \
    '(type (;8;) (func (param i32 i32 i32 i32) (result i32)))' \
    '(import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16" "[task-return]cancel"' \
    '(import "$root" "[subtask-cancel]"'; do
    require_text "$file" "$fragment"
  done
}

require_core_layout() {
  local file="$1"
  for fragment in \
    '(type $method (func (param i32 i32) (result i32)))' \
    '(type $task-return-stat (func (param i32 i32 i64 i64 i32 i64 i32 i32 i64 i32 i32 i64 i32)))' \
    '8 result-tag:u8, 16 descriptor-type:u8' \
    '112 status:i32, 116 callback-subtask-handle:i32.' \
    ';; [stat-result-area]' \
    ';; [stat-option-presence]' \
    ';; [stat-ready]' \
    ';; [stat-pending]' \
    ';; [stat-error]' \
    ';; [descriptor-drop]'; do
    require_text "$file" "$fragment"
  done
  if [[ "$file" == "$cancel_core_wat" ]]; then
    require_text "$file" ';; [subtask-cancel]'
  fi
}

require_regular_dummy "$tmp_dir/current-regular.wat"
require_cancel_dummy "$tmp_dir/current-cancel.wat"
require_core_layout "$core_wat"
require_core_layout "$cancel_core_wat"

core_tmp="$tmp_dir/stat.core.wasm"
cancel_core_tmp="$tmp_dir/stat-cancel.core.wasm"
"$current_wasm_tools" parse "$core_wat" -o "$core_tmp"
"$current_wasm_tools" validate --features cm-async,cm-more-async-builtins "$core_tmp"
"$current_wasm_tools" parse "$cancel_core_wat" -o "$cancel_core_tmp"
"$current_wasm_tools" validate --features cm-async,cm-more-async-builtins "$cancel_core_tmp"

assemble_component() {
  local input_dir="$1"
  local world="$2"
  local core="$3"
  local name="$4"
  local embedded="$tmp_dir/$name.embedded.wasm"
  local component="$tmp_dir/$name.component.wasm"
  local component_wat="$tmp_dir/$name.component.wat"
  local component_wit="$tmp_dir/$name.component.wit"

  "$current_wasm_tools" component embed "$input_dir" "$core" --world "$world" \
    --features cm-async,cm-more-async-builtins -o "$embedded"
  "$current_wasm_tools" component new --skip-validation "$embedded" -o "$component"
  "$current_wasm_tools" validate --features cm-async,cm-more-async-builtins "$component"
  "$current_wasm_tools" print "$component" >"$component_wat"
  "$current_wasm_tools" component wit "$component" >"$component_wit"

  require_text "$component_wat" '"[async-lower][method]descriptor.stat"'
  require_text "$component_wat" '"[resource-drop]descriptor"'
  require_text "$component_wat" '"[task-return]run"'
  [[ $(grep -cF '"[async-lower][method]' "$component_wat") -eq 2 ]] || {
    printf 'unexpected filesystem async method count in %s\n' "$component_wat" >&2
    exit 1
  }
  for forbidden in get-type get-flags sync read write; do
    if grep -Fq "descriptor.$forbidden" "$component_wat"; then
      printf 'unexpected filesystem method in %s: descriptor.%s\n' \
        "$component_wat" "$forbidden" >&2
      exit 1
    fi
  done
  require_text "$component_wit" 'stat: async func() -> result<descriptor-stat, error-code>;'
  require_text "$component_wit" 'run: async func(file: descriptor) -> result<descriptor-stat, error-code>;'
  if [[ "$world" == stat-cancel-probe ]]; then
    require_text "$component_wat" '"[async-lower][subtask-cancel]"'
    require_text "$component_wat" '"[task-return]cancel"'
    require_text "$component_wit" 'cancel: async func();'
  fi
}

assemble_component "$tmp_dir/regular" stat-probe "$core_tmp" stat
assemble_component "$tmp_dir/cancel" stat-cancel-probe "$cancel_core_tmp" stat-cancel

printf 'D2 filesystem descriptor.stat WIT ABI capability passed\n'
printf 'wasm-tools=%s sha256=%s\n' "$actual_current_version" "$actual_current_sha256"
printf 'clock-mirror-sha256=%s stat-mirror-sha256=%s cancel-mirror-sha256=%s upstream-sha256=%s\n' \
  "$expected_clock_sha256" "$expected_mirror_sha256" "$expected_cancel_mirror_sha256" "$expected_upstream_sha256"
printf 'async-import=[async-lower][method]descriptor.stat core=(i32,i32)->i32\n'
printf 'task-return-run=(i32,i32,i64,i64,i32,i64,i32,i32,i64,i32,i32,i64,i32)\n'
printf 'result=descriptor-stat|error-code record-with-three-option-datetime-fields\n'
printf 'resource-drop=[resource-drop]descriptor (i32)->nil\n'
printf 'cancel=[async-lower][subtask-cancel] plus task-return-cancel\n'
