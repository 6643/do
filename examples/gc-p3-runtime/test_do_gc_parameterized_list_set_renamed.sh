#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi
zig_bin=${ZIG_BIN:-zig}
fixture="$repo_root/examples/gc-p3-runtime/parameterized-list-set-renamed.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-parameterized-list-set-renamed.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT


wat_path="$tmp_dir/parameterized-list-set-renamed.wat"
"$zig_bin" run "$repo_root/src/build/gc_sync_probe.zig" -- "$fixture" "$wat_path" replace
"$toolchain_bin" parse-core "$wat_path" -o "$tmp_dir/parameterized-list-set-renamed.wasm"
"$toolchain_bin" compile-core-gc "$wat_path" -o "$tmp_dir/parameterized-list-set-renamed.compiled"

result=$("$toolchain_bin" invoke-core-gc "$wat_path" --export probe)
if [ "$result" != "27815" ]; then
  printf 'expected renamed parameterized GC list update result 27815, got %s\n' "$result" >&2
  exit 1
fi
printf 'Do GC renamed parameterized list update passed: %s\n' "$result"
