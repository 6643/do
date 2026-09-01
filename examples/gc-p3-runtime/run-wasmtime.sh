#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
fixture="$repo_root/examples/gc-p3-runtime/gc-frame.wat"
expected=27815
compiled=$(mktemp /tmp/do-gc-frame.XXXXXX)
trap 'rm -f "$compiled"' EXIT

if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing executable Wasmtime binary: %s\n' "$wasmtime_bin" >&2
  exit 1
fi
if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi

printf 'wasmtime: '
"$wasmtime_bin" --version
printf 'compile-or-validate: '
"$toolchain_bin" compile-core-gc "$fixture" -o "$compiled"
printf 'ok\n'
printf 'run:\n'
output=$("$toolchain_bin" invoke-core-gc "$fixture" --export probe)
if [ "$output" != "$expected" ]; then
  printf 'expected %s, got %s\n' "$expected" "$output" >&2
  exit 1
fi
printf '  guest result: %s\n' "$output"

printf 'GC probe passed: %s\n' "$expected"
