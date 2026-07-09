#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

TEST_DIR="$ROOT_DIR/tool/build/test"
LIB_DIR="$TEST_DIR/lib"
TMP_DIR="${DO_RELEASE_SMOKE_TMP_DIR:-$TEST_DIR/tmp/release_smoke}"
DO_BIN="$ROOT_DIR/bin/do"
ZIG_BIN="${ZIG_BIN:-$(command -v zig || true)}"
ZIG_BIN="${ZIG_BIN:-/home/_/_/zig/zig}"
WASM_TOOLS="${WASM_TOOLS:-$(command -v wasm-tools || true)}"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"

BUILD_INPUT="$TEST_DIR/compile_ok/01_start_entry_valid.do"
TEST_INPUT="$TEST_DIR/ok/01_path_get_single.do"
COMPILED_INPUT="$TEST_DIR/compiled_ok/01_compiled_test_entry.do"
CHECK_INPUT="$TEST_DIR/check/01_valid.do"
FMT_INPUT="$TEST_DIR/fmt/01_struct_func_indent.do"
FMT_EXPECT="$TEST_DIR/fmt/01_struct_func_indent.expect"
RUN_INPUT="$TEST_DIR/run/01_start_scalar.do"
LSP_DIR="$TEST_DIR/lsp"

fail() {
    echo "[FAIL] release smoke $1" >&2
    exit 1
}

pass() {
    echo "[PASS] release smoke $1"
}

require_exec() {
    local path="$1"
    local name="$2"

    if [[ -z "$path" || ! -x "$path" ]]; then
        fail "$name not found"
    fi
}

expect_empty_file() {
    local path="$1"
    local label="$2"

    if [[ -s "$path" ]]; then
        echo "unexpected $label:" >&2
        cat "$path" >&2
        fail "$label not empty"
    fi
}

mkdir -p "$TMP_DIR"
rm -f "$TMP_DIR"/* 2>/dev/null || true

require_exec "$ZIG_BIN" "zig"
require_exec "$NODE_BIN" "node"
require_exec "$WASM_TOOLS" "wasm-tools"

echo "[INFO] build ReleaseSmall compiler"
(
    cd "$ROOT_DIR/tool"
    ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-/tmp/zig-cache}" \
    ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-/tmp/zig-gcache}" \
    "$ZIG_BIN" build -Doptimize=ReleaseSmall >/dev/null
)
require_exec "$DO_BIN" "bin/do"
pass "ReleaseSmall build"

build_stdout="$TMP_DIR/build.stdout"
build_stderr="$TMP_DIR/build.stderr"
build_wat="$TMP_DIR/build.wat"
if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" build "$BUILD_INPUT" -o "$build_wat" >"$build_stdout" 2>"$build_stderr"; then
    cat "$build_stderr" >&2
    fail "do build"
fi
expect_empty_file "$build_stderr" "do build stderr"
grep -Fq "ok: $BUILD_INPUT -> $build_wat" "$build_stdout" || fail "do build missing success marker"
[[ -s "$build_wat" ]] || fail "do build output missing"
pass "do build"

test_stdout="$TMP_DIR/test.stdout"
test_stderr="$TMP_DIR/test.stderr"
if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" test "$TEST_INPUT" >"$test_stdout" 2>"$test_stderr"; then
    cat "$test_stderr" >&2
    fail "do test"
fi
expect_empty_file "$test_stderr" "do test stderr"
grep -Fq 'test "path get single" ... ok' "$test_stdout" || fail "do test missing case ok"
grep -Fq 'ok: 1 passed; 0 failed; 0 skipped' "$test_stdout" || fail "do test missing summary"
pass "do test"

compiled_stdout="$TMP_DIR/compiled.stdout"
compiled_stderr="$TMP_DIR/compiled.stderr"
compiled_wat="$TMP_DIR/compiled.wat"
compiled_wasm="$TMP_DIR/compiled.wasm"
compiled_run_stdout="$TMP_DIR/compiled.run.stdout"
compiled_run_stderr="$TMP_DIR/compiled.run.stderr"
if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" test "$COMPILED_INPUT" --compiled -o "$compiled_wat" >"$compiled_stdout" 2>"$compiled_stderr"; then
    cat "$compiled_stderr" >&2
    fail "do test --compiled"
fi
expect_empty_file "$compiled_stderr" "do test --compiled stderr"
[[ -s "$compiled_wat" ]] || fail "do test --compiled output missing"
"$WASM_TOOLS" parse "$compiled_wat" -o "$compiled_wasm" >"$TMP_DIR/compiled.parse.stdout" 2>"$TMP_DIR/compiled.parse.stderr" || {
    cat "$TMP_DIR/compiled.parse.stderr" >&2
    fail "compiled wat parse"
}
"$NODE_BIN" "$TEST_DIR/run_compiled_test_case.mjs" "$compiled_wasm" "$compiled_wat" >"$compiled_run_stdout" 2>"$compiled_run_stderr" || {
    cat "$compiled_run_stderr" >&2
    fail "compiled test execution"
}
expect_empty_file "$compiled_run_stderr" "compiled test stderr"
grep -Fq 'test "compiled test entry" ... ok' "$compiled_run_stdout" || fail "compiled test missing case ok"
grep -Fq 'ok: 1 passed; 0 failed' "$compiled_run_stdout" || fail "compiled test missing summary"
pass "do test --compiled"

check_stdout="$TMP_DIR/check.stdout"
check_stderr="$TMP_DIR/check.stderr"
if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" check "$CHECK_INPUT" >"$check_stdout" 2>"$check_stderr"; then
    cat "$check_stderr" >&2
    fail "do check"
fi
expect_empty_file "$check_stdout" "do check stdout"
expect_empty_file "$check_stderr" "do check stderr"
pass "do check"

fmt_stdout="$TMP_DIR/fmt.stdout"
fmt_stderr="$TMP_DIR/fmt.stderr"
fmt_formatted="$TMP_DIR/fmt_formatted.do"
fmt_write="$TMP_DIR/fmt_write.do"
fmt_write_stdout="$TMP_DIR/fmt_write.stdout"
fmt_write_stderr="$TMP_DIR/fmt_write.stderr"
if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" fmt "$FMT_INPUT" >"$fmt_stdout" 2>"$fmt_stderr"; then
    cat "$fmt_stderr" >&2
    fail "do fmt"
fi
expect_empty_file "$fmt_stderr" "do fmt stderr"
diff -u "$FMT_EXPECT" "$fmt_stdout" >/dev/null || fail "do fmt stdout mismatch"
cp "$FMT_EXPECT" "$fmt_formatted"
if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" fmt --check "$fmt_formatted" >"$TMP_DIR/fmt_check.stdout" 2>"$TMP_DIR/fmt_check.stderr"; then
    cat "$TMP_DIR/fmt_check.stderr" >&2
    fail "do fmt --check"
fi
expect_empty_file "$TMP_DIR/fmt_check.stdout" "do fmt --check stdout"
expect_empty_file "$TMP_DIR/fmt_check.stderr" "do fmt --check stderr"
cp "$FMT_INPUT" "$fmt_write"
if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" fmt --write "$fmt_write" >"$fmt_write_stdout" 2>"$fmt_write_stderr"; then
    cat "$fmt_write_stderr" >&2
    fail "do fmt --write"
fi
expect_empty_file "$fmt_write_stdout" "do fmt --write stdout"
expect_empty_file "$fmt_write_stderr" "do fmt --write stderr"
diff -u "$FMT_EXPECT" "$fmt_write" >/dev/null || fail "do fmt --write mismatch"
pass "do fmt"

run_stdout="$TMP_DIR/run.stdout"
run_stderr="$TMP_DIR/run.stderr"
if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" run "$RUN_INPUT" >"$run_stdout" 2>"$run_stderr"; then
    cat "$run_stderr" >&2
    fail "do run"
fi
expect_empty_file "$run_stdout" "do run stdout"
expect_empty_file "$run_stderr" "do run stderr"
pass "do run"

for lsp_case in "$LSP_DIR"/*.json; do
    [[ -e "$lsp_case" ]] || continue
    lsp_name="$(basename "$lsp_case" .json)"
    if ! "$NODE_BIN" "$TEST_DIR/run_lsp_case.mjs" "$DO_BIN" "$lsp_case" >"$TMP_DIR/lsp_${lsp_name}.stdout" 2>"$TMP_DIR/lsp_${lsp_name}.stderr"; then
        cat "$TMP_DIR/lsp_${lsp_name}.stderr" >&2
        fail "do lsp $lsp_name"
    fi
done
pass "do lsp"

echo "[INFO] release smoke passed"
