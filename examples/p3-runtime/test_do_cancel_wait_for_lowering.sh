#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$repo_root/examples/p3-runtime/cancel-wait-for-component.do"
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-cancel-lowering.XXXXXX")
trap 'rm -rf -- "$tmpdir"' EXIT
core_path="$tmpdir/cancel-wait-for.wat"
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

wasm-tools component embed "$wit_path" "$core_path" --world probe -o "$embedded_path"
wasm-tools component new "$embedded_path" -o "$component_path"
wasm-tools validate "$component_path"
DO_P3_COMPONENT="$component_path" "$repo_root/examples/p3-runtime/test_rust_cancel_wait_for.sh"
