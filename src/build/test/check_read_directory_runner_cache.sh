#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

for gate in \
    test_rust_wasi_filesystem_read_directory.sh \
    test_rust_wasi_filesystem_read_directory_bounded.sh; do
    path="$ROOT_DIR/examples/p3-runtime/$gate"
    if ! rg -q 'ZIG_LOCAL_CACHE_DIR=' "$path" ||
       ! rg -q 'ZIG_GLOBAL_CACHE_DIR=' "$path" ||
       ! rg -q 'mkdir -p' "$path"; then
        printf '[FAIL] %s does not establish isolated Zig caches for the Rust runner\n' "$gate" >&2
        exit 1
    fi
done

for host_smoke in \
    build_and_run.sh \
    test_c_api_host_drive_queue.sh; do
    path="$ROOT_DIR/examples/p3-runtime/$host_smoke"
    if ! rg -q 'ZIG_LOCAL_CACHE_DIR=' "$path" ||
       ! rg -q 'ZIG_GLOBAL_CACHE_DIR=' "$path" ||
       ! rg -q 'mkdir -p' "$path"; then
        printf '[FAIL] %s does not establish isolated Zig caches for the C host smoke\n' "$host_smoke" >&2
        exit 1
    fi
done

wrapper="$ROOT_DIR/examples/p3-runtime/rust-host-runner/zig-cc.sh"
if ! rg -q 'ZIG_LOCAL_CACHE_DIR=' "$wrapper" ||
   ! rg -q 'ZIG_GLOBAL_CACHE_DIR=' "$wrapper" ||
   ! rg -q 'mkdir -p' "$wrapper"; then
    printf '[FAIL] rust-host-runner/zig-cc.sh does not establish isolated Zig caches\n' >&2
    exit 1
fi

printf '[PASS] P3 Rust and C host gates establish isolated Zig caches\n'
