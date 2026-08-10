#!/usr/bin/env bash
set -euo pipefail

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
if [[ "$actual_version" != "$expected_version" ]]; then
    printf 'unexpected wasm-tools version: expected %s, got %s\n' \
        "$expected_version" "$actual_version" >&2
    exit 1
fi
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    printf 'unexpected wasm-tools hash: expected %s, got %s\n' \
        "$expected_sha256" "$actual_sha256" >&2
    exit 1
fi

legacy_refs=$(rg -n \
    -e '1\.254\.0' \
    -e 'legacy_wasm_tools' \
    -e 'LEGACY_WASM_TOOLS' \
    -e 'assemble_wasmtime_p3_legacy\.sh' \
    --glob '*.sh' examples/p3-runtime src/build/test \
    | rg -v 'test_wasm_tools_current_only\.sh' || true)
if [[ -n "$legacy_refs" ]]; then
    printf 'active wasm-tools legacy references remain:\n%s\n' "$legacy_refs" >&2
    exit 1
fi

printf 'wasm-tools current-only guard passed: version=%s sha256=%s\n' \
    "$actual_version" "$actual_sha256"
