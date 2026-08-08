#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-get-flags.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-get-flags-cancel.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-get-flags.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-get-flags-cancel.core.wat"
upstream_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit"

expected_current_version=${WASM_TOOLS_EXPECT_VERSION:-'wasm-tools 1.255.0 (76e20611d 2026-07-30)'}
expected_current_sha256=${WASM_TOOLS_EXPECT_SHA256:-6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013}
expected_legacy_version=${WASM_TOOLS_LEGACY_EXPECT_VERSION:-'wasm-tools 1.254.0 (bb58fdf91 2026-07-20)'}
expected_legacy_sha256=${WASM_TOOLS_LEGACY_EXPECT_SHA256:-cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6}
expected_mirror_sha256=12afdb48b07d7160c76f04231fb8da4862350d42f6170174e6e27264b7307be9
expected_upstream_sha256=8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f

current_wasm_tools=${WASM_TOOLS:-wasm-tools}
legacy_wasm_tools=${LEGACY_WASM_TOOLS:-/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools}

resolve_tool() {
  local requested=$1
  if [[ "$requested" == */* ]]; then
    test -x "$requested"
    printf '%s\n' "$requested"
    return
  fi
  command -v "$requested"
}

current_wasm_tools=$(resolve_tool "$current_wasm_tools")
legacy_wasm_tools=$(resolve_tool "$legacy_wasm_tools")
for path in "$wit" "$cancel_wit" "$core_wat" "$cancel_core_wat" "$upstream_wit"; do
  test -f "$path"
done

actual_current_version=$($current_wasm_tools --version)
actual_current_sha256=$(sha256sum "$current_wasm_tools" | awk '{print $1}')
test "$actual_current_version" = "$expected_current_version"
test "$actual_current_sha256" = "$expected_current_sha256"
actual_legacy_version=$($legacy_wasm_tools --version)
actual_legacy_sha256=$(sha256sum "$legacy_wasm_tools" | awk '{print $1}')
test "$actual_legacy_version" = "$expected_legacy_version"
test "$actual_legacy_sha256" = "$expected_legacy_sha256"
test "$(sha256sum "$wit" | awk '{print $1}')" = "$expected_mirror_sha256"
test "$(sha256sum "$upstream_wit" | awk '{print $1}')" = "$expected_upstream_sha256"

grep -Fq 'package wasi:filesystem@0.3.0-rc-2025-09-16;' "$wit"
grep -Fq 'flags descriptor-flags' "$wit"
grep -Fq 'get-flags: async func() -> result<descriptor-flags, error-code>;' "$wit"
grep -Fq 'run: async func(directory: own<descriptor>) -> result<descriptor-flags, error-code>;' "$wit"
grep -Fq 'world get-flags-probe' "$wit"
grep -Fq 'world get-flags-cancel-probe' "$cancel_wit"
grep -Fq 'cancel: async func();' "$cancel_wit"

require_text() {
  local file=$1
  local fragment=$2
  grep -Fq -- "$fragment" "$file" || {
    printf 'missing ABI fragment in %s: %s\n' "$file" "$fragment" >&2
    exit 1
  }
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-get-flags-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

for tool_name in current legacy; do
  if [[ "$tool_name" == current ]]; then
    tool=$current_wasm_tools
  else
    tool=$legacy_wasm_tools
  fi

  dummy="$tmp_dir/$tool_name-dummy.wat"
  cancel_dummy="$tmp_dir/$tool_name-cancel-dummy.wat"
  "$tool" component embed "$wit" --world get-flags-probe \
    --dummy-names legacy --async-callback --features cm-async,cm-more-async-builtins -t >"$dummy"
  "$tool" component embed "$cancel_wit" --world get-flags-cancel-probe \
    --dummy-names legacy --async-callback --features cm-async,cm-more-async-builtins -t >"$cancel_dummy"
  for file in "$dummy" "$cancel_dummy"; do
    require_text "$file" '(type (;0;) (func (param i32 i32) (result i32)))'
    require_text "$file" '(type (;4;) (func (param i32 i32)))'
    require_text "$file" '(type (;6;) (func (param i32 i32 i32) (result i32)))'
    require_text "$file" '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][method]descriptor.get-flags"'
    require_text "$file" '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[resource-drop]descriptor"'
    require_text "$file" '"[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16" "[task-return]run"'
  done

  core_wasm="$tmp_dir/$tool_name-core.wasm"
  embedded="$tmp_dir/$tool_name-embedded.wasm"
  component="$tmp_dir/$tool_name.component.wasm"
  component_wat="$tmp_dir/$tool_name.component.wat"
  component_wit="$tmp_dir/$tool_name.component.wit"
  "$tool" parse "$core_wat" -o "$core_wasm"
  "$tool" component embed "$wit" "$core_wasm" --world get-flags-probe \
    --features cm-async,cm-more-async-builtins -o "$embedded"
  "$tool" component new --skip-validation "$embedded" -o "$component"
  "$tool" validate --features cm-async,cm-more-async-builtins "$component"
  "$tool" print "$component" >"$component_wat"
  "$tool" component wit "$component" >"$component_wit"
  require_text "$core_wat" ';; [get-flags-call]'
  require_text "$core_wat" ';; [get-flags-ready]'
  require_text "$core_wat" ';; [get-flags-pending]'
  require_text "$core_wat" ';; [get-flags-error]'
  require_text "$core_wat" ';; [descriptor-drop]'
  require_text "$component_wat" '"[async-lower][method]descriptor.get-flags"'
  require_text "$component_wat" '"[resource-drop]descriptor"'
  require_text "$component_wit" 'get-flags: async func() -> result<descriptor-flags, error-code>;'

  cancel_core_wasm="$tmp_dir/$tool_name-cancel-core.wasm"
  cancel_embedded="$tmp_dir/$tool_name-cancel-embedded.wasm"
  cancel_component="$tmp_dir/$tool_name-cancel.component.wasm"
  cancel_component_wat="$tmp_dir/$tool_name-cancel.component.wat"
  cancel_component_wit="$tmp_dir/$tool_name-cancel.component.wit"
  "$tool" parse "$cancel_core_wat" -o "$cancel_core_wasm"
  "$tool" component embed "$cancel_wit" "$cancel_core_wasm" \
    --world get-flags-cancel-probe --features cm-async,cm-more-async-builtins \
    -o "$cancel_embedded"
  "$tool" component new --skip-validation "$cancel_embedded" -o "$cancel_component"
  "$tool" validate --features cm-async,cm-more-async-builtins "$cancel_component"
  "$tool" print "$cancel_component" >"$cancel_component_wat"
  "$tool" component wit "$cancel_component" >"$cancel_component_wit"
  require_text "$cancel_core_wat" '"[async-lower][subtask-cancel]"'
  require_text "$cancel_component_wat" '"[async-lower][method]descriptor.get-flags"'
  require_text "$cancel_component_wit" 'cancel: async func();'
done

printf 'D2 filesystem descriptor.get-flags ABI passed\n'
printf 'current=%s sha256=%s\n' "$actual_current_version" "$actual_current_sha256"
printf 'legacy=%s sha256=%s\n' "$actual_legacy_version" "$actual_legacy_sha256"
printf 'mirror-sha256=%s upstream-sha256=%s\n' "$expected_mirror_sha256" "$expected_upstream_sha256"
printf 'async-import=[async-lower][method]descriptor.get-flags core=(i32,i32)->i32\n'
printf 'result=descriptor-flags|error-code tag/payload=component-variant flags=canonical-u8/flat-i32\n'
printf 'resource-drop=[resource-drop]descriptor (i32)->nil\n'
