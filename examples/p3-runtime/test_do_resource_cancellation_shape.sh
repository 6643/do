#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/resource-cancel-shape.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_path="$tmp_dir/cancel.wat"
wit_path="$tmp_dir/cancel.wit"
core_wasm="$tmp_dir/cancel.wasm"
embedded_path="$tmp_dir/cancel.embedded.wasm"
component_path="$tmp_dir/cancel.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  --p3-async-component \
  "$repo_root/examples/p3-runtime/async-resource-result-cancel-component.do" \
  --p3-wit-output "$wit_path" -o "$core_path"

for required in \
  '[resource-result-cancel]' \
  '[task-cancel]' \
  '[subtask-cancel]' \
  'call $subtask-cancel' \
  '[subtask-drop]' \
  'call $subtask-drop' \
  '[task-return]cancel' \
  '(export "[async-lift]cancel")'; do
  if ! grep -Fq "$required" "$core_path"; then
    printf 'resource Result cancellation lowering is missing: %s\n' "$required" >&2
    exit 1
  fi
done

for forbidden in operation_id request_cancel CancelledAck terminal-ack; do
  if grep -Fq "$forbidden" "$core_path"; then
    printf 'resource Result cancellation emitted obsolete protocol name: %s\n' "$forbidden" >&2
    exit 1
  fi
done

if grep -Fq '$async-frame' "$core_path"; then
  printf 'nil-returning resource cancellation unexpectedly allocated a result frame\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$core_path" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit_path" "$core_wasm" \
  async-resource-cancel-probe -o "$embedded_path"
"$toolchain_bin" new-component "$embedded_path" -o "$component_path"
"$toolchain_bin" validate-component "$component_path" --features component-async

for rejected in \
  async-resource-result-cancel-double.do \
  async-resource-result-cancel-drop.do \
  async-resource-result-cancel-after-terminal.do; do
  stderr_path="$tmp_dir/$rejected.stderr"
  if DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
    --p3-async-component "$repo_root/examples/p3-runtime/$rejected" \
    -o "$tmp_dir/$rejected.wat" >"$tmp_dir/$rejected.stdout" 2>"$stderr_path"; then
    printf 'invalid resource cancellation shape unexpectedly lowered: %s\n' "$rejected" >&2
    exit 1
  fi
  expected_error=FutureDropped
  case "$rejected" in
    async-resource-result-cancel-double.do|async-resource-result-cancel-after-terminal.do)
      expected_error=FutureAlreadyConsumed
      ;;
  esac
  grep -Fq "$expected_error" "$stderr_path"
done

"$toolchain_bin" parse-core "$repo_root/examples/p3-runtime/resource-result-cancel-probe.wat" \
  -o "$tmp_dir/probe.wasm"
"$toolchain_bin" embed-component \
  "$repo_root/examples/p3-runtime/resource-result-cancel-probe.wit" \
  "$tmp_dir/probe.wasm" async-resource-cancel-probe \
  -o "$tmp_dir/probe.embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/probe.embedded.wasm" \
  -o "$tmp_dir/probe.component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/probe.component.wasm" \
  --features component-async

printf 'resource Result cancellation lowering, negative boundaries, and pinned assembly passed\n'
