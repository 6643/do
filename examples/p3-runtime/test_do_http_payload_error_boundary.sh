#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
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

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit_dir" "$core_wasm" \
  --world service -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

printf 'WASI HTTP payload error compiler boundary passed\n'
