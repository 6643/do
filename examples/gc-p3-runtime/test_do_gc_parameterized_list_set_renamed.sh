#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
zig_bin=${ZIG_BIN:-zig}
fixture="$repo_root/examples/gc-p3-runtime/parameterized-list-set-renamed.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-parameterized-list-set-renamed.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

wat_path="$tmp_dir/parameterized-list-set-renamed.wat"
"$zig_bin" run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$wat_path" replace
"${WASM_TOOLS_BIN:-wasm-tools}" parse "$wat_path" -o "$tmp_dir/parameterized-list-set-renamed.wasm"
"$wasmtime_bin" compile -W gc=y -o "$tmp_dir/parameterized-list-set-renamed.compiled" "$wat_path"

result=$("$wasmtime_bin" -W gc=y --invoke probe "$wat_path")
if [ "$result" != "27815" ]; then
  printf 'expected renamed parameterized GC list update result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC renamed parameterized list update passed: %s\n' "$result"
