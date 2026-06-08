#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_DIR="$ROOT_DIR/tool/build/test"
RUN_DIR="$TEST_DIR/run"
LIB_DIR="$TEST_DIR/lib"
TMP_DIR="$TEST_DIR/tmp/wasm_run"

ZIG_BIN="${ZIG_BIN:-$(command -v zig || true)}"
ZIG_BIN="${ZIG_BIN:-/home/_/_/zig/zig}"
DO_BIN="$ROOT_DIR/bin/do"
WASM_TOOLS="${WASM_TOOLS:-$(command -v wasm-tools || true)}"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"

pass_count=0
fail_count=0

mkdir -p "$TMP_DIR"
rm -f "$TMP_DIR"/* 2>/dev/null || true

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    if [[ ! -x "$ZIG_BIN" ]]; then
        echo "[FAIL] zig binary not found: $ZIG_BIN"
        exit 1
    fi
    (
        cd "$ROOT_DIR/tool"
        ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache \
        ZIG_GLOBAL_CACHE_DIR=/tmp/zig-gcache \
        "$ZIG_BIN" build -Doptimize=Debug >/dev/null
    )
fi

if [[ ! -x "$DO_BIN" ]]; then
    echo "[FAIL] compiler binary not found: $DO_BIN"
    exit 1
fi
if [[ -z "$WASM_TOOLS" || ! -x "$WASM_TOOLS" ]]; then
    echo "[FAIL] wasm-tools not found"
    exit 1
fi
if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
    echo "[FAIL] node not found"
    exit 1
fi

run_case() {
    local case_file="$1"
    local name
    name="$(basename "$case_file" .do)"

    local wat_file="$TMP_DIR/$name.wat"
    local wasm_file="$TMP_DIR/$name.wasm"
    local stdout_file="$TMP_DIR/$name.stdout"
    local stderr_file="$TMP_DIR/$name.stderr"
    local expect_file="${case_file%.do}.stdout.expect"

    if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" build "$case_file" -o "$wat_file" >"$TMP_DIR/$name.build.stdout" 2>"$TMP_DIR/$name.build.stderr"; then
        echo "[FAIL] wasm run $name (build failed)"
        cat "$TMP_DIR/$name.build.stderr"
        ((fail_count += 1))
        return
    fi

    if ! "$WASM_TOOLS" parse "$wat_file" -o "$wasm_file" >"$TMP_DIR/$name.parse.stdout" 2>"$TMP_DIR/$name.parse.stderr"; then
        echo "[FAIL] wasm run $name (wat parse failed)"
        cat "$TMP_DIR/$name.parse.stderr"
        ((fail_count += 1))
        return
    fi

    if ! "$NODE_BIN" "$TEST_DIR/run_wasm_case.mjs" "$wasm_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] wasm run $name (execution failed)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if [[ -f "$expect_file" ]]; then
        if ! diff -u "$expect_file" "$stdout_file"; then
            echo "[FAIL] wasm run $name (stdout mismatch)"
            ((fail_count += 1))
            return
        fi
    elif [[ -s "$stdout_file" ]]; then
        echo "[FAIL] wasm run $name (unexpected stdout)"
        cat "$stdout_file"
        ((fail_count += 1))
        return
    fi

    echo "[PASS] wasm run $name"
    ((pass_count += 1))
}

for case_file in "$RUN_DIR"/*.do; do
    [[ -e "$case_file" ]] || continue
    run_case "$case_file"
done

echo "[INFO] wasm run summary: pass=$pass_count fail=$fail_count"
if [[ "$fail_count" -ne 0 ]]; then
    exit 1
fi
