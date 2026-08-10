#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-metadata-hash-at.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-metadata-hash-at-cancel.wit"
upstream_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-metadata-hash-at.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-metadata-hash-at-cancel.core.wat"

expected_current_version='wasm-tools 1.255.0 (76e20611d 2026-07-30)'
expected_current_sha256=6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013
expected_upstream_sha256=8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f
expected_mirror_sha256=95e24b70eeed89407706c18a6e4cd13a8bc4dce72d1e56638436b03287d23412
expected_cancel_mirror_sha256=aca9c5933786a00a2dd20b1ad1ddbb6d0a79ab5b3bdbd5bd61e14b100a3b6e0a

current_wasm_tools=wasm-tools
command -v "$current_wasm_tools" >/dev/null || {
  printf 'missing executable: %s\n' "$current_wasm_tools" >&2
  exit 1
}

for path in "$wit" "$cancel_wit" "$upstream_wit" "$core_wat" "$cancel_core_wat"; do
  [[ -f "$path" ]] || {
    printf 'missing ABI probe input: %s\n' "$path" >&2
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

[[ "$(sha256sum "$wit" | awk '{print $1}')" == "$expected_mirror_sha256" ]] || {
  printf 'filesystem metadata-hash-at WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$cancel_wit" | awk '{print $1}')" == "$expected_cancel_mirror_sha256" ]] || {
  printf 'filesystem metadata-hash-at cancel WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$upstream_wit" | awk '{print $1}')" == "$expected_upstream_sha256" ]] || {
  printf 'pinned filesystem WIT source hash changed\n' >&2
  exit 1
}

grep -Fq 'package wasi:filesystem@0.3.0-rc-2025-09-16;' "$wit"
grep -Fq 'flags path-flags' "$wit"
grep -Fq 'symlink-follow' "$wit"
grep -Fq 'metadata-hash-at: async func(' "$wit"
grep -Fq 'path-flags: path-flags' "$wit"
grep -Fq 'path: string' "$wit"
grep -Fq 'run: async func(' "$wit"
grep -Fq 'file: own<descriptor>' "$wit"
grep -Fq 'world metadata-hash-at-probe' "$wit"
grep -Fq 'world metadata-hash-at-cancel-probe' "$cancel_wit"
grep -Fq 'cancel: async func();' "$cancel_wit"

tmp_dir=$(mktemp -d /tmp/do-d2-filesystem-metadata-hash-at-abi.XXXXXX)
mkdir -p "$tmp_dir/regular" "$tmp_dir/cancel"
cp "$wit" "$tmp_dir/regular/wasi-filesystem-metadata-hash-at.wit"
cp "$cancel_wit" "$tmp_dir/cancel/wasi-filesystem-metadata-hash-at-cancel.wit"

"$current_wasm_tools" component embed "$tmp_dir/regular" --world metadata-hash-at-probe \
  --dummy-names legacy --async-callback \
  --features cm-async,cm-more-async-builtins -t >"$tmp_dir/current-regular.wat"
"$current_wasm_tools" component embed "$tmp_dir/cancel" --world metadata-hash-at-cancel-probe \
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

require_dummy() {
  local file="$1"
  for fragment in \
    '(type (;0;) (func (param i32 i32 i32 i32 i32) (result i32)))' \
    '(type (;1;) (func (param i32)))' \
    '(type (;6;) (func (param i32) (result i32)))' \
    '(type (;7;) (func (param i32 i64 i64)))' \
    '(import "wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][method]descriptor.metadata-hash-at"' \
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
  require_dummy "$file"
  require_text "$file" '(import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16" "[task-return]cancel"'
  require_text "$file" '(import "$root" "[subtask-cancel]"'
}

require_core_layout() {
  local file="$1"
  for fragment in \
    '(type $method (func (param i32 i32 i32 i32 i32) (result i32)))' \
    '(type $task-return-metadata-hash-at (func (param i32 i64 i64)))' \
    '0 waitable:i32, 4 descriptor:i32, 8 path-flags:i32,' \
    '12 path-ptr:i32, 16 path-len:i32, 20 status:i32,' \
    '24 result-tag:u8, 32 lower:u64, 40 upper:u64,' \
    ';; [metadata-hash-at-result-area]' \
    ';; [metadata-hash-at-ready]' \
    ';; [metadata-hash-at-error]' \
    ';; [metadata-hash-at-pending]' \
    ';; [descriptor-drop]' \
    '"[async-lower][method]descriptor.metadata-hash-at"'; do
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

for path in "$core_wat" "$cancel_core_wat"; do
  "$current_wasm_tools" parse "$path" -o "$tmp_dir/$(basename "$path" .wat).wasm"
  "$current_wasm_tools" validate --features cm-async,cm-more-async-builtins \
    "$tmp_dir/$(basename "$path" .wat).wasm"
done

assemble_component() {
  local input_dir="$1"
  local world="$2"
  local core="$3"
  local name="$4"
  local core_wasm="$tmp_dir/$name.core.wasm"
  local embedded="$tmp_dir/$name.embedded.wasm"
  local component="$tmp_dir/$name.component.wasm"
  local component_wat="$tmp_dir/$name.component.wat"
  local component_wit="$tmp_dir/$name.component.wit"

  "$current_wasm_tools" parse "$core" -o "$core_wasm"
  "$current_wasm_tools" component embed "$input_dir" "$core_wasm" --world "$world" \
    --features cm-async,cm-more-async-builtins -o "$embedded"
  "$current_wasm_tools" component new --skip-validation "$embedded" -o "$component"
  "$current_wasm_tools" validate --features cm-async,cm-more-async-builtins "$component"
  "$current_wasm_tools" print "$component" >"$component_wat"
  "$current_wasm_tools" component wit "$component" >"$component_wit"

  require_text "$component_wat" '"[async-lower][method]descriptor.metadata-hash-at"'
  require_text "$component_wat" '"[resource-drop]descriptor"'
  require_text "$component_wat" '"[task-return]run"'
  require_text "$component_wat" 'string-encoding=utf8 async'
  [[ $(grep -cF '"[async-lower][method]' "$component_wat") -eq 2 ]] || {
    printf 'unexpected filesystem async method count in %s\n' "$component_wat" >&2
    exit 1
  }
  for forbidden in metadata-hash stat stat-at get-type get-flags sync sync-data; do
    if grep -Fq "descriptor.$forbidden\"" "$component_wat"; then
      printf 'unexpected filesystem method in %s: descriptor.%s\n' \
        "$component_wat" "$forbidden" >&2
      exit 1
    fi
  done
  require_text "$component_wit" 'metadata-hash-at: async func(path-flags: path-flags, path: string) -> result<metadata-hash-value, error-code>;'
  require_text "$component_wit" 'run: async func(file: descriptor, path-flags: path-flags, path: string) -> result<metadata-hash-value, error-code>;'
  require_text "$component_wit" 'flags path-flags {'
  if [[ "$world" == metadata-hash-at-cancel-probe ]]; then
    require_text "$component_wat" '"[async-lower][subtask-cancel]"'
    require_text "$component_wat" '"[task-return]cancel"'
    require_text "$component_wit" 'cancel: async func();'
  fi
}

assemble_component "$tmp_dir/regular" metadata-hash-at-probe "$core_wat" metadata-hash-at
assemble_component "$tmp_dir/cancel" metadata-hash-at-cancel-probe "$cancel_core_wat" metadata-hash-at-cancel

printf 'D2 filesystem descriptor.metadata-hash-at WIT ABI capability passed\n'
printf 'wasm-tools=%s sha256=%s\n' "$actual_current_version" "$actual_current_sha256"
printf 'metadata-hash-at-mirror-sha256=%s cancel-mirror-sha256=%s upstream-sha256=%s\n' \
  "$expected_mirror_sha256" "$expected_cancel_mirror_sha256" "$expected_upstream_sha256"
printf 'async-import=[async-lower][method]descriptor.metadata-hash-at core=(i32,i32,i32,i32,i32)->i32\n'
printf 'arguments=descriptor:i32 path-flags:i32 path-ptr:i32 path-len:i32 result-area:i32\n'
printf 'task-return-run=(i32,i64,i64) result=metadata-hash-value|error-code lower:u64 upper:u64\n'
printf 'resource-drop=[resource-drop]descriptor (i32)->nil string-lowering=ptr,len utf8\n'
printf 'cancel=[async-lower][subtask-cancel] + [task-return]cancel (test-only)\n'
