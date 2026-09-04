#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-$repo_root/bin/do}
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
fixture="$repo_root/examples/p3-runtime/async-resource-result-component.do"
expected_wit="$repo_root/src/build/p3_async_resource_probe.wit"
host_gate="$repo_root/examples/p3-runtime/test_rust_async_resource_result.sh"
cancel_shape_gate="$repo_root/examples/p3-runtime/test_do_resource_cancellation_shape.sh"
cancel_host_gate="$repo_root/examples/p3-runtime/test_rust_resource_cancellation_shape.sh"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-resource-terminal.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler: %s\n' "$do_bin" >&2
  exit 1
fi
if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi
if [ ! -f "$fixture" ] || [ ! -f "$expected_wit" ]; then
  printf 'missing resource terminal fixture or WIT: fixture=%s wit=%s\n' "$fixture" "$expected_wit" >&2
  exit 1
fi

wat_path="$tmp_dir/async-resource-result.wat"
wit_path="$tmp_dir/async-resource-result.wit"
core_path="$tmp_dir/async-resource-result.core.wasm"
embedded_path="$tmp_dir/async-resource-result.embedded.wasm"
component_path="$tmp_dir/async-resource-result.component.wasm"

(cd "$repo_root" && DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
  --p3-async-component --p3-wit-output "$wit_path" -o "$wat_path"
)
cmp "$expected_wit" "$wit_path"

if grep -Fq '__arc_' "$wat_path"; then
  printf 'resource terminal GC output contains ARC markers\n' >&2
  exit 1
fi
for marker in \
  '(type $async-frame (struct' \
  '(table $async-frames 0 (ref null $async-frame))' \
  '(field $slot-result-ptr (mut i32))' \
  '[resource-drop]request' \
  '[resource-drop]response' \
  '$result-buffer-for-handle' \
  '[resource-result-error-terminal]' \
  '$canonical-buffer-release' \
  '$frame-free' \
  'call $task-return'; do
  if ! grep -Fq "$marker" "$wat_path"; then
    printf 'resource terminal GC output is missing marker: %s\n' "$marker" >&2
    exit 1
  fi
done
if grep -Fq 'global $frame-next' "$wat_path"; then
  printf 'resource terminal GC output still uses linear-memory frame allocation\n' >&2
  exit 1
fi
for forbidden in 'call $drop-request' 'call $drop-response'; do
  if grep -Fq "$forbidden" "$wat_path"; then
    printf 'resource drop escaped the Component boundary: %s\n' "$forbidden" >&2
    exit 1
  fi
done

"$toolchain_bin" parse-core "$wat_path" -o "$core_path"
"$toolchain_bin" compile-core-gc "$wat_path" -o "$tmp_dir/async-resource-result.compiled"
"$toolchain_bin" embed-component "$wit_path" "$core_path" async-resource-probe \
  --features component-async -o "$embedded_path"
"$toolchain_bin" new-component "$embedded_path" -o "$component_path"
"$toolchain_bin" validate-component "$component_path" --features component-async

# The existing Rust/Wasmtime adapter executes pending, immediate, and error
# terminal paths and asserts exactly-once request/response cleanup. Keep it
# behind an explicit switch so structural gate debugging can remain isolated.
if [ "${RUN_RESOURCE_HOST:-1}" = 1 ]; then
  PATH="$(dirname "$toolchain_bin"):$PATH" bash "$host_gate"
  PATH="$(dirname "$toolchain_bin"):$PATH" bash "$cancel_shape_gate"
  PATH="$(dirname "$toolchain_bin"):$PATH" bash "$cancel_host_gate"
fi

printf 'Do bounded GC resource terminal cleanup passed: fixture=%s\n' \
  "$(basename "$fixture")"
