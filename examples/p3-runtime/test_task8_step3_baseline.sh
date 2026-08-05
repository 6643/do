#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

run_gate() {
    local name=$1
    shift
    printf '[baseline] %s\n' "$name"
    "$@"
    printf 'baseline %s: PASS\n' "$name"
}

run_gate cancel-wait-for bash "$repo_root/examples/p3-runtime/test_rust_cancel_wait_for.sh"
run_gate scalar-result bash "$repo_root/examples/p3-runtime/test_rust_scalar_result.sh"
run_gate resource-result bash "$repo_root/examples/p3-runtime/test_rust_async_resource_result.sh"
run_gate stream-reader bash "$repo_root/examples/p3-runtime/test_rust_stream_reader_descriptor.sh"
run_gate stream-writer bash "$repo_root/examples/p3-runtime/test_rust_stream_writer.sh"
run_gate filesystem bash "$repo_root/examples/p3-runtime/test_rust_wasi_filesystem_preopen.sh"
run_gate sockets bash "$repo_root/examples/p3-runtime/test_rust_wasi_sockets_real.sh"

printf 'Task 8 Step 3 runtime baseline: PASS\n'
