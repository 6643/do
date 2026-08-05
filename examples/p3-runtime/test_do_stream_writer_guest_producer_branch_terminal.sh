#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-stream-writer-branch-terminal.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_path="$tmp_dir/branch-terminal.wat"
wit_path="$tmp_dir/branch-terminal.wit"
core_wasm="$tmp_dir/branch-terminal.core.wasm"
embedded_path="$tmp_dir/branch-terminal.embedded.wasm"
component_path="$tmp_dir/branch-terminal.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
  --p3-wit-output "$wit_path" \
  "$repo_root/examples/p3-runtime/stream-probe-guest-producer-branch-terminal.do" \
  -o "$core_path"

cmp "$wit_path" "$repo_root/examples/p3-runtime/wit/stream-probe-guest-producer-branch-terminal.wit"
for marker in \
  '[writer-endpoint-mode] guest-producer' \
  '[writer-lease-transfer] async-helper' \
  '[writer-terminal] branch-abort-pipe selector=90 code=2' \
  '(func $writer-abort' \
  '(func (export "[async-lift]produce") (type $async-run-i64-i32)'; do
  grep -Fq "$marker" "$core_path"
done

wasm-tools parse "$core_path" -o "$core_wasm"
wasm-tools component embed "$wit_path" "$core_wasm" \
  --world stream-writer-probe -o "$embedded_path"
wasm-tools component new "$embedded_path" -o "$component_path"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component_path"

negative_stderr="$tmp_dir/negative.stderr"
if DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
  "$repo_root/examples/p3-runtime/stream-probe-guest-producer-branch-terminal-dynamic.do" \
  -o "$tmp_dir/negative.wat" >"$tmp_dir/negative.stdout" 2>"$negative_stderr"; then
  printf 'dynamic abort code unexpectedly lowered\n' >&2
  exit 1
fi
grep -Fq 'UnsupportedP3AsyncComponent' "$negative_stderr"

printf 'branch terminal producer Component lowering passed\n'
