#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-metadata-hash.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-metadata-hash-cancel.wit"
upstream_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-metadata-hash.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-metadata-hash-cancel.core.wat"

expected_upstream_sha256=8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f
expected_mirror_sha256=6976359b3a4813d6771b3ef9a7fdcfb2ee9323e70c33b9ac7d6b628519fecfed
expected_cancel_mirror_sha256=b6e98cf2ae6f76e105f53c7ea09666b1c5684d33edb9838d034862a27b09f5c3

for path in "$wit" "$cancel_wit" "$upstream_wit"; do
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

[[ "$(sha256sum "$wit" | awk '{print $1}')" == "$expected_mirror_sha256" ]] || {
  printf 'filesystem metadata-hash WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$cancel_wit" | awk '{print $1}')" == "$expected_cancel_mirror_sha256" ]] || {
  printf 'filesystem metadata-hash cancel WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$upstream_wit" | awk '{print $1}')" == "$expected_upstream_sha256" ]] || {
  printf 'pinned filesystem WIT source hash changed\n' >&2
  exit 1
}

grep -Fq 'record metadata-hash-value' "$wit"
grep -Fq 'lower: u64' "$wit"
grep -Fq 'upper: u64' "$wit"
grep -Fq 'metadata-hash: async func() -> result<metadata-hash-value, error-code>;' "$wit"
grep -Fq 'run: async func(file: own<descriptor>) -> result<metadata-hash-value, error-code>;' "$wit"
grep -Fq 'world metadata-hash-probe' "$wit"
grep -Fq 'world metadata-hash-cancel-probe' "$cancel_wit"
grep -Fq 'cancel: async func();' "$cancel_wit"

tmp_dir=$(mktemp -d /tmp/do-d2-filesystem-metadata-hash-abi.XXXXXX)
mkdir -p "$tmp_dir/regular" "$tmp_dir/cancel"
cp "$wit" "$tmp_dir/regular/wasi-filesystem-metadata-hash.wit"
cp "$cancel_wit" "$tmp_dir/cancel/wasi-filesystem-metadata-hash-cancel.wit"

"$toolchain_bin" embed-component-template "$tmp_dir/regular" metadata-hash-probe \
  --features component-async >"$tmp_dir/current-regular.wat"
"$toolchain_bin" embed-component-template "$tmp_dir/cancel" metadata-hash-cancel-probe \
  --features component-async >"$tmp_dir/current-cancel.wat"

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
    '(type (;0;) (func (param i32 i32) (result i32)))' \
    '(type (;1;) (func (param i32)))' \
    '(type (;6;) (func (param i32 i64 i64)))' \
    '(import "wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][method]descriptor.metadata-hash"' \
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
    '(type $method (func (param i32 i32) (result i32)))' \
    '(type $task-return-metadata-hash (func (param i32 i64 i64)))' \
    '0 waitable:i32, 4 descriptor:i32, 8 result-tag:u8,' \
    '16 lower:u64, 24 upper:u64, 32 status:i32, 36 callback-subtask:i32.' \
    ';; [metadata-hash-result-area]' \
    ';; [metadata-hash-ready]' \
    ';; [metadata-hash-error]' \
    ';; [metadata-hash-pending]' \
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

for path in "$core_wat" "$cancel_core_wat"; do
  "$toolchain_bin" parse-core "$path" -o "$tmp_dir/$(basename "$path" .wat).wasm"
  "$toolchain_bin" validate-core "$tmp_dir/$(basename "$path" .wat).wasm"
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

  "$toolchain_bin" parse-core "$core" -o "$core_wasm"
  "$toolchain_bin" embed-component "$input_dir" "$core_wasm" "$world" -o "$embedded"
  "$toolchain_bin" new-component "$embedded" -o "$component"
  "$toolchain_bin" validate-component "$component" --features component-async
  "$toolchain_bin" print-component "$component" >"$component_wat"
  "$toolchain_bin" component-wit "$component" >"$component_wit"

  require_text "$component_wat" '"[async-lower][method]descriptor.metadata-hash"'
  require_text "$component_wat" '"[resource-drop]descriptor"'
  require_text "$component_wat" '"[task-return]run"'
  [[ $(grep -cF '"[async-lower][method]' "$component_wat") -eq 2 ]] || {
    printf 'unexpected filesystem async method count in %s\n' "$component_wat" >&2
    exit 1
  }
  for forbidden in get-type get-flags sync sync-data stat stat-at metadata-hash-at; do
    if grep -Fq "descriptor.$forbidden" "$component_wat"; then
      printf 'unexpected filesystem method in %s: descriptor.%s\n' \
        "$component_wat" "$forbidden" >&2
      exit 1
    fi
  done
  require_text "$component_wit" 'metadata-hash: async func() -> result<metadata-hash-value, error-code>;'
  require_text "$component_wit" 'run: async func(file: descriptor) -> result<metadata-hash-value, error-code>;'
  if [[ "$world" == metadata-hash-cancel-probe ]]; then
    require_text "$component_wat" '"[async-lower][subtask-cancel]"'
    require_text "$component_wat" '"[task-return]cancel"'
    require_text "$component_wit" 'cancel: async func();'
  fi
}

assemble_component "$tmp_dir/regular" metadata-hash-probe "$core_wat" metadata-hash
assemble_component "$tmp_dir/cancel" metadata-hash-cancel-probe "$cancel_core_wat" metadata-hash-cancel

printf 'D2 filesystem descriptor.metadata-hash WIT ABI capability passed\n'
printf 'toolchain-adapter=current-only\n'
printf 'metadata-hash-mirror-sha256=%s cancel-mirror-sha256=%s upstream-sha256=%s\n' \
  "$expected_mirror_sha256" "$expected_cancel_mirror_sha256" "$expected_upstream_sha256"
printf 'async-import=[async-lower][method]descriptor.metadata-hash core=(i32,i32)->i32\n'
printf 'task-return-run=(i32,i64,i64)\n'
printf 'result=metadata-hash-value|error-code lower:u64 upper:u64\n'
printf 'resource-drop=[resource-drop]descriptor (i32)->nil\n'
