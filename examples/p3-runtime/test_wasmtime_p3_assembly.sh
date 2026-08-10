#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-wasmtime-p3.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

source="$repo_root/examples/p3-runtime/wait-for-component.do"
wat="$work_dir/core.wat"
wit="$work_dir/component.wit"
core="$work_dir/core.wasm"
component="$work_dir/wasmtime-p3.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$source" \
    --p3-async-component --p3-wit-output "$wit" -o "$wat"
grep -Fq '[async-lower]wait-for' "$wat"
grep -Fq '[callback][async-lift]run' "$wat"
wasm-tools parse "$wat" -o "$core"
assembly_output=$(bash "$repo_root/examples/p3-runtime/assemble_async_component.sh" \
    "$wit" "$core" probe "$component")
grep -Fq 'target=wasmtime-p3' <<<"$assembly_output"
grep -Fq 'async-names=legacy' <<<"$assembly_output"
grep -Fq 'wasm-tools=wasm-tools 1.255.0 (76e20611d 2026-07-30)' <<<"$assembly_output"
grep -Fq 'sha256=6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013' <<<"$assembly_output"

test -s "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"
wasm-tools print "$component" >"$work_dir/component.wat"
grep -Fq '[async-lift]run' "$work_dir/component.wat"
grep -Fq '[callback][async-lift]run' "$work_dir/component.wat"
grep -Fq '[task-return]run' "$work_dir/component.wat"
DO_P3_COMPONENT="$component" bash "$repo_root/examples/p3-runtime/test_rust_wait_for.sh"

if WASM_TOOLS=/bin/sh bash "$repo_root/examples/p3-runtime/assemble_async_component.sh" \
    "$wit" "$core" probe "$work_dir/rejected.component.wasm" >/dev/null 2>&1; then
    printf 'assembly helper accepted an unpinned wasm-tools binary\n' >&2
    exit 1
fi

printf 'wasmtime-p3 assembly passed\n'
