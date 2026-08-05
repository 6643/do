#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-cli-result-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_path="$tmp_dir/cli-result.wat"
wit_path="$tmp_dir/cli-result.wit"
embedded_path="$tmp_dir/cli-result.embedded.wasm"
component_path="$tmp_dir/cli-result.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/cli-run-result-component.do" \
  --p3-async-component --p3-wit-output "$wit_path" -o "$core_path"

grep -Fq 'wasi:cli/run@0.3.0' "$core_path"
grep -Fq '[async-lower]run' "$core_path"
grep -Fq '(type $task-return (func (param i32)))' "$core_path"
grep -Fq 'i32.eqz' "$core_path"
grep -Fq 'run: async func() -> result' "$wit_path"

wasm-tools component embed "$wit_path" "$core_path" --world probe -o "$embedded_path"
wasm-tools component new "$embedded_path" -o "$component_path"
DO_P3_COMPONENT="$component_path" "$repo_root/examples/p3-runtime/test_rust_cli_result.sh"
