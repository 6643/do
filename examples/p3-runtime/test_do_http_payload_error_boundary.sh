#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
do_bin="$repo_root/bin/do"
fixture="$repo_root/examples/p3-runtime/http-service.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-http-payload-error-boundary.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wat="$tmp_dir/http-service.wat"
core_wasm="$tmp_dir/http-service.wasm"
embedded="$tmp_dir/http-service.embedded.wasm"
component="$tmp_dir/http-service.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"

grep -Fq '(type $task-return (func (param i32 i32 i32 i64 i32 i32 i32 i32)))' "$core_wat"
grep -Fq ';; [error-variant:internal-error]' "$core_wat"
grep -Fq 'i32.const 16' "$core_wat"
grep -Fq 'i32.const 20' "$core_wat"
grep -Fq 'i32.const 24' "$core_wat"
grep -Fq 'i32.const 32' "$core_wat"
if rg -U -q 'i32\.const 38\n\s*i32\.eq\n\s*if unreachable end' "$core_wat"; then
  printf 'InternalError payload unexpectedly remains an explicit trap\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit_dir" "$core_wasm" \
  service -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"

printf 'WASI HTTP payload error compiler boundary passed\n'
