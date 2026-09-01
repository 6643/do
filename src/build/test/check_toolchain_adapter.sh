#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TOOLCHAIN_BIN="$ROOT_DIR/bin/do-toolchain"
LOCK_FILE="$ROOT_DIR/toolchain/toolchain.lock.json"

if [[ ! -f "$LOCK_FILE" ]]; then
    printf '[FAIL] missing toolchain lock: %s\n' "$LOCK_FILE" >&2
    exit 1
fi
if [[ ! -x "$TOOLCHAIN_BIN" ]]; then
    printf '[FAIL] missing do-toolchain executable: %s\n' "$TOOLCHAIN_BIN" >&2
    exit 1
fi

probe_output="$(
    cd "$ROOT_DIR"
    DO_TOOLCHAIN_LOCK="$LOCK_FILE" "$TOOLCHAIN_BIN" probe
)" || {
    printf '[FAIL] do-toolchain probe failed\n' >&2
    exit 1
}

for marker in '"schema":1' '"wasm_tools":' '"wasmtime":' '"rust_wasmtime":'; do
    if [[ "$probe_output" != *"$marker"* ]]; then
        printf '[FAIL] toolchain probe missing marker: %s\n' "$marker" >&2
        exit 1
    fi
done

scan_args=(
    --glob '*.sh'
    --glob '!**/tmp/**'
    --glob '!test_wasm_tools_current_only.sh'
    --glob '!check_toolchain_adapter.sh'
    --glob '!check_toolchain_adapter_test.sh'
)

direct_tool_refs="$(rg -n --pcre2 \
    '(?:^|[;&|()[:space:]])"?\$?(?:WASM_TOOLS_BIN|wasm_tools_bin|wasm-tools)"?[[:space:]]+(?:parse|component|validate|--version)(?:[[:space:]]|$)' \
    "${scan_args[@]}" "$ROOT_DIR/examples" "$ROOT_DIR/src/build/test" || true)"
if [[ -n "$direct_tool_refs" ]]; then
    printf '[FAIL] active shell invokes wasm-tools directly:\n%s\n' "$direct_tool_refs" >&2
    exit 1
fi

legacy_refs="$(rg -n \
    -e '1\.254\.0' \
    -e '1\.255\.0' \
    -e 'legacy_wasm_tools' \
    -e 'LEGACY_WASM_TOOLS' \
    -e 'assemble_wasmtime_p3_legacy\.sh' \
    --glob '*.sh' \
    --glob '!**/tmp/**' \
    --glob '!test_wasm_tools_current_only.sh' \
    --glob '!check_toolchain_adapter.sh' \
    --glob '!check_toolchain_adapter_test.sh' \
    "$ROOT_DIR/examples" "$ROOT_DIR/src/build/test" || true)"
if [[ -n "$legacy_refs" ]]; then
    printf '[FAIL] active shell contains legacy toolchain references:\n%s\n' "$legacy_refs" >&2
    exit 1
fi

printf '[PASS] toolchain adapter active gate\n'
