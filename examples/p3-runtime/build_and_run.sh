#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
zig_bin=${ZIG_BIN:-/snap/bin/zig}
wasmtime_include=/home/_/Public/wasmtime/c-api/include
wasmtime_lib=/home/_/Public/wasmtime/c-api/lib
runner=/tmp/do-p3-host-runner
component=/tmp/do-p3-async-component.wasm
gc_component=/tmp/do-p3-async-gc-component.wasm
p3_wait_for_component=/tmp/do-p3-wait-for-component.wasm

if [ ! -x "$zig_bin" ]; then
  printf 'missing Zig compiler: %s\n' "$zig_bin" >&2
  exit 1
fi
if [ ! -f "$wasmtime_lib/libwasmtime.so" ]; then
  printf 'missing Wasmtime C API library: %s\n' "$wasmtime_lib/libwasmtime.so" >&2
  exit 1
fi

"$zig_bin" cc \
  -I "$wasmtime_include" \
  "$repo_root/examples/p3-runtime/host_runner.c" \
  -L "$wasmtime_lib" \
  -lwasmtime \
  -Wl,-rpath,"$wasmtime_lib" \
  -o "$runner"

"$runner" \
  "$repo_root/examples/p3-runtime/async-component.wat" \
  "$component" \
  async

"$runner" \
  "$repo_root/examples/gc-p3-runtime/async-gc-component.wat" \
  "$gc_component" \
  "async GC"

if p3_output=$("$runner" \
  "$repo_root/examples/p3-runtime/async-wait-for-component.wat" \
  "$p3_wait_for_component" \
  "P3 wait-for" 2>&1); then
  printf 'P3 wait-for probe unexpectedly linked; inspect the host callback trace before changing this gate\n' >&2
  printf '%s\n' "$p3_output" >&2
  exit 1
fi

case "$p3_output" in
  *"has the wrong type"*"type mismatch with async"*)
    printf 'P3 wait-for component ABI probe: blocked (C linker cannot define a WIT async function)\n'
    ;;
  *)
    printf 'P3 wait-for probe failed for an unexpected reason\n' >&2
    printf '%s\n' "$p3_output" >&2
    exit 1
    ;;
esac
