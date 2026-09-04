#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-cli-result.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

"$toolchain_bin" parse-core "$repo_root/examples/p3-runtime/cli-result-probe.wat" \
  -o "$tmp_dir/core.wasm"
"$toolchain_bin" embed-component "$repo_root/examples/p3-runtime/cli-result-probe.wit" \
  "$tmp_dir/core.wasm" probe -o "$tmp_dir/embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
DO_P3_COMPONENT="$tmp_dir/component.wasm" "$repo_root/examples/p3-runtime/test_rust_cli_result.sh"
