#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
zig_bin=${ZIG_BIN:-zig}
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
fixture="$repo_root/examples/gc-p3-runtime/three-level-nested-field-path.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-three-level-nested-field-path.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

wat_path="$tmp_dir/three-level-nested-field-path.wat"
"$zig_bin" run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$wat_path" update
if rg -q '__arc_' "$wat_path"; then
  printf 'three-level nested field path GC WAT contains ARC markers\n' >&2
  exit 1
fi
if ! rg -q 'struct.get \$outer \$inner' "$wat_path" ||
   ! rg -q 'struct.get \$inner \$middle' "$wat_path" ||
   ! rg -q 'struct.get \$middle \$leaf' "$wat_path" ||
   ! rg -q 'struct.get \$leaf \$value' "$wat_path" ||
   ! rg -q 'struct.new \$leaf' "$wat_path" ||
   ! rg -q 'struct.new \$middle' "$wat_path" ||
   ! rg -q 'struct.new \$inner' "$wat_path" ||
   ! rg -q 'struct.new \$outer' "$wat_path"; then
  printf 'three-level nested field path output lacks chained GC lowering\n' >&2
  exit 1
fi
"$wasm_tools_bin" parse "$wat_path" -o "$tmp_dir/three-level-nested-field-path.wasm"
"$wasmtime_bin" compile -W gc=y -o "$tmp_dir/three-level-nested-field-path.compiled" "$wat_path"

result=$("$wasmtime_bin" -W gc=y --invoke probe "$wat_path")
if [ "$result" != "27815" ]; then
  printf 'expected three-level nested field path result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC three-level nested field path update passed: %s\n' "$result"
