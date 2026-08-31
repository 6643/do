#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
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
"$toolchain_bin" parse-core "$wat" -o "$core"
assembly_output=$(bash "$repo_root/examples/p3-runtime/assemble_async_component.sh" \
    "$wit" "$core" probe "$component")
grep -Fq 'target=wasmtime-p3' <<<"$assembly_output"
grep -Fq 'async-names=legacy' <<<"$assembly_output"
grep -Fq 'toolchain-adapter=current-only' <<<"$assembly_output"

test -s "$component"
"$toolchain_bin" validate-component "$component"
"$toolchain_bin" print-component "$component" >"$work_dir/component.wat"
grep -Fq '[async-lift]run' "$work_dir/component.wat"
grep -Fq '[callback][async-lift]run' "$work_dir/component.wat"
grep -Fq '[task-return]run' "$work_dir/component.wat"
DO_P3_COMPONENT="$component" bash "$repo_root/examples/p3-runtime/test_rust_wait_for.sh"

if DO_TOOLCHAIN_BIN=/bin/sh bash "$repo_root/examples/p3-runtime/assemble_async_component.sh" \
    "$wit" "$core" probe "$work_dir/rejected.component.wasm" >/dev/null 2>&1; then
    printf 'assembly helper accepted an unpinned wasm-tools binary\n' >&2
    exit 1
fi

printf 'wasmtime-p3 assembly passed\n'
