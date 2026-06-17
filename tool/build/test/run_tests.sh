#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_DIR="$ROOT_DIR/tool/build/test"
SRC_DIR="$ROOT_DIR/src"
WASI_REGISTRY="$ROOT_DIR/doc/wit/wasi_registry.json"
OK_DIR="$TEST_DIR/ok"
ERR_DIR="$TEST_DIR/err"
LIB_DIR="$TEST_DIR/lib"
COMPILE_OK_DIR="$TEST_DIR/compile_ok"
COMPILE_ERR_DIR="$TEST_DIR/compile_err"
COMPILED_OK_DIR="$TEST_DIR/compiled_ok"
COMPILED_ERR_DIR="$TEST_DIR/compiled_err"
COMPILED_TRAP_DIR="$TEST_DIR/compiled_trap"
FMT_DIR="$TEST_DIR/fmt"
PENDING_OK_DIR="$TEST_DIR/pending/ok"
PENDING_ERR_DIR="$TEST_DIR/pending/err"
TMP_DIR="$TEST_DIR/tmp"
RUN_PENDING="${RUN_PENDING:-0}"
SKIP_BUILD="${SKIP_BUILD:-0}"

ZIG_BIN="${ZIG_BIN:-$(command -v zig || true)}"
ZIG_BIN="${ZIG_BIN:-/home/_/_/zig/zig}"
DO_BIN="$ROOT_DIR/bin/do"
WASM_TOOLS="${WASM_TOOLS:-$(command -v wasm-tools || true)}"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"

pass_count=0
fail_count=0
skip_count=0

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

run_wasi_bind_manifest_tool_test() {
    local stdout_file="$TMP_DIR/wasi_bind_manifest_tool.stdout"
    local stderr_file="$TMP_DIR/wasi_bind_manifest_tool.stderr"

    if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
        echo "[FAIL] tool wasi_bind_manifest (node not found)"
        ((fail_count += 1))
        return
    fi

    if "$NODE_BIN" "$TEST_DIR/test_wasi_bind_manifest_tool.mjs" "$TEST_DIR/validate_wasi_bind_manifest.mjs" "$TMP_DIR" >"$stdout_file" 2>"$stderr_file"; then
        if grep -Fq "ok: wasi-bind manifest tool" "$stdout_file"; then
            echo "[PASS] tool wasi_bind_manifest"
            ((pass_count += 1))
            return
        fi

        echo "[FAIL] tool wasi_bind_manifest (missing success marker)"
        cat "$stdout_file"
        ((fail_count += 1))
        return
    fi

    echo "[FAIL] tool wasi_bind_manifest (unexpected non-zero exit)"
    cat "$stderr_file"
    ((fail_count += 1))
}

run_cli_output_order_case() {
    local case_file="$COMPILE_OK_DIR/01_start_entry_valid.do"
    local build_out="$TMP_DIR/cli_build_pre_output.wat"
    local test_out="$TMP_DIR/cli_test_pre_output.wat"
    local build_stdout="$TMP_DIR/cli_build_pre_output.stdout"
    local build_stderr="$TMP_DIR/cli_build_pre_output.stderr"
    local test_stdout="$TMP_DIR/cli_test_pre_output.stdout"
    local test_stderr="$TMP_DIR/cli_test_pre_output.stderr"

    rm -f "$build_out" "$test_out"

    if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" build -o "$build_out" "$case_file" >"$build_stdout" 2>"$build_stderr"; then
        echo "[FAIL] cli output_order build (unexpected non-zero exit)"
        cat "$build_stderr"
        ((fail_count += 1))
        return
    fi
    if [[ ! -s "$build_out" ]]; then
        echo "[FAIL] cli output_order build (missing requested output)"
        cat "$build_stdout"
        ((fail_count += 1))
        return
    fi

    if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" test --compiled -o "$test_out" "$COMPILED_OK_DIR/01_compiled_test_entry.do" >"$test_stdout" 2>"$test_stderr"; then
        echo "[FAIL] cli output_order test --compiled (unexpected non-zero exit)"
        cat "$test_stderr"
        ((fail_count += 1))
        return
    fi
    if [[ ! -s "$test_out" ]]; then
        echo "[FAIL] cli output_order test --compiled (missing requested output)"
        cat "$test_stdout"
        ((fail_count += 1))
        return
    fi

    echo "[PASS] cli output_order"
    ((pass_count += 1))
}

run_cli_strict_arg_case() {
    local case_file="$COMPILE_OK_DIR/01_start_entry_valid.do"
    local test_case_file="$OK_DIR/01_path_get_single.do"
    local stdout_file="$TMP_DIR/cli_strict_args.stdout"
    local stderr_file="$TMP_DIR/cli_strict_args.stderr"

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" build "$case_file" --bad >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] cli strict_args build unknown flag (expected failure)"
        ((fail_count += 1))
        return
    fi
    if ! grep -Fq "error[UnexpectedCliArg]" "$stderr_file"; then
        echo "[FAIL] cli strict_args build unknown flag (missing diagnostic)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" build "$case_file" "$case_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] cli strict_args build extra input (expected failure)"
        ((fail_count += 1))
        return
    fi
    if ! grep -Fq "error[UnexpectedCliArg]" "$stderr_file"; then
        echo "[FAIL] cli strict_args build extra input (missing diagnostic)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" run "$case_file" --bad >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] cli strict_args run unknown flag (expected failure)"
        ((fail_count += 1))
        return
    fi
    if ! grep -Fq "error[UnexpectedCliArg]" "$stderr_file"; then
        echo "[FAIL] cli strict_args run unknown flag (missing diagnostic)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" run "$case_file" "$case_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] cli strict_args run extra input (expected failure)"
        ((fail_count += 1))
        return
    fi
    if ! grep -Fq "error[UnexpectedCliArg]" "$stderr_file"; then
        echo "[FAIL] cli strict_args run extra input (missing diagnostic)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" test "$test_case_file" -o "$TMP_DIR/cli_strict_args.wat" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] cli strict_args test output without compiled (expected failure)"
        ((fail_count += 1))
        return
    fi
    if ! grep -Fq "error[OutputRequiresCompiledTest]" "$stderr_file"; then
        echo "[FAIL] cli strict_args test output without compiled (missing diagnostic)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    echo "[PASS] cli strict_args"
    ((pass_count += 1))
}

run_ok_case() {
    local case_file="$1"
    local name
    name="$(basename "$case_file" .do)"
    local must_pass_file="${case_file%.do}.must_pass"
    local compiled_must_pass_file="${case_file%.do}.compiled_must_pass"

    local stdout_file="$TMP_DIR/${name}.stdout"
    local stderr_file="$TMP_DIR/${name}.stderr"

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" test "$case_file" >"$stdout_file" 2>"$stderr_file"; then
        if grep -Fq 'test "' "$stdout_file" && grep -Fq "ok:" "$stdout_file"; then
            if grep -Fq " ... ok" "$stdout_file"; then
                echo "[PASS] ok  $name"
                ((pass_count += 1))
                return
            fi
            if grep -Fq " ... skipped" "$stdout_file"; then
                if [[ -f "$must_pass_file" ]]; then
                    echo "[FAIL] ok  $name (must pass, got skip)"
                    cat "$stdout_file"
                    ((fail_count += 1))
                    return
                fi
                if [[ -f "$compiled_must_pass_file" ]]; then
                    run_ok_compiled_must_pass_case "$case_file"
                    return
                fi
                echo "[SKIP] ok  $name"
                ((skip_count += 1))
                return
            fi
        fi

        echo "[FAIL] ok  $name (missing success or skip marker)"
        cat "$stdout_file"
        ((fail_count += 1))
        return
    fi

    echo "[FAIL] ok  $name (unexpected non-zero exit)"
    cat "$stderr_file"
    ((fail_count += 1))
}

run_ok_compiled_must_pass_case() {
    local case_file="$1"
    local name
    name="$(basename "$case_file" .do)"

    local stdout_file="$TMP_DIR/${name}.compiled.stdout"
    local stderr_file="$TMP_DIR/${name}.compiled.stderr"
    local wat_file="$TMP_DIR/${name}.compiled.wat"
    local wasm_file="$TMP_DIR/${name}.compiled.wasm"
    local wasm_stdout_file="$TMP_DIR/${name}.compiled.wasm.stdout"
    local wasm_stderr_file="$TMP_DIR/${name}.compiled.wasm.stderr"

    if [[ -z "$WASM_TOOLS" || ! -x "$WASM_TOOLS" ]]; then
        echo "[FAIL] ok  $name (compiled_must_pass requires wasm-tools)"
        ((fail_count += 1))
        return
    fi
    if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
        echo "[FAIL] ok  $name (compiled_must_pass requires node)"
        ((fail_count += 1))
        return
    fi

    if ! DO_LIB_ROOT="$SRC_DIR" "$DO_BIN" test "$case_file" --compiled -o "$wat_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] ok  $name (compiled_must_pass generation failed)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi
    if ! "$WASM_TOOLS" parse "$wat_file" -o "$wasm_file" >"$TMP_DIR/${name}.compiled.parse.stdout" 2>"$TMP_DIR/${name}.compiled.parse.stderr"; then
        echo "[FAIL] ok  $name (compiled_must_pass wat parse failed)"
        cat "$TMP_DIR/${name}.compiled.parse.stderr"
        ((fail_count += 1))
        return
    fi
    if ! "$NODE_BIN" "$TEST_DIR/run_compiled_test_case.mjs" "$wasm_file" "$wat_file" >"$wasm_stdout_file" 2>"$wasm_stderr_file"; then
        echo "[FAIL] ok  $name (compiled_must_pass execution failed)"
        cat "$wasm_stderr_file"
        ((fail_count += 1))
        return
    fi
    if ! grep -Fq 'test "' "$wasm_stdout_file" || ! grep -Fq " ... ok" "$wasm_stdout_file" || ! grep -Fq "ok:" "$wasm_stdout_file"; then
        echo "[FAIL] ok  $name (compiled_must_pass missing report marker)"
        cat "$wasm_stdout_file"
        ((fail_count += 1))
        return
    fi

    echo "[PASS] ok  $name (compiled)"
    ((pass_count += 1))
}

run_do_run_case() {
    local case_file="$1"
    local name
    name="$(basename "$case_file" .do)"

    local stdout_file="$TMP_DIR/run_${name}.stdout"
    local stderr_file="$TMP_DIR/run_${name}.stderr"
    local expect_file="${case_file%.do}.stdout.expect"

    if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" run "$case_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] do run $name (unexpected non-zero exit)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if [[ -s "$stderr_file" ]]; then
        echo "[FAIL] do run $name (unexpected stderr)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if [[ -f "$expect_file" ]]; then
        if ! diff -u "$expect_file" "$stdout_file"; then
            echo "[FAIL] do run $name (stdout mismatch)"
            ((fail_count += 1))
            return
        fi
    elif [[ -s "$stdout_file" ]]; then
        echo "[FAIL] do run $name (unexpected stdout)"
        cat "$stdout_file"
        ((fail_count += 1))
        return
    fi

    echo "[PASS] do run $name"
    ((pass_count += 1))
}

run_fmt_case() {
    local case_file="$1"
    local name
    name="$(basename "$case_file" .do)"

    local expect_file="${case_file%.do}.expect"
    local stdout_file="$TMP_DIR/fmt_${name}.stdout"
    local stderr_file="$TMP_DIR/fmt_${name}.stderr"
    local second_stdout_file="$TMP_DIR/fmt_${name}.second.stdout"
    local second_stderr_file="$TMP_DIR/fmt_${name}.second.stderr"
    local formatted_file="$TMP_DIR/fmt_${name}.formatted.do"

    if [[ ! -f "$expect_file" ]]; then
        echo "[FAIL] fmt $name (missing expect file)"
        ((fail_count += 1))
        return
    fi

    if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" fmt "$case_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] fmt $name (unexpected non-zero exit)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if [[ -s "$stderr_file" ]]; then
        echo "[FAIL] fmt $name (unexpected stderr)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if ! diff -u "$expect_file" "$stdout_file"; then
        echo "[FAIL] fmt $name (stdout mismatch)"
        ((fail_count += 1))
        return
    fi

    cp "$stdout_file" "$formatted_file"
    if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" fmt "$formatted_file" >"$second_stdout_file" 2>"$second_stderr_file"; then
        echo "[FAIL] fmt $name (idempotence command failed)"
        cat "$second_stderr_file"
        ((fail_count += 1))
        return
    fi

    if [[ -s "$second_stderr_file" ]]; then
        echo "[FAIL] fmt $name (idempotence stderr)"
        cat "$second_stderr_file"
        ((fail_count += 1))
        return
    fi

    if ! diff -u "$stdout_file" "$second_stdout_file"; then
        echo "[FAIL] fmt $name (idempotence mismatch)"
        ((fail_count += 1))
        return
    fi

    if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" fmt --check "$formatted_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] fmt $name (--check formatted source failed)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if [[ -s "$stdout_file" || -s "$stderr_file" ]]; then
        echo "[FAIL] fmt $name (--check formatted source emitted output)"
        cat "$stdout_file"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if cmp -s "$case_file" "$expect_file"; then
        echo "[PASS] fmt $name"
        ((pass_count += 1))
        return
    fi

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" fmt --check "$case_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] fmt $name (--check unformatted source passed)"
        ((fail_count += 1))
        return
    fi

    if ! grep -Fq "error[FormatMismatch]" "$stderr_file"; then
        echo "[FAIL] fmt $name (--check mismatch diagnostic missing)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if [[ -s "$stdout_file" ]]; then
        echo "[FAIL] fmt $name (--check mismatch stdout)"
        cat "$stdout_file"
        ((fail_count += 1))
        return
    fi

    echo "[PASS] fmt $name"
    ((pass_count += 1))
}

run_do_run_missing_wasm_tools_case() {
    local case_file="$TEST_DIR/run/01_start_scalar.do"
    local stdout_file="$TMP_DIR/run_missing_wasm_tools.stdout"
    local stderr_file="$TMP_DIR/run_missing_wasm_tools.stderr"
    local empty_path="$TMP_DIR/run_missing_wasm_tools_path"

    rm -rf "$empty_path"
    mkdir -p "$empty_path"

    if PATH="$empty_path" DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" run "$case_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] do run missing wasm-tools (expected failure)"
        ((fail_count += 1))
        return
    fi

    if ! grep -Fq "error[MissingExternalTool]: wasm-tools not found" "$stderr_file"; then
        echo "[FAIL] do run missing wasm-tools (missing diagnostic)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if [[ -s "$stdout_file" ]]; then
        echo "[FAIL] do run missing wasm-tools (unexpected stdout)"
        cat "$stdout_file"
        ((fail_count += 1))
        return
    fi

    echo "[PASS] do run missing wasm-tools"
    ((pass_count += 1))
}

run_do_run_missing_node_case() {
    local case_file="$TEST_DIR/run/01_start_scalar.do"
    local stdout_file="$TMP_DIR/run_missing_node.stdout"
    local stderr_file="$TMP_DIR/run_missing_node.stderr"
    local tool_path="$TMP_DIR/run_missing_node_path"

    if [[ -z "$WASM_TOOLS" || ! -x "$WASM_TOOLS" ]]; then
        echo "[FAIL] do run missing node (wasm-tools not found for setup)"
        ((fail_count += 1))
        return
    fi

    rm -rf "$tool_path"
    mkdir -p "$tool_path"
    ln -s "$WASM_TOOLS" "$tool_path/wasm-tools"

    if PATH="$tool_path" DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" run "$case_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] do run missing node (expected failure)"
        ((fail_count += 1))
        return
    fi

    if ! grep -Fq "error[MissingExternalTool]: node not found" "$stderr_file"; then
        echo "[FAIL] do run missing node (missing diagnostic)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi

    if [[ -s "$stdout_file" ]]; then
        echo "[FAIL] do run missing node (unexpected stdout)"
        cat "$stdout_file"
        ((fail_count += 1))
        return
    fi

    echo "[PASS] do run missing node"
    ((pass_count += 1))
}

run_ok_or_skip_output() {
    local stdout_file="$1"
    if grep -Fq 'test "' "$stdout_file" && grep -Fq "ok:" "$stdout_file"; then
        if grep -Fq " ... ok" "$stdout_file"; then
            return 0
        fi
        if grep -Fq " ... skipped" "$stdout_file"; then
            return 2
        fi
    fi
    return 1
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

run_std_src_case() {
    local case_file="$1"
    local name
    name="$(basename "$case_file" .do)"

    if [[ "$(basename "$case_file")" == "_.do" ]]; then
        echo "[PASS] std src $name (metadata table skipped)"
        ((pass_count += 1))
        return
    fi

    local stdout_file="$TMP_DIR/std_${name}.stdout"
    local stderr_file="$TMP_DIR/std_${name}.stderr"

    if DO_LIB_ROOT="$SRC_DIR" "$DO_BIN" test "$case_file" >"$stdout_file" 2>"$stderr_file"; then
        run_ok_or_skip_output "$stdout_file"
        local status=$?
        if [[ "$status" -eq 0 ]]; then
            echo "[PASS] ok  $name"
            ((pass_count += 1))
            return
        fi
        if [[ "$status" -eq 2 ]]; then
            echo "[SKIP] std src $name"
            ((skip_count += 1))
            return
        fi

        echo "[FAIL] std src $name (missing success or skip marker)"
        cat "$stdout_file"
        ((fail_count += 1))
        return
    fi

    if grep -Fq "NoTestDecl" "$stderr_file"; then
        echo "[SKIP] std src $name (NoTestDecl)"
        ((skip_count += 1))
        return
    fi

    echo "[FAIL] std src $name (unexpected non-zero exit)"
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
    local component_plan_expect_file="${case_file%.do}.component_plan.expect"
    local wit_dir_expect_file="${case_file%.do}.wit_dir.expect"
    local core_imports_expect_file="${case_file%.do}.core_imports.expect"
    local core_shims_expect_file="${case_file%.do}.core_shims.expect"
    local component_input_expect_file="${case_file%.do}.component_input.expect"
    local component_core_expect_file="${case_file%.do}.component_core.expect"

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" build "$case_file" -o "$wat_file" >"$stdout_file" 2>"$stderr_file"; then
        if grep -Fq "ok:" "$stdout_file" && [[ -s "$wat_file" ]]; then
            if [[ -f "$expect_file" ]]; then
                local missing=0
                while IFS= read -r line || [[ -n "$line" ]]; do
                    [[ -z "$line" ]] && continue
                    [[ "${line:0:1}" == "#" ]] && continue
                    if [[ "$line" == count=* ]]; then
                        local count_spec="${line#count=}"
                        local expected_count="${count_spec%% *}"
                        local pattern="${line#count=${expected_count} }"
                        local actual_count
                        actual_count="$(grep -F -c -- "$pattern" "$wat_file" || true)"
                        actual_count="${actual_count//[[:space:]]/}"
                        if [[ "$actual_count" == "$expected_count" ]]; then
                            continue
                        fi
                        echo "[FAIL] compile ok  $name (expected count=$expected_count for wat text: $pattern, got $actual_count)"
                        missing=1
                        continue
                    fi
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
            if grep -Fq ";; wasi-bind " "$wat_file"; then
                if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
                    echo "[FAIL] compile ok  $name (node not found for wasi-bind manifest validation)"
                    ((fail_count += 1))
                    return
                fi
                if ! "$NODE_BIN" "$TEST_DIR/validate_wasi_bind_manifest.mjs" --registry "$WASI_REGISTRY" "$wat_file" >"$TMP_DIR/compile_${name}.wasi_bind.stdout" 2>"$TMP_DIR/compile_${name}.wasi_bind.stderr"; then
                    echo "[FAIL] compile ok  $name (wasi-bind manifest validation failed)"
                    cat "$TMP_DIR/compile_${name}.wasi_bind.stderr"
                    ((fail_count += 1))
                    return
                fi
            fi
            if [[ -f "$component_plan_expect_file" ]]; then
                if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
                    echo "[FAIL] compile ok  $name (node not found for wasi component plan validation)"
                    ((fail_count += 1))
                    return
                fi
                local component_plan_file="$TMP_DIR/compile_${name}.component_plan.json"
                if ! "$NODE_BIN" "$TEST_DIR/validate_wasi_bind_manifest.mjs" --registry "$WASI_REGISTRY" --component-plan "$wat_file" >"$component_plan_file" 2>"$TMP_DIR/compile_${name}.component_plan.stderr"; then
                    echo "[FAIL] compile ok  $name (wasi component plan validation failed)"
                    cat "$TMP_DIR/compile_${name}.component_plan.stderr"
                    ((fail_count += 1))
                    return
                fi
                local component_missing=0
                while IFS= read -r line || [[ -n "$line" ]]; do
                    [[ -z "$line" ]] && continue
                    [[ "${line:0:1}" == "#" ]] && continue
                    if grep -Fq "$line" "$component_plan_file"; then
                        continue
                    fi
                    echo "[FAIL] compile ok  $name (missing expected component plan text: $line)"
                    component_missing=1
                done < "$component_plan_expect_file"
                if [[ "$component_missing" -ne 0 ]]; then
                    echo "[INFO] component plan output for $name:"
                    cat "$component_plan_file"
                    ((fail_count += 1))
                    return
                fi
                if [[ ! -f "$wit_dir_expect_file" ]]; then
                    local wit_file="$TMP_DIR/compile_${name}.wit"
                    if ! "$NODE_BIN" "$TEST_DIR/validate_wasi_bind_manifest.mjs" --registry "$WASI_REGISTRY" --wit "$wat_file" >"$wit_file" 2>"$TMP_DIR/compile_${name}.wit.stderr"; then
                        echo "[FAIL] compile ok  $name (wasi WIT generation failed)"
                        cat "$TMP_DIR/compile_${name}.wit.stderr"
                        ((fail_count += 1))
                        return
                    fi
                    if [[ -n "$WASM_TOOLS" && -x "$WASM_TOOLS" ]]; then
                        if ! "$WASM_TOOLS" component wit "$wit_file" >"$TMP_DIR/compile_${name}.wit.stdout" 2>"$TMP_DIR/compile_${name}.wit.parse.stderr"; then
                            echo "[FAIL] compile ok  $name (generated WIT failed wasm-tools validation)"
                            cat "$TMP_DIR/compile_${name}.wit.parse.stderr"
                            ((fail_count += 1))
                            return
                        fi
                    fi
                fi
            fi
            if [[ -f "$wit_dir_expect_file" ]]; then
                if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
                    echo "[FAIL] compile ok  $name (node not found for wasi WIT directory validation)"
                    ((fail_count += 1))
                    return
                fi
                local wit_dir="$TMP_DIR/compile_${name}.wit_dir"
                if ! "$NODE_BIN" "$TEST_DIR/validate_wasi_bind_manifest.mjs" --registry "$WASI_REGISTRY" --wit-dir "$wit_dir" "$wat_file" >"$TMP_DIR/compile_${name}.wit_dir.stdout" 2>"$TMP_DIR/compile_${name}.wit_dir.stderr"; then
                    echo "[FAIL] compile ok  $name (wasi WIT directory generation failed)"
                    cat "$TMP_DIR/compile_${name}.wit_dir.stderr"
                    ((fail_count += 1))
                    return
                fi
                local wit_dir_output="$TMP_DIR/compile_${name}.wit_dir.parsed"
                if [[ -n "$WASM_TOOLS" && -x "$WASM_TOOLS" ]]; then
                    if ! "$WASM_TOOLS" component wit "$wit_dir" >"$wit_dir_output" 2>"$TMP_DIR/compile_${name}.wit_dir.parse.stderr"; then
                        echo "[FAIL] compile ok  $name (generated WIT directory failed wasm-tools validation)"
                        cat "$TMP_DIR/compile_${name}.wit_dir.parse.stderr"
                        ((fail_count += 1))
                        return
                    fi
                else
                    {
                        find "$wit_dir" -type f -name '*.wit' | sort | while IFS= read -r file; do
                            cat "$file"
                        done
                    } >"$wit_dir_output"
                fi
                local wit_dir_missing=0
                while IFS= read -r line || [[ -n "$line" ]]; do
                    [[ -z "$line" ]] && continue
                    [[ "${line:0:1}" == "#" ]] && continue
                    if grep -Fq "$line" "$wit_dir_output"; then
                        continue
                    fi
                    echo "[FAIL] compile ok  $name (missing expected WIT directory text: $line)"
                    wit_dir_missing=1
                done < "$wit_dir_expect_file"
                if [[ "$wit_dir_missing" -ne 0 ]]; then
                    echo "[INFO] WIT directory output for $name:"
                    cat "$wit_dir_output"
                    ((fail_count += 1))
                    return
                fi
            fi
            if [[ -f "$core_imports_expect_file" ]]; then
                if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
                    echo "[FAIL] compile ok  $name (node not found for wasi core import validation)"
                    ((fail_count += 1))
                    return
                fi
                local core_imports_file="$TMP_DIR/compile_${name}.core_imports.wat"
                if ! "$NODE_BIN" "$TEST_DIR/validate_wasi_bind_manifest.mjs" --registry "$WASI_REGISTRY" --core-imports "$wat_file" >"$core_imports_file" 2>"$TMP_DIR/compile_${name}.core_imports.stderr"; then
                    echo "[FAIL] compile ok  $name (wasi core import generation failed)"
                    cat "$TMP_DIR/compile_${name}.core_imports.stderr"
                    ((fail_count += 1))
                    return
                fi
                local core_imports_missing=0
                while IFS= read -r line || [[ -n "$line" ]]; do
                    [[ -z "$line" ]] && continue
                    [[ "${line:0:1}" == "#" ]] && continue
                    if grep -Fq "$line" "$core_imports_file"; then
                        continue
                    fi
                    echo "[FAIL] compile ok  $name (missing expected wasi core import text: $line)"
                    core_imports_missing=1
                done < "$core_imports_expect_file"
                if [[ "$core_imports_missing" -ne 0 ]]; then
                    echo "[INFO] wasi core imports output for $name:"
                    cat "$core_imports_file"
                    ((fail_count += 1))
                    return
                fi
            fi
            if [[ -f "$core_shims_expect_file" ]]; then
                if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
                    echo "[FAIL] compile ok  $name (node not found for wasi core shim validation)"
                    ((fail_count += 1))
                    return
                fi
                local core_shims_file="$TMP_DIR/compile_${name}.core_shims.wat"
                if ! "$NODE_BIN" "$TEST_DIR/validate_wasi_bind_manifest.mjs" --registry "$WASI_REGISTRY" --core-shims "$wat_file" >"$core_shims_file" 2>"$TMP_DIR/compile_${name}.core_shims.stderr"; then
                    echo "[FAIL] compile ok  $name (wasi core shim generation failed)"
                    cat "$TMP_DIR/compile_${name}.core_shims.stderr"
                    ((fail_count += 1))
                    return
                fi
                local core_shims_missing=0
                while IFS= read -r line || [[ -n "$line" ]]; do
                    [[ -z "$line" ]] && continue
                    [[ "${line:0:1}" == "#" ]] && continue
                    if grep -Fq "$line" "$core_shims_file"; then
                        continue
                    fi
                    echo "[FAIL] compile ok  $name (missing expected wasi core shim text: $line)"
                    core_shims_missing=1
                done < "$core_shims_expect_file"
                if [[ "$core_shims_missing" -ne 0 ]]; then
                    echo "[INFO] wasi core shims output for $name:"
                    cat "$core_shims_file"
                    ((fail_count += 1))
                    return
                fi
                if [[ -n "$WASM_TOOLS" && -x "$WASM_TOOLS" ]]; then
                    local core_shims_module_file="$TMP_DIR/compile_${name}.core_shims.module.wat"
                    {
                        printf '(module\n'
                        cat "$core_shims_file"
                        printf ')\n'
                    } >"$core_shims_module_file"
                    if ! "$WASM_TOOLS" parse "$core_shims_module_file" -o "$TMP_DIR/compile_${name}.core_shims.module.wasm" >"$TMP_DIR/compile_${name}.core_shims.parse.stdout" 2>"$TMP_DIR/compile_${name}.core_shims.parse.stderr"; then
                        echo "[FAIL] compile ok  $name (generated wasi core shims failed wasm-tools parse)"
                        cat "$TMP_DIR/compile_${name}.core_shims.parse.stderr"
                        ((fail_count += 1))
                        return
                    fi
                fi
            fi
            if [[ -f "$component_input_expect_file" ]]; then
                if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
                    echo "[FAIL] compile ok  $name (node not found for wasi component input validation)"
                    ((fail_count += 1))
                    return
                fi
                local component_input_dir="$TMP_DIR/compile_${name}.component_input"
                if ! "$NODE_BIN" "$TEST_DIR/validate_wasi_bind_manifest.mjs" --registry "$WASI_REGISTRY" --component-input-dir "$component_input_dir" "$wat_file" >"$TMP_DIR/compile_${name}.component_input.stdout" 2>"$TMP_DIR/compile_${name}.component_input.stderr"; then
                    echo "[FAIL] compile ok  $name (wasi component input directory generation failed)"
                    cat "$TMP_DIR/compile_${name}.component_input.stderr"
                    ((fail_count += 1))
                    return
                fi
                local component_input_output="$TMP_DIR/compile_${name}.component_input.txt"
                {
                    cat "$component_input_dir/metadata.json"
                    cat "$component_input_dir/component_plan.json"
                    cat "$component_input_dir/core_imports.wat"
                    cat "$component_input_dir/core_shims.wat"
                } >"$component_input_output"
                if [[ -n "$WASM_TOOLS" && -x "$WASM_TOOLS" ]]; then
                    if ! "$WASM_TOOLS" component wit "$component_input_dir/wit" >>"$component_input_output" 2>"$TMP_DIR/compile_${name}.component_input.wit.stderr"; then
                        echo "[FAIL] compile ok  $name (component input WIT directory failed wasm-tools validation)"
                        cat "$TMP_DIR/compile_${name}.component_input.wit.stderr"
                        ((fail_count += 1))
                        return
                    fi
                    local component_input_shims_module_file="$TMP_DIR/compile_${name}.component_input.shims.module.wat"
                    {
                        printf '(module\n'
                        cat "$component_input_dir/core_shims.wat"
                        printf ')\n'
                    } >"$component_input_shims_module_file"
                    if ! "$WASM_TOOLS" parse "$component_input_shims_module_file" -o "$TMP_DIR/compile_${name}.component_input.shims.module.wasm" >"$TMP_DIR/compile_${name}.component_input.shims.parse.stdout" 2>"$TMP_DIR/compile_${name}.component_input.shims.parse.stderr"; then
                        echo "[FAIL] compile ok  $name (component input core shims failed wasm-tools parse)"
                        cat "$TMP_DIR/compile_${name}.component_input.shims.parse.stderr"
                        ((fail_count += 1))
                        return
                    fi
                    local component_input_embedded_file="$TMP_DIR/compile_${name}.component_input.embedded.wasm"
                    local component_input_component_file="$TMP_DIR/compile_${name}.component_input.component.wasm"
                    if ! "$WASM_TOOLS" component embed "$component_input_dir/wit" "$component_input_dir/core_component.wat" -o "$component_input_embedded_file" >"$TMP_DIR/compile_${name}.component_input.embed.stdout" 2>"$TMP_DIR/compile_${name}.component_input.embed.stderr"; then
                        echo "[FAIL] compile ok  $name (component input embed failed)"
                        cat "$TMP_DIR/compile_${name}.component_input.embed.stderr"
                        ((fail_count += 1))
                        return
                    fi
                    if ! "$WASM_TOOLS" component new "$component_input_embedded_file" -o "$component_input_component_file" >"$TMP_DIR/compile_${name}.component_input.new.stdout" 2>"$TMP_DIR/compile_${name}.component_input.new.stderr"; then
                        echo "[FAIL] compile ok  $name (component input component generation failed)"
                        cat "$TMP_DIR/compile_${name}.component_input.new.stderr"
                        ((fail_count += 1))
                        return
                    fi
                    if ! "$WASM_TOOLS" validate "$component_input_component_file" >"$TMP_DIR/compile_${name}.component_input.validate.stdout" 2>"$TMP_DIR/compile_${name}.component_input.validate.stderr"; then
                        echo "[FAIL] compile ok  $name (component input component validation failed)"
                        cat "$TMP_DIR/compile_${name}.component_input.validate.stderr"
                        ((fail_count += 1))
                        return
                    fi
                else
                    find "$component_input_dir/wit" -type f -name '*.wit' | sort | while IFS= read -r file; do
                        cat "$file"
                    done >>"$component_input_output"
                fi
                local component_input_missing=0
                while IFS= read -r line || [[ -n "$line" ]]; do
                    [[ -z "$line" ]] && continue
                    [[ "${line:0:1}" == "#" ]] && continue
                    if grep -Fq "$line" "$component_input_output"; then
                        continue
                    fi
                    echo "[FAIL] compile ok  $name (missing expected component input text: $line)"
                    component_input_missing=1
                done < "$component_input_expect_file"
                if [[ "$component_input_missing" -ne 0 ]]; then
                    echo "[INFO] component input output for $name:"
                    cat "$component_input_output"
                    ((fail_count += 1))
                    return
                fi
            fi
            if [[ -f "$component_core_expect_file" ]]; then
                local component_core_file="$TMP_DIR/compile_${name}.component_core.wat"
                if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" build "$case_file" --component-core -o "$component_core_file" >"$TMP_DIR/compile_${name}.component_core.stdout" 2>"$TMP_DIR/compile_${name}.component_core.stderr"; then
                    echo "[FAIL] compile ok  $name (component-core build failed)"
                    cat "$TMP_DIR/compile_${name}.component_core.stderr"
                    ((fail_count += 1))
                    return
                fi
                local component_core_missing=0
                while IFS= read -r line || [[ -n "$line" ]]; do
                    [[ -z "$line" ]] && continue
                    [[ "${line:0:1}" == "#" ]] && continue
                    if grep -Fq "$line" "$component_core_file"; then
                        continue
                    fi
                    echo "[FAIL] compile ok  $name (missing expected component-core text: $line)"
                    component_core_missing=1
                done < "$component_core_expect_file"
                if [[ "$component_core_missing" -ne 0 ]]; then
                    echo "[INFO] component-core output for $name:"
                    cat "$component_core_file"
                    ((fail_count += 1))
                    return
                fi
                if grep -Fq '(memory (export "memory")' "$component_core_file"; then
                    echo "[FAIL] compile ok  $name (component-core still exports plain memory)"
                    ((fail_count += 1))
                    return
                fi
                if [[ -n "$WASM_TOOLS" && -x "$WASM_TOOLS" && -f "$component_input_expect_file" ]]; then
                    local component_core_input_dir="$TMP_DIR/compile_${name}.component_core_input"
                    if ! "$NODE_BIN" "$TEST_DIR/validate_wasi_bind_manifest.mjs" --registry "$WASI_REGISTRY" --wit-dir "$component_core_input_dir/wit" "$component_core_file" >"$TMP_DIR/compile_${name}.component_core.wit_dir.stdout" 2>"$TMP_DIR/compile_${name}.component_core.wit_dir.stderr"; then
                        echo "[FAIL] compile ok  $name (component-core WIT directory generation failed)"
                        cat "$TMP_DIR/compile_${name}.component_core.wit_dir.stderr"
                        ((fail_count += 1))
                        return
                    fi
                    local component_core_embedded_file="$TMP_DIR/compile_${name}.component_core.embedded.wasm"
                    local component_core_component_file="$TMP_DIR/compile_${name}.component_core.component.wasm"
                    if ! "$WASM_TOOLS" component embed "$component_core_input_dir/wit" "$component_core_file" -o "$component_core_embedded_file" >"$TMP_DIR/compile_${name}.component_core.embed.stdout" 2>"$TMP_DIR/compile_${name}.component_core.embed.stderr"; then
                        echo "[FAIL] compile ok  $name (component-core embed failed)"
                        cat "$TMP_DIR/compile_${name}.component_core.embed.stderr"
                        ((fail_count += 1))
                        return
                    fi
                    if ! "$WASM_TOOLS" component new "$component_core_embedded_file" -o "$component_core_component_file" >"$TMP_DIR/compile_${name}.component_core.new.stdout" 2>"$TMP_DIR/compile_${name}.component_core.new.stderr"; then
                        echo "[FAIL] compile ok  $name (component-core component generation failed)"
                        cat "$TMP_DIR/compile_${name}.component_core.new.stderr"
                        ((fail_count += 1))
                        return
                    fi
                    if ! "$WASM_TOOLS" validate "$component_core_component_file" >"$TMP_DIR/compile_${name}.component_core.validate.stdout" 2>"$TMP_DIR/compile_${name}.component_core.validate.stderr"; then
                        echo "[FAIL] compile ok  $name (component-core component validation failed)"
                        cat "$TMP_DIR/compile_${name}.component_core.validate.stderr"
                        ((fail_count += 1))
                        return
                    fi
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

run_compiled_ok_case() {
    local case_file="$1"
    local name
    name="$(basename "$case_file" .do)"

    local stdout_file="$TMP_DIR/compiled_${name}.stdout"
    local stderr_file="$TMP_DIR/compiled_${name}.stderr"
    local wat_file="$TMP_DIR/compiled_${name}.wat"
    local wasm_file="$TMP_DIR/compiled_${name}.wasm"
    local wasm_stdout_file="$TMP_DIR/compiled_${name}.wasm.stdout"
    local wasm_stderr_file="$TMP_DIR/compiled_${name}.wasm.stderr"
    local expect_file="${case_file%.do}.expect"

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" test "$case_file" --compiled -o "$wat_file" >"$stdout_file" 2>"$stderr_file"; then
        if grep -Fq "ok:" "$stdout_file" && [[ -s "$wat_file" ]]; then
            if [[ -f "$expect_file" ]]; then
                local missing=0
                while IFS= read -r line || [[ -n "$line" ]]; do
                    [[ -z "$line" ]] && continue
                    [[ "${line:0:1}" == "#" ]] && continue
                    if [[ "$line" == count=* ]]; then
                        local count_spec="${line#count=}"
                        local expected_count="${count_spec%% *}"
                        local pattern="${line#count=${expected_count} }"
                        local actual_count
                        actual_count="$(grep -F -c -- "$pattern" "$wat_file" || true)"
                        actual_count="${actual_count//[[:space:]]/}"
                        if [[ "$actual_count" == "$expected_count" ]]; then
                            continue
                        fi
                        echo "[FAIL] compiled ok  $name (expected count=$expected_count for wat text: $pattern, got $actual_count)"
                        missing=1
                        continue
                    fi
                    if grep -Fq "$line" "$wat_file"; then
                        continue
                    fi
                    echo "[FAIL] compiled ok  $name (missing expected wat text: $line)"
                    missing=1
                done < "$expect_file"
                if [[ "$missing" -ne 0 ]]; then
                    echo "[INFO] wat output for $name:"
                    cat "$wat_file"
                    ((fail_count += 1))
                    return
                fi
            fi
            if [[ "${RUN_WASM:-0}" == "1" ]]; then
                if [[ -z "$WASM_TOOLS" || ! -x "$WASM_TOOLS" ]]; then
                    echo "[FAIL] compiled ok  $name (wasm-tools not found)"
                    ((fail_count += 1))
                    return
                fi
                if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
                    echo "[FAIL] compiled ok  $name (node not found)"
                    ((fail_count += 1))
                    return
                fi
                if ! "$WASM_TOOLS" parse "$wat_file" -o "$wasm_file" >"$TMP_DIR/compiled_${name}.parse.stdout" 2>"$TMP_DIR/compiled_${name}.parse.stderr"; then
                    echo "[FAIL] compiled ok  $name (wat parse failed)"
                    cat "$TMP_DIR/compiled_${name}.parse.stderr"
                    ((fail_count += 1))
                    return
                fi
                if ! "$NODE_BIN" "$TEST_DIR/run_compiled_test_case.mjs" "$wasm_file" "$wat_file" >"$wasm_stdout_file" 2>"$wasm_stderr_file"; then
                    echo "[FAIL] compiled ok  $name (execution failed)"
                    cat "$wasm_stderr_file"
                    ((fail_count += 1))
                    return
                fi
                if ! grep -Fq 'test "' "$wasm_stdout_file" || ! grep -Fq " ... ok" "$wasm_stdout_file" || ! grep -Fq "ok:" "$wasm_stdout_file"; then
                    echo "[FAIL] compiled ok  $name (missing compiled test report marker)"
                    cat "$wasm_stdout_file"
                    ((fail_count += 1))
                    return
                fi
            fi
            echo "[PASS] compiled ok  $name"
            ((pass_count += 1))
            return
        fi

        echo "[FAIL] compiled ok  $name (missing success marker or wat output)"
        cat "$stdout_file"
        ((fail_count += 1))
        return
    fi

    echo "[FAIL] compiled ok  $name (unexpected non-zero exit)"
    cat "$stderr_file"
    ((fail_count += 1))
}

run_compiled_err_case() {
    local case_file="$1"
    local name
    name="$(basename "$case_file" .do)"

    local stdout_file="$TMP_DIR/compiled_err_${name}.stdout"
    local stderr_file="$TMP_DIR/compiled_err_${name}.stderr"
    local wat_file="$TMP_DIR/compiled_err_${name}.wat"
    local expect_file="${case_file%.do}.expect"

    if [[ ! -f "$expect_file" ]]; then
        echo "[FAIL] compiled err $name (missing expect file: $expect_file)"
        ((fail_count += 1))
        return
    fi

    if DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" test "$case_file" --compiled -o "$wat_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] compiled err $name (expected failure, got success)"
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
        echo "[FAIL] compiled err $name (missing expected text: $line)"
        missing=1
    done < "$expect_file"

    if [[ "$missing" -eq 0 ]]; then
        echo "[PASS] compiled err $name"
        ((pass_count += 1))
        return
    fi

    echo "[INFO] stderr output for $name:"
    cat "$stderr_file"
    ((fail_count += 1))
}

run_compiled_trap_case() {
    local case_file="$1"
    local name
    name="$(basename "$case_file" .do)"

    local stdout_file="$TMP_DIR/compiled_trap_${name}.stdout"
    local stderr_file="$TMP_DIR/compiled_trap_${name}.stderr"
    local wat_file="$TMP_DIR/compiled_trap_${name}.wat"
    local wasm_file="$TMP_DIR/compiled_trap_${name}.wasm"
    local wasm_stdout_file="$TMP_DIR/compiled_trap_${name}.wasm.stdout"
    local wasm_stderr_file="$TMP_DIR/compiled_trap_${name}.wasm.stderr"

    if [[ -z "$WASM_TOOLS" || ! -x "$WASM_TOOLS" ]]; then
        echo "[FAIL] compiled trap $name (wasm-tools not found)"
        ((fail_count += 1))
        return
    fi
    if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
        echo "[FAIL] compiled trap $name (node not found)"
        ((fail_count += 1))
        return
    fi

    if ! DO_LIB_ROOT="$LIB_DIR" "$DO_BIN" test "$case_file" --compiled -o "$wat_file" >"$stdout_file" 2>"$stderr_file"; then
        echo "[FAIL] compiled trap $name (compiled test generation failed)"
        cat "$stderr_file"
        ((fail_count += 1))
        return
    fi
    if ! "$WASM_TOOLS" parse "$wat_file" -o "$wasm_file" >"$TMP_DIR/compiled_trap_${name}.parse.stdout" 2>"$TMP_DIR/compiled_trap_${name}.parse.stderr"; then
        echo "[FAIL] compiled trap $name (wat parse failed)"
        cat "$TMP_DIR/compiled_trap_${name}.parse.stderr"
        ((fail_count += 1))
        return
    fi
    if "$NODE_BIN" "$TEST_DIR/run_compiled_test_case.mjs" "$wasm_file" "$wat_file" >"$wasm_stdout_file" 2>"$wasm_stderr_file"; then
        echo "[FAIL] compiled trap $name (expected trap, got success)"
        cat "$wasm_stdout_file"
        ((fail_count += 1))
        return
    fi

    echo "[PASS] compiled trap $name"
    ((pass_count += 1))
}

echo "[INFO] run tool cases"
run_wasi_bind_manifest_tool_test
run_cli_output_order_case
run_cli_strict_arg_case

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

echo "[INFO] run std src cases"
for case_file in "$SRC_DIR"/*.do; do
    [[ -e "$case_file" ]] || continue
    run_std_src_case "$case_file"
done

echo "[INFO] run compile ok cases"
for case_file in "$COMPILE_OK_DIR"/*.do; do
    [[ -e "$case_file" ]] || continue
    [[ "$(basename "$case_file")" == fixture.*.do ]] && continue
    run_compile_ok_case "$case_file"
done

echo "[INFO] run compile err cases"
for case_file in "$COMPILE_ERR_DIR"/*.do; do
    [[ -e "$case_file" ]] || continue
    [[ "$(basename "$case_file")" == fixture.*.do ]] && continue
    run_compile_err_case "$case_file"
done

echo "[INFO] run compiled ok cases"
for case_file in "$COMPILED_OK_DIR"/*.do; do
    [[ -e "$case_file" ]] || continue
    run_compiled_ok_case "$case_file"
done

echo "[INFO] run compiled err cases"
for case_file in "$COMPILED_ERR_DIR"/*.do; do
    [[ -e "$case_file" ]] || continue
    run_compiled_err_case "$case_file"
done

if [[ "${RUN_WASM:-0}" == "1" ]]; then
    echo "[INFO] run compiled trap cases"
    for case_file in "$COMPILED_TRAP_DIR"/*.do; do
        [[ -e "$case_file" ]] || continue
        run_compiled_trap_case "$case_file"
    done
fi

echo "[INFO] run do run cases"
run_do_run_missing_wasm_tools_case
run_do_run_missing_node_case

for case_file in "$TEST_DIR/run"/*.do; do
    [[ -e "$case_file" ]] || continue
    run_do_run_case "$case_file"
done

echo "[INFO] run fmt cases"
for case_file in "$FMT_DIR"/*.do; do
    [[ -e "$case_file" ]] || continue
    run_fmt_case "$case_file"
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

if [[ "${RUN_WASM:-0}" == "1" ]]; then
    echo "[INFO] run wasm smoke cases"
    if ! SKIP_BUILD=1 "$TEST_DIR/run_wasm_smoke.sh"; then
        ((fail_count += 1))
    fi
fi

echo "[INFO] summary: pass=$pass_count fail=$fail_count skip=$skip_count"
if [[ "$fail_count" -ne 0 ]]; then
    exit 1
fi
