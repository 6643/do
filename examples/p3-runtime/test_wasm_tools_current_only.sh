#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLCHAIN_BIN="${DO_TOOLCHAIN_BIN:-$ROOT_DIR/bin/do-toolchain}"
[[ -x "$TOOLCHAIN_BIN" ]] || {
    printf 'missing do-toolchain executable: %s\n' "$TOOLCHAIN_BIN" >&2
    exit 1
}
probe_output=$("$TOOLCHAIN_BIN" probe)
if [[ "$probe_output" != *'"schema":1'* ]]; then
    printf 'do-toolchain probe returned no schema marker\n' >&2
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

printf 'wasm-tools current-only guard passed through do-toolchain adapter\n'
