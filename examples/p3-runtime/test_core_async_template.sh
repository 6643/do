#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
wit="$repo_root/examples/p3-runtime/wit/async-core-template.wit"
core="$repo_root/examples/p3-runtime/core-async-template.wat"
component=$(mktemp "${TMPDIR:-/tmp}/do-p3-core-async-component.XXXXXX.wasm")
trap 'rm -f -- "$component"' EXIT

test -x "$toolchain_bin"
"$toolchain_bin" new-component "$core" -o "$component"
"$toolchain_bin" component-targets "$wit" "$component" --world probe

DO_P3_COMPONENT="$component" bash "$repo_root/examples/p3-runtime/test_rust_wait_for.sh"
