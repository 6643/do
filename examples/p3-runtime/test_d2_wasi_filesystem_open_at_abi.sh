#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-open-at.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-open-at-cancel.wit"
upstream_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-open-at.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-open-at-cancel.core.wat"

expected_current_version='wasm-tools 1.255.0 (76e20611d 2026-07-30)'
expected_current_sha256=6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013
expected_mirror_sha256=1e5f9131387015c4e650a64e02bb9f112d8266f4755aa6b605af038407ef807a
expected_cancel_mirror_sha256=1c48fba03b569d91617efd834232fcccc553ca3001ffb0e0834b4134f93e4f52
expected_upstream_sha256=8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f

wasm_tools=${WASM_TOOLS:-wasm-tools}
command -v "$wasm_tools" >/dev/null || {
  printf 'missing executable: %s\n' "$wasm_tools" >&2
  exit 1
}
[[ "$($wasm_tools --version)" == "$expected_current_version" ]] || {
  printf 'wasm-tools version mismatch\n' >&2
  exit 1
}
[[ "$(sha256sum "$(command -v "$wasm_tools")" | awk '{print $1}')" == "$expected_current_sha256" ]] || {
  printf 'wasm-tools hash mismatch\n' >&2
  exit 1
}
[[ "$(sha256sum "$upstream_wit" | awk '{print $1}')" == "$expected_upstream_sha256" ]] || {
  printf 'pinned filesystem WIT source hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$wit" | awk '{print $1}')" == "$expected_mirror_sha256" ]] || {
  printf 'open-at WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$cancel_wit" | awk '{print $1}')" == "$expected_cancel_mirror_sha256" ]] || {
  printf 'open-at cancel WIT mirror hash changed\n' >&2
  exit 1
}

for path in "$wit" "$cancel_wit" "$upstream_wit" "$core_wat" "$cancel_core_wat"; do
  [[ -f "$path" ]] || {
    printf 'missing open-at ABI input: %s\n' "$path" >&2
    exit 1
  }
done

grep -Fq 'package wasi:filesystem@0.3.0-rc-2025-09-16;' "$wit"
grep -Fq 'open-at: async func(' "$wit"
grep -Fq ') -> result<descriptor, error-code>;' "$wit"
grep -Fq 'run: async func(' "$wit"
grep -Fq ') -> result<own<descriptor>, error-code>;' "$wit"
grep -Fq 'world open-at-probe' "$wit"
grep -Fq 'world open-at-cancel-probe' "$cancel_wit"
grep -Fq 'cancel: async func();' "$cancel_wit"

tmp_dir=$(mktemp -d /tmp/do-d2-filesystem-open-at-abi.XXXXXX)
trap 'rm -rf -- "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/regular" "$tmp_dir/cancel"
cp "$wit" "$tmp_dir/regular/wasi-filesystem-open-at.wit"
cp "$cancel_wit" "$tmp_dir/cancel/wasi-filesystem-open-at-cancel.wit"

"$wasm_tools" component embed "$tmp_dir/regular" --world open-at-probe \
  --dummy-names legacy --async-callback \
  --features cm-async,cm-more-async-builtins -t >"$tmp_dir/current-regular.wat"
"$wasm_tools" component embed "$tmp_dir/cancel" --world open-at-cancel-probe \
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

require_text "$tmp_dir/current-regular.wat" '(type (;0;) (func (param i32 i32) (result i32)))'
require_text "$tmp_dir/current-regular.wat" '(type (;4;) (func (param i32 i32)))'
require_text "$tmp_dir/current-regular.wat" '(type (;6;) (func (param i32 i32 i32 i32 i32 i32) (result i32)))'
require_text "$tmp_dir/current-regular.wat" '[async-lower][method]descriptor.open-at'
require_text "$tmp_dir/current-regular.wat" '[resource-drop]descriptor'
require_text "$tmp_dir/current-regular.wat" '[task-return]run'
require_text "$tmp_dir/current-cancel.wat" '[subtask-cancel]'
require_text "$tmp_dir/current-cancel.wat" '[task-return]cancel'
[[ "$(grep -cF '[async-lower][method]' "$tmp_dir/current-regular.wat")" -eq 1 ]]
[[ "$(grep -cF '[async-lower][method]' "$tmp_dir/current-cancel.wat")" -eq 1 ]]

require_core_layout() {
  local file="$1"
  for fragment in \
    '(type $method (func (param i32 i32) (result i32)))' \
    '(type $task-return-open-at (func (param i32 i32)))' \
    '(type $async-run (func (param i32 i32 i32 i32 i32 i32) (result i32)))' \
    '[open-at-call]' \
    '[open-at-result-area]' \
    '[open-at-path-copy]' \
    '[open-at-ready]' \
    '[open-at-pending]' \
    '[open-at-error]' \
    '[descriptor-drop]'; do
    require_text "$file" "$fragment"
  done
  if [[ "$file" == "$cancel_core_wat" ]]; then
    require_text "$file" '[subtask-cancel]'
    require_text "$file" '[task-return]cancel'
  fi
}

require_core_layout "$core_wat"
require_core_layout "$cancel_core_wat"

core_tmp="$tmp_dir/open-at.core.wasm"
cancel_core_tmp="$tmp_dir/open-at-cancel.core.wasm"
"$wasm_tools" parse "$core_wat" -o "$core_tmp"
"$wasm_tools" validate --features cm-async,cm-more-async-builtins "$core_tmp"
"$wasm_tools" parse "$cancel_core_wat" -o "$cancel_core_tmp"
"$wasm_tools" validate --features cm-async,cm-more-async-builtins "$cancel_core_tmp"

assemble_component() {
  local input_dir="$1"
  local world="$2"
  local core="$3"
  local name="$4"
  local embedded="$tmp_dir/$name.embedded.wasm"
  local component="$tmp_dir/$name.component.wasm"
  local component_wat="$tmp_dir/$name.component.wat"
  local component_wit="$tmp_dir/$name.component.wit"

  "$wasm_tools" component embed "$input_dir" "$core" --world "$world" \
    --features cm-async,cm-more-async-builtins -o "$embedded"
  "$wasm_tools" component new --skip-validation "$embedded" -o "$component"
  "$wasm_tools" validate --features cm-async,cm-more-async-builtins "$component"
  "$wasm_tools" print "$component" >"$component_wat"
  "$wasm_tools" component wit "$component" >"$component_wit"

  require_text "$component_wat" '"[async-lower][method]descriptor.open-at"'
  require_text "$component_wat" '"[resource-drop]descriptor"'
  require_text "$component_wat" '"[task-return]run"'
  [[ "$(grep -cF '"[async-lower][method]' "$component_wat")" -eq 2 ]] || {
    printf 'unexpected filesystem async method count in %s\n' "$component_wat" >&2
    exit 1
  }
  for forbidden in stat get-type get-flags sync sync-data metadata-hash stat-at; do
    if grep -Fq "descriptor.$forbidden" "$component_wat"; then
      printf 'unexpected filesystem method in %s: descriptor.%s\n' "$component_wat" "$forbidden" >&2
      exit 1
    fi
  done
  require_text "$component_wit" 'open-at: async func(path-flags: path-flags, path: string, open-flags: open-flags, descriptor-flags: descriptor-flags) -> result<descriptor, error-code>;'
  require_text "$component_wit" 'run: async func(root: descriptor, path-flags: path-flags, path: string, open-flags: open-flags, descriptor-flags: descriptor-flags) -> result<descriptor, error-code>;'
  if [[ "$world" == open-at-cancel-probe ]]; then
    require_text "$component_wat" '"[async-lower][subtask-cancel]"'
    require_text "$component_wat" '"[task-return]cancel"'
    require_text "$component_wit" 'cancel: async func();'
  fi
}

assemble_component "$tmp_dir/regular" open-at-probe "$core_tmp" open-at
assemble_component "$tmp_dir/cancel" open-at-cancel-probe "$cancel_core_tmp" open-at-cancel

printf 'D2 filesystem descriptor.open-at WIT ABI capability passed\n'
printf 'wasm-tools=%s sha256=%s\n' "$($wasm_tools --version)" "$(sha256sum "$(command -v "$wasm_tools")" | awk '{print $1}')"
printf 'open-at-mirror-sha256=%s cancel-mirror-sha256=%s upstream-sha256=%s\n' \
  "$expected_mirror_sha256" "$expected_cancel_mirror_sha256" "$expected_upstream_sha256"
printf 'async-import=[async-lower][method]descriptor.open-at core=(i32,i32)->i32 indirect-params\n'
printf 'indirect-params=descriptor:i32,path-flags:i32,path-ptr:i32,path-len:i32,open-flags:i32,descriptor-flags:i32\n'
printf 'task-return-run=(i32,i32) result=descriptor|error-code\n'
printf 'resource-drop=[resource-drop]descriptor (i32)->nil\n'
printf 'cancel=[async-lower][subtask-cancel] + [task-return]cancel (test-only)\n'
