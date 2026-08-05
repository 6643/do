#!/usr/bin/env bash
set -euo pipefail

# v1 Component assembly contract. The async metadata emitted by this tool is
# legacy-only in wasm-tools 1.254.0, so keep the toolchain boundary explicit.
readonly target_name='wasmtime-p3-legacy'
readonly expected_version='wasm-tools 1.254.0 (bb58fdf91 2026-07-20)'
readonly expected_sha256='cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6'

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
    wasm_tools_path=$(command -v "$wasm_tools" || true)
    [[ -n "$wasm_tools_path" ]] || {
        printf 'missing executable wasm-tools: %s\n' "$wasm_tools" >&2
        exit 1
    }
    wasm_tools=$wasm_tools_path
fi

actual_version=$("$wasm_tools" --version)
if [[ "$actual_version" != "$expected_version" ]]; then
    printf 'unsupported wasm-tools for %s: expected %s, got %s\n' \
        "$target_name" "$expected_version" "$actual_version" >&2
    exit 1
fi

actual_sha256=$(sha256sum "$wasm_tools" | awk '{print $1}')
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    printf 'unexpected wasm-tools hash for %s: expected %s, got %s\n' \
        "$target_name" "$expected_sha256" "$actual_sha256" >&2
    exit 1
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-wasmtime-p3-legacy.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

# wasm-tools generates the async component-type custom section from a dummy
# Core module. Attach that section to the compiler's real Core module before
# component-new; this is the pinned v1 workaround for the legacy async path.
stripped_wasm="$work_dir/core-stripped.wasm"
stripped_wat="$work_dir/core-stripped.wat"
dummy_wat="$work_dir/dummy.wat"
with_custom_wat="$work_dir/core-with-custom.wat"
with_custom_wasm="$work_dir/core-with-custom.wasm"

"$wasm_tools" strip -a "$core_path" -o "$stripped_wasm"
"$wasm_tools" print "$stripped_wasm" >"$stripped_wat"
"$wasm_tools" component embed "$wit_path" \
    --world "$world_name" \
    --dummy-names legacy \
    --async-callback \
    -t >"$dummy_wat"

custom_line=$(grep '^  (@custom "component-type"' "$dummy_wat" || true)
if [[ -z "$custom_line" ]]; then
    printf 'missing component-type custom section for world %s\n' "$world_name" >&2
    exit 1
fi

sed '$d' "$stripped_wat" >"$with_custom_wat"
printf '%s\n' "$custom_line" ')' >>"$with_custom_wat"
"$wasm_tools" parse "$with_custom_wat" -o "$with_custom_wasm"
"$wasm_tools" component new --skip-validation "$with_custom_wasm" -o "$component_path"
"$wasm_tools" validate --features cm-async,cm-more-async-builtins "$component_path"

printf 'target=%s wasm-tools=%s sha256=%s async-names=legacy callback=enabled\n' \
    "$target_name" "$actual_version" "$actual_sha256"
