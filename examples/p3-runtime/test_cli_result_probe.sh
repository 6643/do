#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-cli-result.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wasm-tools component embed "$repo_root/examples/p3-runtime/cli-result-probe.wit" \
  "$repo_root/examples/p3-runtime/cli-result-probe.wat" --world probe -o "$tmp_dir/embedded.wasm"
wasm-tools component new "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
DO_P3_COMPONENT="$tmp_dir/component.wasm" "$repo_root/examples/p3-runtime/test_rust_cli_result.sh"
