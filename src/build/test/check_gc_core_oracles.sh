#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${WASMTIME_BIN:?RUN_GC_CORE=1 requires WASMTIME_BIN}"

for probe in \
    text_identity \
    text_identity_renamed \
    list_set \
    parameterized_list_set \
    parameterized_list_set_renamed \
    managed_struct_set \
    managed_struct_renamed \
    managed_struct_preserve_field \
    managed_tuple_text_bytes
do
    WASMTIME_BIN="$WASMTIME_BIN" bash "$ROOT/examples/gc-p3-runtime/test_do_gc_${probe}.sh"
done
