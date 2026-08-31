#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
fixture="$repo_root/examples/gc-p3-runtime/managed-struct-renamed.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-managed-struct-renamed.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

wat_path="$tmp_dir/managed-struct-renamed.wat"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" --gc-core -o "$wat_path"
"$toolchain_bin" parse-core "$wat_path" -o "$tmp_dir/managed-struct-renamed.wasm"
"$wasmtime_bin" compile -W gc=y -o "$tmp_dir/managed-struct-renamed.compiled" "$wat_path"

result=$("$wasmtime_bin" -W gc=y --invoke probe "$wat_path")
if [ "$result" != "27815" ]; then
  printf 'expected renamed GC managed struct update result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC renamed managed struct update passed: %s\n' "$result"
