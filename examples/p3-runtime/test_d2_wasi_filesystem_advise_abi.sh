#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
upstream_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-advise-probe.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-advise-cancel-probe.wit"

expected_wasm_tools_version='wasm-tools 1.263.0'
expected_wasm_tools_sha256=c8b33fa4abc6b2cc85a68a10779c1968f1a98725e5d462ffbc5a71a4a8c8fb87
expected_upstream_sha256=8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f
expected_wit_sha256=b896feb4867d49dcfb57951e09ebb6a3feeaf16fbffb8b56cd27f7bee281e132
expected_cancel_wit_sha256=0e2dc022d1985ce0de7ac8a412348c835995f390597e1bd40e98b4f1c22dc9a1

wasm_tools_bin=$(command -v wasm-tools)
[[ "$($wasm_tools_bin --version)" == "$expected_wasm_tools_version" ]] || {
  printf 'unexpected wasm-tools version: %s\n' "$($wasm_tools_bin --version)" >&2
  exit 1
}
[[ "$(sha256sum "$wasm_tools_bin" | awk '{print $1}')" == "$expected_wasm_tools_sha256" ]] || {
  printf 'wasm-tools binary hash changed: %s\n' "$wasm_tools_bin" >&2
  exit 1
}

for path in "$upstream_wit" "$wit" "$cancel_wit"; do
  [[ -f "$path" ]] || {
    printf 'missing descriptor.advise ABI input: %s\n' "$path" >&2
    exit 1
  }
done

[[ "$(sha256sum "$upstream_wit" | awk '{print $1}')" == "$expected_upstream_sha256" ]] || {
  printf 'pinned filesystem WIT source hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$wit" | awk '{print $1}')" == "$expected_wit_sha256" ]] || {
  printf 'descriptor.advise WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$cancel_wit" | awk '{print $1}')" == "$expected_cancel_wit_sha256" ]] || {
  printf 'descriptor.advise cancel WIT mirror hash changed\n' >&2
  exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-advise-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

require_text() {
  local file="$1"
  local expected="$2"
  rg -Fq -- "$expected" "$file" || {
    printf 'missing ABI fragment in %s: %s\n' "$file" "$expected" >&2
    exit 1
  }
}

probe_world() {
  local input_wit="$1"
  local world="$2"
  local name="$3"
  local template_wat="$tmp_dir/$name.template.wat"
  local core_wasm="$tmp_dir/$name.core.wasm"
  local embedded="$tmp_dir/$name.embedded.wasm"
  local component="$tmp_dir/$name.component.wasm"
  local component_wat="$tmp_dir/$name.component.wat"
  local component_wit="$tmp_dir/$name.component.wit"
  local canonical_wat="$repo_root/examples/p3-runtime/wasi-filesystem-$name.core.wat"

  "$toolchain_bin" embed-component-template "$input_wit" "$world" \
    --features component-async >"$template_wat"

  [[ -f "$canonical_wat" ]] || {
    printf 'missing checked-in canonical Core snapshot: %s\n' "$canonical_wat" >&2
    exit 1
  }
  cmp -s "$template_wat" "$canonical_wat" || {
    printf 'canonical Core snapshot drifted for %s\n' "$world" >&2
    diff -u "$canonical_wat" "$template_wat" >&2 || true
    exit 1
  }

  require_text "$template_wat" '(type (;0;) (func (param i32 i64 i64 i32 i32) (result i32)))'
  require_text "$template_wat" '"[async-lower][method]descriptor.advise" (func'
  require_text "$template_wat" '"[resource-drop]descriptor"'
  require_text "$template_wat" '"[task-return]run"'
  [[ $(rg -cF '"[async-lower][method]' "$template_wat") -eq 1 ]] || {
    printf 'unexpected filesystem async method count in %s\n' "$template_wat" >&2
    exit 1
  }
  if [[ "$world" == advise-cancel-probe ]]; then
    require_text "$template_wat" '"[task-return]cancel"'
    require_text "$template_wat" '"[subtask-cancel]"'
  fi

  "$toolchain_bin" parse-core "$canonical_wat" -o "$core_wasm"
  "$toolchain_bin" embed-component "$input_wit" "$core_wasm" "$world" \
    --features component-async -o "$embedded"
  "$toolchain_bin" new-component "$embedded" -o "$component"
  "$toolchain_bin" validate-component "$component" --features component-async
  "$toolchain_bin" print-component "$component" >"$component_wat"
  "$toolchain_bin" component-wit "$component" >"$component_wit"

  require_text "$component_wat" '"[async-lower][method]descriptor.advise"'
  require_text "$component_wat" '"[resource-drop]descriptor"'
  require_text "$component_wat" '"[task-return]run"'
  [[ $(rg -cF '"[async-lower][method]' "$component_wat") -eq 2 ]] || {
    printf 'unexpected assembled filesystem async method count in %s\n' "$component_wat" >&2
    exit 1
  }
  require_text "$component_wit" 'advise: async func(offset: filesize, length: filesize, advice: advice) -> result<_, error-code>;'
  require_text "$component_wit" 'run: async func(file: descriptor, offset: filesize, length: filesize, advice: advice) -> result<_, error-code>;'
  rg -U -Fq $'enum advice {\n      normal,\n      sequential,\n      random,\n      will-need,\n      dont-need,\n      no-reuse,\n    }' "$component_wit" || {
    printf 'descriptor.advise WIT enum order changed in %s\n' "$component_wit" >&2
    exit 1
  }
  if [[ "$world" == advise-cancel-probe ]]; then
    require_text "$component_wat" '"[subtask-cancel]"'
    require_text "$component_wat" '"[task-return]cancel"'
    require_text "$component_wit" 'cancel: async func();'
  fi
}

probe_world "$wit" advise-probe advise
probe_world "$cancel_wit" advise-cancel-probe advise-cancel

printf 'D2 descriptor.advise ABI probe passed\n'
printf 'wasm-tools=%s sha256=%s\n' "$expected_wasm_tools_version" "$expected_wasm_tools_sha256"
printf 'upstream-wit-sha256=%s mirror-sha256=%s cancel-mirror-sha256=%s\n' \
  "$expected_upstream_sha256" "$expected_wit_sha256" "$expected_cancel_wit_sha256"
printf 'async-import=[async-lower][method]descriptor.advise core=(i32,i64,i64,i32,i32)->i32\n'
printf 'arguments=descriptor:i32 offset:u64 length:u64 advice:u32 result-area:i32 result=unit|error-code\n'
printf 'resource-drop=[resource-drop]descriptor (i32)->nil\n'
