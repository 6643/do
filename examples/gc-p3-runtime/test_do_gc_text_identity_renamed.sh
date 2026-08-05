#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
fixture="$repo_root/examples/gc-p3-runtime/text-identity-renamed.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-text-identity-renamed.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

wat_path="$tmp_dir/text-identity-renamed.wat"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" --gc-core -o "$wat_path"
wasm-tools parse "$wat_path" -o "$tmp_dir/text-identity-renamed.wasm"
"$wasmtime_bin" compile -W gc=y -o "$tmp_dir/text-identity-renamed.compiled" "$wat_path"

result=$("$wasmtime_bin" -W gc=y --invoke probe "$wat_path")
if [ "$result" != "27815" ]; then
  printf 'expected renamed GC text identity result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC renamed text identity passed: %s\n' "$result"
