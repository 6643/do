#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/wit/async-core-template.wit"
core="$repo_root/examples/p3-runtime/core-async-template.wat"
component=$(mktemp "${TMPDIR:-/tmp}/do-p3-core-async-component.XXXXXX.wasm")
trap 'rm -f -- "$component"' EXIT

wasm-tools component new "$core" -o "$component"
wasm-tools component targets "$wit" "$component" --world probe

DO_P3_COMPONENT="$component" bash "$repo_root/examples/p3-runtime/test_rust_wait_for.sh"
