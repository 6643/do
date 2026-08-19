#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
zig_bin=${ZIG_BIN:-zig}
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
fixture="$repo_root/examples/gc-p3-runtime/managed-text-field-call-producer.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-managed-text-field-call-producer.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

wat_path="$tmp_dir/managed-text-field-call-producer.wat"
"$zig_bin" run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$wat_path" replace
if rg -q '__arc_' "$wat_path"; then
  printf 'managed text field call producer GC WAT contains ARC markers\n' >&2
  exit 1
fi
if ! rg -q 'call \$make_text' "$wat_path" || ! rg -q ';; gc-root call_result' "$wat_path"; then
  printf 'managed text field call producer GC WAT lacks typed call/root lowering\n' >&2
  exit 1
fi
"$wasm_tools_bin" parse "$wat_path" -o "$tmp_dir/managed-text-field-call-producer.wasm"
"$wasmtime_bin" compile -W gc=y -o "$tmp_dir/managed-text-field-call-producer.compiled" "$wat_path"

result=$("$wasmtime_bin" -W gc=y --invoke probe "$wat_path")
if [ "$result" != "27815" ]; then
  printf 'expected managed text field call producer result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC managed text field call producer passed: %s\n' "$result"
