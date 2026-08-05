#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-single-await-post-compute.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_path="$tmp_dir/single-await.wat"
wit_path="$tmp_dir/single-await.wit"
embedded_path="$tmp_dir/single-await.embedded.wasm"
component_path="$tmp_dir/single-await.component.wasm"
stderr_path="$tmp_dir/single-await.stderr"

if ! DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/single-await-post-compute-component.do" \
  --p3-async-component --p3-wit-output "$wit_path" -o "$core_path" \
  >"$tmp_dir/single-await.stdout" 2>"$stderr_path"; then
  cat "$stderr_path" >&2
  printf 'single-await post-compute fixture failed before emitter implementation\n' >&2
  exit 1
fi

grep -Fq '[async-slot] deadline' "$core_path"
grep -Fq 'struct.get $async-frame $state' "$core_path"
if [ "$(grep -Fc 'struct.get $async-frame $slot-deadline' "$core_path")" -lt 2 ] || \
   ! grep -Fq $'struct.get $async-frame $slot-deadline\n        i64.const 1\n        i64.add' "$core_path"; then
  printf 'single-await post-compute emitter did not lower the post-await add from the frame slot\n' >&2
  exit 1
fi
if [ "$(grep -Fc 'call $first-host-call' "$core_path")" -ne 1 ]; then
  printf 'single-await post-compute emitter replayed the host call after await\n' >&2
  exit 1
fi

wasm-tools component embed "$wit_path" "$core_path" --world probe -o "$embedded_path"
wasm-tools component new "$embedded_path" -o "$component_path"
wasm-tools validate "$component_path"
DO_P3_COMPONENT="$component_path" \
DO_P3_CLOCK_INPUT=27815 \
DO_P3_CLOCK_EXPECTED_DURATION=27816 \
  bash "$repo_root/examples/p3-runtime/test_rust_wait_for.sh"

if DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/single-await-post-compute-component.do" \
  -o "$tmp_dir/ordinary.wat" >"$tmp_dir/ordinary.stdout" 2>"$tmp_dir/ordinary.stderr"; then
  printf 'ordinary do build unexpectedly lowered async source\n' >&2
  exit 1
fi
grep -Fq 'AsyncLoweringUnavailable' "$tmp_dir/ordinary.stderr"
printf 'single-await post-compute emitter contract passed\n'
