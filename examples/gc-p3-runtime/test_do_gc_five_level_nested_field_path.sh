#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi
zig_bin=${ZIG_BIN:-zig}
fixture="$repo_root/examples/gc-p3-runtime/five-level-nested-field-path.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-five-level-nested-field-path.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT


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
"$toolchain_bin" parse-core "$wat_path" -o "$tmp_dir/five-level-nested-field-path.wasm"
"$toolchain_bin" compile-core-gc "$wat_path" -o "$tmp_dir/five-level-nested-field-path.compiled"

result=$("$toolchain_bin" invoke-core-gc "$wat_path" --export probe)
if [ "$result" != "27815" ]; then
  printf 'expected five-level nested field path result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC five-level nested field path update passed: %s\n' "$result"
