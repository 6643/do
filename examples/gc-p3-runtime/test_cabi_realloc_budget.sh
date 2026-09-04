#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
fixture="$repo_root/examples/gc-p3-runtime/cabi-realloc-budget.wat"
compiled=$(mktemp "${TMPDIR:-/tmp}/do-cabi-realloc-budget.XXXXXX")
trap 'rm -f "$compiled" "$compiled.wasm"' EXIT

if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi

"$toolchain_bin" parse-core "$fixture" -o "$compiled.wasm"
probe=$("$toolchain_bin" invoke-core-gc "$fixture" --export probe)
if [ "$probe" != "4" ]; then
  printf 'expected grow/shrink probe result 4, got %s\n' "$probe" >&2
  exit 1
fi
rollback=$("$toolchain_bin" invoke-core-gc "$fixture" --export rollback_probe)
if [ "$rollback" != "1" ]; then
  printf 'expected failed-grow rollback status 1, got %s\n' "$rollback" >&2
  exit 1
fi
if "$toolchain_bin" invoke-core-gc "$fixture" --export quota_reject >/dev/null 2>&1; then
  printf 'expected quota rejection to trap\n' >&2
  exit 1
fi
printf 'cabi realloc budget probe passed: usage=%s rollback=verified quota=trapped\n' "$probe"
