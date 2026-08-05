#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
fixture="$repo_root/examples/gc-p3-runtime/async-frame-table.wat"
compiled=$(mktemp "${TMPDIR:-/tmp}/do-gc-async-frame-table.XXXXXX")
trap 'rm -f "$compiled"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

wasm-tools parse "$fixture" -o "$compiled.wasm"
"$wasmtime_bin" compile -W gc=y -o "$compiled" "$fixture"
result=$("$wasmtime_bin" -W gc=y --invoke probe "$fixture")
if [ "$result" != "27815" ]; then
  printf 'expected GC async frame-table result 27815, got %s\n' "$result" >&2
  exit 1
fi
budget_result=$("$wasmtime_bin" -W gc=y --invoke budget_probe "$fixture")
if [ "$budget_result" != "1" ]; then
  printf 'expected GC async frame budget result 1, got %s\n' "$budget_result" >&2
  exit 1
fi
canonical_result=$("$wasmtime_bin" -W gc=y --invoke canonical_budget_probe "$fixture")
if [ "$canonical_result" != "1" ]; then
  printf 'expected canonical buffer budget result 1, got %s\n' "$canonical_result" >&2
  exit 1
fi
printf 'GC async frame-table probe passed: %s (budget=%s, canonical=%s)\n' "$result" "$budget_result" "$canonical_result"
