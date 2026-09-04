#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
fixture="$repo_root/examples/p3-runtime/cancel-wait-for-component.do"
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-cancel-lowering.XXXXXX")
trap 'rm -rf -- "$tmpdir"' EXIT
core_path="$tmpdir/cancel-wait-for.wat"
core_wasm="$tmpdir/cancel-wait-for.core.wasm"
wit_path="$tmpdir/cancel-wait-for.wit"
embedded_path="$tmpdir/cancel-wait-for.embedded.wasm"
component_path="$tmpdir/cancel-wait-for.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" \
  --p3-async-component --p3-wit-output "$wit_path" -o "$core_path"

for required in \
  "[subtask-cancel]" \
  "call \$subtask-cancel" \
  "[subtask-drop]" \
  "call \$subtask-drop" \
  "(type \$async-frame (struct" \
  "(table \$async-frames 0 (ref null \$async-frame))" \
  "table.get \$async-frames" \
  "i32.const 4"; do
  if ! grep -Fq "$required" "$core_path"; then
    printf 'pinned cancellation lowering is missing: %s\n' "$required" >&2
    exit 1
  fi
done

if grep -Fq 'global $frame-next' "$core_path"; then
  printf 'pinned cancellation lowering still uses the linear-memory frame allocator\n' >&2
  exit 1
fi

for forbidden in operation_id request_cancel CancelledAck terminal-ack; do
  if grep -Fq "$forbidden" "$core_path"; then
    printf 'pinned cancellation lowering emitted obsolete protocol name: %s\n' "$forbidden" >&2
    exit 1
  fi
done

"$toolchain_bin" parse-core "$core_path" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit_path" "$core_wasm" probe -o "$embedded_path"
"$toolchain_bin" new-component "$embedded_path" -o "$component_path"
"$toolchain_bin" validate-component "$component_path"
DO_P3_COMPONENT="$component_path" "$repo_root/examples/p3-runtime/test_rust_cancel_wait_for.sh"
