#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
zig_bin=${ZIG_BIN:-zig}
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
fixture="$repo_root/examples/gc-p3-runtime/five-level-nested-field-path.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-five-level-nested-field-path.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

wat_path="$tmp_dir/five-level-nested-field-path.wat"
"$zig_bin" run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$wat_path" update
if rg -q '__arc_' "$wat_path"; then
  printf 'five-level nested field path GC WAT contains ARC markers\n' >&2
  exit 1
fi
for marker in \
  'struct.get \$top \$outer' \
  'struct.get \$outer \$inner' \
  'struct.get \$inner \$middle' \
  'struct.get \$middle \$leaf' \
  'struct.get \$leaf \$core' \
  'struct.get \$core \$value' \
  'struct.new \$core' \
  'struct.new \$leaf' \
  'struct.new \$middle' \
  'struct.new \$inner' \
  'struct.new \$outer' \
  'struct.new \$top'; do
  if ! rg -q "$marker" "$wat_path"; then
    printf 'five-level nested field path output lacks marker: %s\n' "$marker" >&2
    exit 1
  fi
done
"$wasm_tools_bin" parse "$wat_path" -o "$tmp_dir/five-level-nested-field-path.wasm"
"$wasmtime_bin" compile -W gc=y -o "$tmp_dir/five-level-nested-field-path.compiled" "$wat_path"

result=$("$wasmtime_bin" -W gc=y --invoke probe "$wat_path")
if [ "$result" != "27815" ]; then
  printf 'expected five-level nested field path result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC five-level nested field path update passed: %s\n' "$result"
