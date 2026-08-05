#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasmtime_bin=${WASMTIME_BIN:-/home/_/.local/bin/wasmtime}
fixture="$repo_root/examples/gc-p3-runtime/cabi-realloc-budget.wat"
compiled=$(mktemp "${TMPDIR:-/tmp}/do-cabi-realloc-budget.XXXXXX")
trap 'rm -f "$compiled" "$compiled.wasm"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

wasm-tools parse "$fixture" -o "$compiled.wasm"
probe=$($wasmtime_bin --invoke probe "$fixture")
if [ "$probe" != "4" ]; then
  printf 'expected grow/shrink probe result 4, got %s\n' "$probe" >&2
  exit 1
fi
rollback=$($wasmtime_bin --invoke rollback_probe "$fixture")
if [ "$rollback" != "1" ]; then
  printf 'expected failed-grow rollback status 1, got %s\n' "$rollback" >&2
  exit 1
fi
if $wasmtime_bin --invoke quota_reject "$fixture" >/dev/null 2>&1; then
  printf 'expected quota rejection to trap\n' >&2
  exit 1
fi
printf 'cabi realloc budget probe passed: usage=%s rollback=verified quota=trapped\n' "$probe"
