#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
zig_bin=${ZIG_BIN:-/snap/bin/zig}
wasmtime_include=/home/_/Public/wasmtime/c-api/include
wasmtime_lib=/home/_/Public/wasmtime/c-api/lib
runner=/tmp/do-p3-host-drive-queue-runner
component=/tmp/do-p3-host-drive-queue-component.wasm

if [ ! -x "$zig_bin" ]; then
  printf 'missing Zig compiler: %s\n' "$zig_bin" >&2
  exit 1
fi
if [ ! -f "$wasmtime_lib/libwasmtime.so" ]; then
  printf 'missing Wasmtime C API library: %s\n' "$wasmtime_lib/libwasmtime.so" >&2
  exit 1
fi

zig_cache_root=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-host-drive-zig-cache.XXXXXX")
trap 'rm -rf -- "$zig_cache_root"' EXIT
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$zig_cache_root/local}"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$zig_cache_root/global}"
mkdir -p "$ZIG_LOCAL_CACHE_DIR" "$ZIG_GLOBAL_CACHE_DIR"

"$zig_bin" cc \
  -I "$wasmtime_include" \
  "$repo_root/examples/p3-runtime/host_runner.c" \
  -L "$wasmtime_lib" \
  -lwasmtime \
  -Wl,-rpath,"$wasmtime_lib" \
  -o "$runner"

output=$("$runner" \
  "$repo_root/examples/p3-runtime/async-component.wat" \
  "$component" \
  "C API host-drive queue")

case "$output" in
  *"C API host-drive queue probe passed: tasks=2"*"active-futures-max=1"*"nested-call-attempts=0"*)
    printf '%s\n' "$output"
    ;;
  *)
    printf 'unexpected C API host-drive queue trace\n%s\n' "$output" >&2
    exit 1
    ;;
esac
