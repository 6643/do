#!/usr/bin/env bash
set -euo pipefail

# Current Component assembly entrypoint. The async name-mangling mode remains
# `--dummy-names legacy`, but the only accepted executable is wasm-tools 1.255.0.
if (($# != 4)); then
    printf 'usage: %s <wit> <core-wasm> <world> <component-wasm>\n' "$0" >&2
    exit 2
fi

wit_path=$1
core_path=$2
world_name=$3
component_path=$4
wasm_tools=${WASM_TOOLS:-wasm-tools}
if [[ "$wasm_tools" == */* ]]; then
    [[ -x "$wasm_tools" ]] || {
        printf 'missing executable wasm-tools: %s\n' "$wasm_tools" >&2
        exit 1
    }
else
    wasm_tools=$(command -v "$wasm_tools" || true)
    [[ -n "$wasm_tools" ]] || {
        printf 'missing executable wasm-tools\n' >&2
        exit 1
    }
fi

expected_version='wasm-tools 1.255.0 (76e20611d 2026-07-30)'
expected_sha256='6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013'
actual_version=$($wasm_tools --version)
actual_sha256=$(sha256sum "$wasm_tools" | awk '{print $1}')
[[ "$actual_version" == "$expected_version" ]] || {
    printf 'unexpected wasm-tools version: expected %s, got %s\n' \
        "$expected_version" "$actual_version" >&2
    exit 1
}
[[ "$actual_sha256" == "$expected_sha256" ]] || {
    printf 'unexpected wasm-tools hash: expected %s, got %s\n' \
        "$expected_sha256" "$actual_sha256" >&2
    exit 1
}

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-wasmtime-p3.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT
embedded_path="$work_dir/embedded.wasm"

"$wasm_tools" component embed "$wit_path" "$core_path" \
    --world "$world_name" \
    --features cm-async,cm-more-async-builtins \
    -o "$embedded_path"
"$wasm_tools" component new --skip-validation "$embedded_path" -o "$component_path"
"$wasm_tools" validate --features cm-async,cm-more-async-builtins "$component_path"

printf 'target=wasmtime-p3 wasm-tools=%s sha256=%s async-names=legacy callback=enabled\n' \
    "$actual_version" "$actual_sha256"
