#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
fixture="$repo_root/examples/gc-p3-runtime/gc-frame.wat"
expected=27815
compiled=$(mktemp /tmp/do-gc-frame.XXXXXX)
trap 'rm -f "$compiled"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

printf 'wasmtime: '
"$wasmtime_bin" --version
printf 'compile-or-validate: '
"$wasmtime_bin" compile -W gc=y -o "$compiled" "$fixture"
printf 'ok\n'
printf 'run:\n'
output=$("$wasmtime_bin" -W gc=y --invoke probe "$fixture")
if [ "$output" != "$expected" ]; then
  printf 'expected %s, got %s\n' "$expected" "$output" >&2
  exit 1
fi
printf '  guest result: %s\n' "$output"

printf 'GC probe passed: %s\n' "$expected"
