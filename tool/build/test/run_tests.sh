#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_DIR="$ROOT_DIR/tool/build/test"
OK_DIR="$TEST_DIR/ok"
ERR_DIR="$TEST_DIR/err"
LIB_DIR="$TEST_DIR/lib"
COMPILE_OK_DIR="$TEST_DIR/compile_ok"
COMPILE_ERR_DIR="$TEST_DIR/compile_err"
PENDING_OK_DIR="$TEST_DIR/pending/ok"
PENDING_ERR_DIR="$TEST_DIR/pending/err"
TMP_DIR="$TEST_DIR/tmp"
RUN_PENDING="${RUN_PENDING:-0}"
SKIP_BUILD="${SKIP_BUILD:-0}"

ZIG_BIN="${ZIG_BIN:-$(command -v zig || true)}"
ZIG_BIN="${ZIG_BIN:-/home/_/_/zig/zig}"
DO_BIN="$ROOT_DIR/bin/do"

pass_count=0
fail_count=0

mkdir -p "$TMP_DIR"
rm -f "$TMP_DIR"/*.stdout "$TMP_DIR"/*.stderr "$TMP_DIR"/compile_*.wat 2>/dev/null || true

if [[ "$SKIP_BUILD" != "1" ]]; then
    if [[ ! -x "$ZIG_BIN" ]]; then
        echo "[FAIL] zig binary not found: $ZIG_BIN"
        exit 1
    fi

    echo "[INFO] build compiler"
    (
        cd "$ROOT_DIR/tool"
        ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache \
        ZIG_GLOBAL_CACHE_DIR=/tmp/zig-gcache \
        "$ZIG_BIN" build -Doptimize=Debug >/dev/null
    )
else
    echo "[INFO] skip build (SKIP_BUILD=1)"
fi

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

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" test "$case_file" >"$stdout_file" 2>"$stderr_file"; then
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

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" test "$case_file" >"$stdout_file" 2>"$stderr_file"; then
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

run_compile_ok_case() {
    local case_file="$1"
    local name
    name="$(basename "$case_file" .do)"

    local stdout_file="$TMP_DIR/compile_${name}.stdout"
    local stderr_file="$TMP_DIR/compile_${name}.stderr"
    local wat_file="$TMP_DIR/compile_${name}.wat"
    local expect_file="${case_file%.do}.expect"

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" build "$case_file" -o "$wat_file" >"$stdout_file" 2>"$stderr_file"; then
        if grep -Fq "ok:" "$stdout_file" && [[ -s "$wat_file" ]]; then
            if [[ -f "$expect_file" ]]; then
                local missing=0
                while IFS= read -r line || [[ -n "$line" ]]; do
                    [[ -z "$line" ]] && continue
                    [[ "${line:0:1}" == "#" ]] && continue
                    if grep -Fq "$line" "$wat_file"; then
                        continue
                    fi
                    echo "[FAIL] compile ok  $name (missing expected wat text: $line)"
                    missing=1
                done < "$expect_file"
                if [[ "$missing" -ne 0 ]]; then
                    echo "[INFO] wat output for $name:"
                    cat "$wat_file"
                    ((fail_count += 1))
                    return
                fi
            fi
            echo "[PASS] compile ok  $name"
            ((pass_count += 1))
            return
        fi

        echo "[FAIL] compile ok  $name (missing success marker or wat output)"
        cat "$stdout_file"
        ((fail_count += 1))
        return
    fi

    echo "[FAIL] compile ok  $name (unexpected non-zero exit)"
    cat "$stderr_file"
    ((fail_count += 1))
}

run_compile_err_case() {
    local case_file="$1"
    local name
    name="$(basename "$case_file" .do)"

    local stdout_file="$TMP_DIR/compile_${name}.stdout"
    local stderr_file="$TMP_DIR/compile_${name}.stderr"
    local wat_file="$TMP_DIR/compile_${name}.wat"
    local expect_file="${case_file%.do}.expect"

    if [[ ! -f "$expect_file" ]]; then
        echo "[FAIL] compile err $name (missing expect file: $expect_file)"
        ((fail_count += 1))
        return
    fi

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" build "$case_file" -o "$wat_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] compile err $name (expected failure, got success)"
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
        echo "[FAIL] compile err $name (missing expected text: $line)"
        missing=1
    done < "$expect_file"

    if [[ "$missing" -eq 0 ]]; then
        echo "[PASS] compile err $name"
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
    [[ "$(basename "$case_file")" == fixture.*.do ]] && continue
    run_ok_case "$case_file"
done

echo "[INFO] run err cases"
for case_file in "$ERR_DIR"/*.do; do
    [[ -e "$case_file" ]] || continue
    [[ "$(basename "$case_file")" == fixture.*.do ]] && continue
    run_err_case "$case_file"
done

echo "[INFO] run compile ok cases"
for case_file in "$COMPILE_OK_DIR"/*.do; do
    [[ -e "$case_file" ]] || continue
    run_compile_ok_case "$case_file"
done

echo "[INFO] run compile err cases"
for case_file in "$COMPILE_ERR_DIR"/*.do; do
    [[ -e "$case_file" ]] || continue
    run_compile_err_case "$case_file"
done

if [[ "$RUN_PENDING" == "1" ]]; then
    echo "[INFO] pending cases track spec/impl gaps; failures here are expected until implementation catches up"
    echo "[INFO] run pending ok cases"
    for case_file in "$PENDING_OK_DIR"/*.do; do
        [[ -e "$case_file" ]] || continue
        run_ok_case "$case_file"
    done

    echo "[INFO] run pending err cases"
    for case_file in "$PENDING_ERR_DIR"/*.do; do
        [[ -e "$case_file" ]] || continue
        run_err_case "$case_file"
    done
fi

echo "[INFO] summary: pass=$pass_count fail=$fail_count"
if [[ "$fail_count" -ne 0 ]]; then
    exit 1
fi
