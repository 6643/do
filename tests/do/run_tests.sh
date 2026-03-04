#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$ROOT_DIR/tests/do"
OK_DIR="$TEST_DIR/cases/ok"
ERR_DIR="$TEST_DIR/cases/err"
TMP_DIR="$TEST_DIR/tmp"

ZIG_BIN="${ZIG_BIN:-/home/_/_/zig/zig}"
DO_BIN="$ROOT_DIR/bin/do"

pass_count=0
fail_count=0

mkdir -p "$TMP_DIR"
rm -f "$TMP_DIR"/*.stdout "$TMP_DIR"/*.stderr 2>/dev/null || true

if [[ ! -x "$ZIG_BIN" ]]; then
    echo "[FAIL] zig binary not found: $ZIG_BIN"
    exit 1
fi

echo "[INFO] build compiler"
(
    cd "$ROOT_DIR/compiler"
    ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache \
    ZIG_GLOBAL_CACHE_DIR=/tmp/zig-gcache \
    "$ZIG_BIN" build -Doptimize=Debug >/dev/null
)

if [[ ! -x "$DO_BIN" ]]; then
    echo "[FAIL] compiler binary not found: $DO_BIN"
    exit 1
fi

run_ok_case() {
    local case_file="$1"
    local name
    name="$(basename "$case_file" .do)"

    local stdout_file="$TMP_DIR/${name}.stdout"
    local stderr_file="$TMP_DIR/${name}.stderr"

    if "$DO_BIN" test "$case_file" >"$stdout_file" 2>"$stderr_file"; then
        if grep -Fq 'test "' "$stdout_file" && grep -Fq " ... ok" "$stdout_file" && grep -Fq "ok:" "$stdout_file"; then
            echo "[PASS] ok  $name"
            ((pass_count += 1))
            return
        fi

        echo "[FAIL] ok  $name (missing success marker)"
        cat "$stdout_file"
        ((fail_count += 1))
        return
    fi

    echo "[FAIL] ok  $name (unexpected non-zero exit)"
    cat "$stderr_file"
    ((fail_count += 1))
}

run_err_case() {
    local case_file="$1"
    local name
    name="$(basename "$case_file" .do)"

    local stdout_file="$TMP_DIR/${name}.stdout"
    local stderr_file="$TMP_DIR/${name}.stderr"
    local expect_file="${case_file%.do}.expect"

    if [[ ! -f "$expect_file" ]]; then
        echo "[FAIL] err $name (missing expect file: $expect_file)"
        ((fail_count += 1))
        return
    fi

    if "$DO_BIN" test "$case_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] err $name (expected failure, got success)"
        cat "$stdout_file"
        ((fail_count += 1))
        return
    fi

    local missing=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        [[ "${line:0:1}" == "#" ]] && continue
        if grep -Fq "$line" "$stderr_file"; then
            continue
        fi
        echo "[FAIL] err $name (missing expected text: $line)"
        missing=1
    done < "$expect_file"

    if [[ "$missing" -eq 0 ]]; then
        echo "[PASS] err $name"
        ((pass_count += 1))
        return
    fi

    echo "[INFO] stderr output for $name:"
    cat "$stderr_file"
    ((fail_count += 1))
}

echo "[INFO] run ok cases"
for case_file in "$OK_DIR"/*.do; do
    [[ -e "$case_file" ]] || continue
    run_ok_case "$case_file"
done

echo "[INFO] run err cases"
for case_file in "$ERR_DIR"/*.do; do
    [[ -e "$case_file" ]] || continue
    run_err_case "$case_file"
done

echo "[INFO] summary: pass=$pass_count fail=$fail_count"
if [[ "$fail_count" -ne 0 ]]; then
    exit 1
fi
