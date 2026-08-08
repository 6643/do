#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-sync.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-sync-cancel.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-sync.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-sync-cancel.core.wat"
upstream_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit"

expected_current_version=${WASM_TOOLS_EXPECT_VERSION:-'wasm-tools 1.255.0 (76e20611d 2026-07-30)'}
expected_current_sha256=${WASM_TOOLS_EXPECT_SHA256:-6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013}
expected_legacy_version=${WASM_TOOLS_LEGACY_EXPECT_VERSION:-'wasm-tools 1.254.0 (bb58fdf91 2026-07-20)'}
expected_legacy_sha256=${WASM_TOOLS_LEGACY_EXPECT_SHA256:-cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6}
expected_mirror_sha256=18ce7dc9efb991cd8e5f945797aea73edeed79f0cfc51ea664cb81537e54e719
expected_cancel_mirror_sha256=9898cd734708a2ab14760da706d69063e5cd6262a5e03d07d8eedd8074745f36
expected_upstream_sha256=8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f

current_wasm_tools=${WASM_TOOLS:-wasm-tools}
legacy_wasm_tools=${LEGACY_WASM_TOOLS:-/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools}

resolve_tool() {
  local requested="$1"
  if [[ "$requested" == */* ]]; then
    [[ -x "$requested" ]] || {
      printf 'missing executable: %s\n' "$requested" >&2
      exit 1
    }
    printf '%s\n' "$requested"
    return
  fi
  command -v "$requested"
}

current_wasm_tools=$(resolve_tool "$current_wasm_tools")
legacy_wasm_tools=$(resolve_tool "$legacy_wasm_tools")

for path in "$wit" "$cancel_wit" "$core_wat" "$cancel_core_wat" "$upstream_wit"; do
  [[ -f "$path" ]] || {
    printf 'missing ABI probe input: %s\n' "$path" >&2
    exit 1
  }
done

actual_current_version=$("$current_wasm_tools" --version)
actual_current_sha256=$(sha256sum "$current_wasm_tools" | awk '{print $1}')
[[ "$actual_current_version" == "$expected_current_version" ]] || {
  printf 'current wasm-tools version mismatch: expected %s, got %s\n' \
    "$expected_current_version" "$actual_current_version" >&2
  exit 1
}
[[ "$actual_current_sha256" == "$expected_current_sha256" ]] || {
  printf 'current wasm-tools hash mismatch: expected %s, got %s\n' \
    "$expected_current_sha256" "$actual_current_sha256" >&2
  exit 1
}

actual_legacy_version=$("$legacy_wasm_tools" --version)
actual_legacy_sha256=$(sha256sum "$legacy_wasm_tools" | awk '{print $1}')
[[ "$actual_legacy_version" == "$expected_legacy_version" ]] || {
  printf 'legacy wasm-tools version mismatch: expected %s, got %s\n' \
    "$expected_legacy_version" "$actual_legacy_version" >&2
  exit 1
}
[[ "$actual_legacy_sha256" == "$expected_legacy_sha256" ]] || {
  printf 'legacy wasm-tools hash mismatch: expected %s, got %s\n' \
    "$expected_legacy_sha256" "$actual_legacy_sha256" >&2
  exit 1
}

[[ "$(sha256sum "$wit" | awk '{print $1}')" == "$expected_mirror_sha256" ]] || {
  printf 'filesystem sync WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$cancel_wit" | awk '{print $1}')" == "$expected_cancel_mirror_sha256" ]] || {
  printf 'filesystem sync cancel WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$upstream_wit" | awk '{print $1}')" == "$expected_upstream_sha256" ]] || {
  printf 'pinned filesystem WIT source hash changed\n' >&2
  exit 1
}

grep -Fq 'package wasi:filesystem@0.3.0-rc-2025-09-16;' "$wit"
grep -Fq 'sync: async func() -> result<_, error-code>;' "$wit"
grep -Fq 'run: async func(file: own<descriptor>) -> result<_, error-code>;' "$wit"
grep -Fq 'world sync-probe' "$wit"
grep -Fq 'world sync-cancel-probe' "$cancel_wit"
grep -Fq 'cancel: async func();' "$cancel_wit"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-sync-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

current_dummy="$tmp_dir/current-dummy.wat"
legacy_dummy="$tmp_dir/legacy-dummy.wat"

"$current_wasm_tools" component embed "$wit" --world sync-probe \
  --dummy-names legacy --async-callback \
  --features cm-async,cm-more-async-builtins -t >"$current_dummy"
"$legacy_wasm_tools" component embed "$wit" --world sync-probe \
  --dummy-names legacy --async-callback \
  --features cm-async,cm-more-async-builtins -t >"$legacy_dummy"

current_cancel_dummy="$tmp_dir/current-cancel-dummy.wat"
legacy_cancel_dummy="$tmp_dir/legacy-cancel-dummy.wat"
"$current_wasm_tools" component embed "$cancel_wit" --world sync-cancel-probe \
  --dummy-names legacy --async-callback \
  --features cm-async,cm-more-async-builtins -t >"$current_cancel_dummy"
"$legacy_wasm_tools" component embed "$cancel_wit" --world sync-cancel-probe \
  --dummy-names legacy --async-callback \
  --features cm-async,cm-more-async-builtins -t >"$legacy_cancel_dummy"

require_text() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || {
    printf 'missing ABI fragment in %s: %s\n' "$file" "$expected" >&2
    exit 1
  }
}

require_common_dummy() {
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
    '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][method]descriptor.sync"' \
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

require_cancel_dummy() {
  local file="$1"
  require_common_dummy "$file"
  require_text "$file" '"$root" "[subtask-cancel]"'
  require_text "$file" '"[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16" "[task-return]cancel"'
  require_text "$file" '"[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#cancel"'
  require_text "$file" '"[callback][async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#cancel"'
}

require_common_dummy "$current_dummy"
require_common_dummy "$legacy_dummy"
require_cancel_dummy "$current_cancel_dummy"
require_cancel_dummy "$legacy_cancel_dummy"

assemble_component() {
  local tool="$1"
  local input_wit="$2"
  local world="$3"
  local input_core="$4"
  local name="$5"
  local core_wasm="$tmp_dir/$name.core.wasm"
  local embedded="$tmp_dir/$name.embedded.wasm"
  local component="$tmp_dir/$name.component.wasm"
  local component_wat="$tmp_dir/$name.component.wat"
  local component_wit="$tmp_dir/$name.component.wit"

  "$tool" parse "$input_core" -o "$core_wasm"
  "$tool" component embed "$input_wit" "$core_wasm" \
    --world "$world" --features cm-async,cm-more-async-builtins -o "$embedded"
  "$tool" component new --skip-validation "$embedded" -o "$component"
  "$tool" validate --features cm-async,cm-more-async-builtins "$component"
  "$tool" print "$component" >"$component_wat"
  "$tool" component wit "$component" >"$component_wit"
}

assemble_component "$current_wasm_tools" "$wit" sync-probe "$core_wat" sync-current
assemble_component "$legacy_wasm_tools" "$wit" sync-probe "$core_wat" sync-legacy
assemble_component "$current_wasm_tools" "$cancel_wit" sync-cancel-probe "$cancel_core_wat" sync-cancel-current
assemble_component "$legacy_wasm_tools" "$cancel_wit" sync-cancel-probe "$cancel_core_wat" sync-cancel-legacy

for name in sync-current sync-legacy; do
  require_text "$tmp_dir/$name.component.wat" \
    '"[async-lower][method]descriptor.sync"'
  require_text "$tmp_dir/$name.component.wat" '"[resource-drop]descriptor"'
  require_text "$tmp_dir/$name.component.wat" '"[task-return]run"'
  require_text "$tmp_dir/$name.component.wat" '(type (;4;) (result (error $error-code)))'
  require_text "$tmp_dir/$name.component.wit" 'sync: async func() -> result<_, error-code>;'
  require_text "$tmp_dir/$name.component.wit" 'run: async func(file: descriptor) -> result<_, error-code>;'
done

for name in sync-cancel-current sync-cancel-legacy; do
  require_text "$tmp_dir/$name.component.wat" \
    '"[async-lower][method]descriptor.sync"'
  require_text "$tmp_dir/$name.component.wat" '"[resource-drop]descriptor"'
  require_text "$tmp_dir/$name.component.wat" '"[task-return]run"'
  require_text "$tmp_dir/$name.component.wat" '"[task-return]cancel"'
  require_text "$tmp_dir/$name.component.wat" '"[async-lower][subtask-cancel]"'
  require_text "$tmp_dir/$name.component.wat" '(type (;4;) (result (error $error-code)))'
  require_text "$tmp_dir/$name.component.wit" 'sync: async func() -> result<_, error-code>;'
  require_text "$tmp_dir/$name.component.wit" 'cancel: async func();'
done

for file in "$core_wat" "$cancel_core_wat"; do
  require_text "$file" ';; [result-layout]'
  require_text "$file" '"wasi:filesystem/types@0.3.0-rc-2025-09-16"'
  require_text "$file" '"[async-lower][method]descriptor.sync"'
  require_text "$file" '(func $sync (type $method))'
  require_text "$file" '"[resource-drop]descriptor"'
  require_text "$file" '(func $descriptor-drop (type $resource-drop))'
done
require_text "$core_wat" ';; [sync-ready]'
require_text "$core_wat" ';; [sync-pending]'
require_text "$core_wat" ';; [sync-error]'
require_text "$cancel_core_wat" ';; Test-only control endpoint:'
require_text "$cancel_core_wat" '"[async-lower][subtask-cancel]"'

printf 'D2 filesystem descriptor.sync ABI passed\n'
printf 'current=%s sha256=%s\n' "$actual_current_version" "$actual_current_sha256"
printf 'legacy=%s sha256=%s\n' "$actual_legacy_version" "$actual_legacy_sha256"
printf 'mirror-sha256=%s cancel-mirror-sha256=%s upstream-sha256=%s\n' \
  "$expected_mirror_sha256" "$expected_cancel_mirror_sha256" "$expected_upstream_sha256"
printf 'async-import=[async-lower][method]descriptor.sync core=(i32,i32)->i32\n'
printf 'result=unit|error-code tag/payload=component-variant\n'
printf 'resource-drop=[resource-drop]descriptor (i32)->nil\n'
printf 'cancel=[async-lower][subtask-cancel] + [task-return]cancel (test-only)\n'
