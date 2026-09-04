#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
fixture="$repo_root/examples/gc-p3-runtime/async-frame-table.wat"
compiled=$(mktemp "${TMPDIR:-/tmp}/do-gc-async-frame-table.XXXXXX")
trap 'rm -f "$compiled" "$compiled.wasm"' EXIT

if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi

"$toolchain_bin" parse-core "$fixture" -o "$compiled.wasm"
"$toolchain_bin" compile-core-gc "$fixture" -o "$compiled"
result=$("$toolchain_bin" invoke-core-gc "$fixture" --export probe)
if [ "$result" != "27815" ]; then
  printf 'expected GC async frame-table result 27815, got %s\n' "$result" >&2
  exit 1
fi
budget_result=$("$toolchain_bin" invoke-core-gc "$fixture" --export budget_probe)
if [ "$budget_result" != "1" ]; then
  printf 'expected GC async frame budget result 1, got %s\n' "$budget_result" >&2
  exit 1
fi
canonical_result=$("$toolchain_bin" invoke-core-gc "$fixture" --export canonical_budget_probe)
if [ "$canonical_result" != "1" ]; then
  printf 'expected canonical buffer budget result 1, got %s\n' "$canonical_result" >&2
  exit 1
fi
printf 'GC async frame-table probe passed: %s (budget=%s, canonical=%s)\n' "$result" "$budget_result" "$canonical_result"
