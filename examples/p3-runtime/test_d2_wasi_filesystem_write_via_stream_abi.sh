#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
upstream_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-write-via-stream-probe.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-write-via-stream-cancel-probe.wit"

expected_wasm_tools_version='wasm-tools 1.263.0'
expected_wasm_tools_sha256=c8b33fa4abc6b2cc85a68a10779c1968f1a98725e5d462ffbc5a71a4a8c8fb87
expected_upstream_sha256=8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f
expected_wit_sha256=4c45db6faffc72c7143355cc43e6261c7038de8de489eecc0749d2cfc4ef329b
expected_cancel_wit_sha256=24eb9c3108ff7a470d919ef5d3ca2b21b39282a2c282e36b711b0c783e9265ef

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
    printf 'missing descriptor.write-via-stream ABI input: %s\n' "$path" >&2
    exit 1
  }
done

[[ "$(sha256sum "$upstream_wit" | awk '{print $1}')" == "$expected_upstream_sha256" ]] || {
  printf 'pinned filesystem WIT source hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$wit" | awk '{print $1}')" == "$expected_wit_sha256" ]] || {
  printf 'descriptor.write-via-stream WIT mirror hash changed\n' >&2
  exit 1
}
[[ "$(sha256sum "$cancel_wit" | awk '{print $1}')" == "$expected_cancel_wit_sha256" ]] || {
  printf 'descriptor.write-via-stream cancel WIT mirror hash changed\n' >&2
  exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-write-via-stream-abi.XXXXXX")
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

  require_text "$template_wat" '(type (;0;) (func (param i32 i32 i64 i32) (result i32)))'
  require_text "$template_wat" '"[async-lower][method]descriptor.write-via-stream" (func'
  require_text "$template_wat" '"[stream-new-0][method]descriptor.write-via-stream"'
  require_text "$template_wat" '"[stream-cancel-read-0][method]descriptor.write-via-stream"'
  require_text "$template_wat" '"[stream-cancel-write-0][method]descriptor.write-via-stream"'
  require_text "$template_wat" '"[stream-drop-readable-0][method]descriptor.write-via-stream"'
  require_text "$template_wat" '"[stream-drop-writable-0][method]descriptor.write-via-stream"'
  require_text "$template_wat" '"[stream-forward-0][method]descriptor.write-via-stream"'
  require_text "$template_wat" '"[async-lower][stream-read-0][method]descriptor.write-via-stream"'
  require_text "$template_wat" '"[async-lower][stream-write-0][method]descriptor.write-via-stream"'
  require_text "$template_wat" '"[resource-drop]descriptor"'
  require_text "$template_wat" '"[task-return]run"'
  [[ $(rg -cF '"[async-lower][method]' "$template_wat") -eq 1 ]] || {
    printf 'unexpected filesystem async method count in %s\n' "$template_wat" >&2
    exit 1
  }
  if [[ "$world" == write-via-stream-cancel-probe ]]; then
    require_text "$template_wat" '"[task-return]cancel"'
    require_text "$template_wat" '"[subtask-cancel]"'
  fi

  "$toolchain_bin" parse-core "$canonical_wat" -o "$core_wasm"
  "$toolchain_bin" validate-core "$core_wasm"
  rg -Fq 'write-via-stream: async func(' "$input_wit"
  rg -Fq 'data: stream<u8>' "$input_wit"
  rg -Fq 'offset: u64' "$input_wit"
  rg -Fq ') -> result<_, error-code>;' "$input_wit"
  rg -Fq 'run: async func(' "$input_wit"
  rg -Fq 'file: own<descriptor>' "$input_wit"
  rg -Fq 'offset: u64' "$input_wit"
  if [[ "$world" == write-via-stream-cancel-probe ]]; then
    rg -Fq 'cancel: async func();' "$input_wit"
  fi
}

probe_world "$wit" write-via-stream-probe write-via-stream
probe_world "$cancel_wit" write-via-stream-cancel-probe write-via-stream-cancel

printf 'D2 descriptor.write-via-stream ABI snapshot passed\n'
printf 'wasm-tools=%s sha256=%s\n' "$expected_wasm_tools_version" "$expected_wasm_tools_sha256"
printf 'upstream-wit-sha256=%s mirror-sha256=%s cancel-mirror-sha256=%s\n' \
  "$expected_upstream_sha256" "$expected_wit_sha256" "$expected_cancel_wit_sha256"
printf 'async-import=[async-lower][method]descriptor.write-via-stream core=(i32,i32,i64,i32)->i32\n'
printf 'arguments=descriptor:i32 stream-writer:i32 offset:u64 result-area:i32 result=unit|error-code\n'
printf 'stream-writer=stream-new/cancel-read/cancel-write/forward/read/write/drop\n'
printf 'resource-drop=[resource-drop]descriptor (i32)->nil\n'
printf 'assembly=deferred: current wasm-tools rejects standard stream.forward validation\n'
