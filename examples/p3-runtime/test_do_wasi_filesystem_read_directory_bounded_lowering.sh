#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-read-directory-bounded-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/read-directory-bounded.wat"
core_wasm="$tmp_dir/read-directory-bounded.wasm"
wit="$tmp_dir/read-directory-bounded.wit"
embedded="$tmp_dir/read-directory-bounded.embedded.wasm"
component="$tmp_dir/read-directory-bounded.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/wasi-filesystem-read-directory-bounded.do" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" read-directory-probe -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"

grep -Fq ';; bounded remaining reads are stored at frame+16' "$core_wat"
grep -Fq 'i32.const 3' "$core_wat"
grep -Fq 'i32.sub' "$core_wat"
test "$(grep -Fc 'call $stream-read' "$core_wat")" -eq 1
grep -Fq 'record directory-entry {' "$wit"
grep -Fq 'run-bounded: async func' "$wit"

printf 'WASI G6.2 bounded read-directory lowering passed\n'
