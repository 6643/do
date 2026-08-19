#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DO_BIN="${DO_BIN:-$ROOT_DIR/bin/do}"
WASM_TOOLS_BIN="${WASM_TOOLS_BIN:-$(command -v wasm-tools || true)}"
WASMTIME_BIN="${WASMTIME_BIN:-$(command -v wasmtime || true)}"
ZIG_BIN="${ZIG_BIN:-zig}"
CARGO_BIN="${CARGO_BIN:-cargo}"
MODE="${1:-baseline}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/do-gc-g5c-residual.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT

case "$MODE" in
    baseline|cutover) ;;
    *)
        printf '[FAIL] usage: %s [baseline|cutover]\n' "$0" >&2
        exit 1
        ;;
esac

if [[ ! -x "$DO_BIN" ]]; then
    printf '[FAIL] missing do compiler executable: %s\n' "$DO_BIN" >&2
    exit 1
fi
if [[ -z "$WASM_TOOLS_BIN" || ! -x "$WASM_TOOLS_BIN" ]]; then
    printf '[FAIL] missing wasm-tools executable: %s\n' "${WASM_TOOLS_BIN:-<unset>}" >&2
    exit 1
fi
if [[ -z "$WASMTIME_BIN" || ! -x "$WASMTIME_BIN" ]]; then
    printf '[FAIL] missing Wasmtime executable: %s\n' "${WASMTIME_BIN:-<unset>}" >&2
    exit 1
fi

wasm_tools_version="$($WASM_TOOLS_BIN --version 2>&1)"
expected_wasm_tools_version='wasm-tools 1.255.0 (76e20611d 2026-07-30)'
if [[ "$wasm_tools_version" != "$expected_wasm_tools_version" ]]; then
    printf '[FAIL] wasm-tools identity mismatch: expected %s, got: %s\n' "$expected_wasm_tools_version" "$wasm_tools_version" >&2
    exit 1
fi
printf '[PASS] pinned wasm-tools: %s\n' "$wasm_tools_version"

run_descriptor_manifest_gate() {
    local gate_output="$TMP_DIR/gc-wasi-random-manifest.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_wasi_random_list_lift.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] descriptor manifest random Component gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] descriptor manifest random Component gate includes negative hash drift\n'
}

run_descriptor_manifest_gate

build_fixture() {
    local fixture="$1" output="$2"
    shift 2
    local -a args=(build "$fixture")
    args+=("$@")
    args+=(-o "$output")
    DO_LIB_ROOT="$ROOT_DIR/lib" "$DO_BIN" "${args[@]}" \
        >"$output.stdout" 2>"$output.stderr"
}

arc_residual_symbols=(
    '__arc_'
    'emit_arc_runtime_prelude'
    'runtime_arc_wat'
    'runtime_prelude_wat'
    'codegen_ownership'
)

assert_active_arc_residuals() {
    local symbol matches
    for symbol in "${arc_residual_symbols[@]}"; do
        matches="$(rg -l --glob '*.zig' "$symbol" "$ROOT_DIR/src/build" || true)"
        if [[ -z "$matches" ]]; then
            printf '[FAIL] expected pre-cutover ARC residual is absent: %s\n' "$symbol" >&2
            return 1
        fi
        printf '[PASS] active pre-cutover ARC residual: %s (%s files)\n' "$symbol" "$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l)"
    done
}

assert_no_active_arc_residuals() {
    local symbol matches
    for symbol in "${arc_residual_symbols[@]}"; do
        matches="$(rg -l --glob '*.zig' "$symbol" "$ROOT_DIR/src/build" || true)"
        if [[ -n "$matches" ]]; then
            printf '[FAIL] active ARC residual remains after cutover: %s\n%s\n' "$symbol" "$matches" >&2
            return 1
        fi
        printf '[PASS] no active ARC residual: %s\n' "$symbol"
    done
}

assert_gc_text_output_shape() {
    local wat_file="$1"
    rg -q '^  \(type \$do_text ' "$wat_file" || {
        printf '[FAIL] GC output lacks typed text object: %s\n' "$wat_file" >&2
        return 1
    }
    rg -q '\(ref null \$do_text\)' "$wat_file" || {
        printf '[FAIL] GC output lacks typed text reference: %s\n' "$wat_file" >&2
        return 1
    }
    rg -q ';; gc-root ' "$wat_file" || {
        printf '[FAIL] GC output lacks root marker: %s\n' "$wat_file" >&2
        return 1
    }
}

assert_gc_managed_output_shape() {
    local wat_file="$1"
    rg -q '^  \(type \$do_[a-zA-Z0-9_]+ ' "$wat_file" || {
        printf '[FAIL] GC output lacks a typed managed object: %s\n' "$wat_file" >&2
        return 1
    }
    rg -q '\(ref null \$do_[a-zA-Z0-9_]+' "$wat_file" || {
        printf '[FAIL] GC output lacks a typed managed reference: %s\n' "$wat_file" >&2
        return 1
    }
    rg -q 'struct\.new|array\.new' "$wat_file" || {
        printf '[FAIL] GC output lacks typed allocation/update instruction: %s\n' "$wat_file" >&2
        return 1
    }
}

run_default_gc_gate() {
    local gate_output="$TMP_DIR/default-build-gate.output"
    if ! DO_BIN="$DO_BIN" \
        WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        bash "$ROOT_DIR/src/build/test/check_gc_default_build_gate.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] admitted generated-output GC gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] admitted generated-output residual scan covered all fixtures\n'
}

run_gc_core_oracle() {
    local wat_file="$1"
    "$WASM_TOOLS_BIN" parse "$wat_file" -o "$TMP_DIR/gc-core.wasm" >/dev/null
    "$WASMTIME_BIN" compile -W gc=y -o "$TMP_DIR/gc-core.compiled" "$wat_file"
    local result
    result="$($WASMTIME_BIN -W gc=y --invoke probe "$wat_file")"
    if [[ "$result" != 27815 ]]; then
        printf '[FAIL] --gc-core Wasmtime oracle returned %s, expected 27815\n' "$result" >&2
        return 1
    fi
    printf '[PASS] --gc-core Wasmtime oracle returned %s\n' "$result"
}

check_inventory() {
    local expected_status="$1" inventory_output inventory_status
    inventory_output="$TMP_DIR/inventory.output"
    inventory_status=0
    if bash "$ROOT_DIR/src/build/test/check_gc_migration_inventory.sh" >"$inventory_output" 2>&1; then
        inventory_status=0
    else
        inventory_status=$?
    fi
    cat "$inventory_output"
    if [[ "$inventory_status" -ne "$expected_status" ]]; then
        printf '[FAIL] migration inventory status=%d; expected %d\n' "$inventory_status" "$expected_status" >&2
        return 1
    fi
    printf '[PASS] migration inventory status=%d\n' "$inventory_status"
}

admitted_fixture="$ROOT_DIR/examples/gc-p3-runtime/text-identity.do"
admitted_wat="$TMP_DIR/admitted.wat"
run_default_gc_gate
if ! build_fixture "$admitted_fixture" "$admitted_wat"; then
    printf '[FAIL] admitted GC fixture failed to build: %s\n' "$admitted_fixture" >&2
    cat "$admitted_wat.stderr" >&2
    exit 1
fi
assert_gc_text_output_shape "$admitted_wat"
if rg -q '__arc_' "$admitted_wat"; then
    printf '[FAIL] admitted output contains ARC marker: %s\n' "$admitted_wat" >&2
    exit 1
fi
"$WASM_TOOLS_BIN" parse "$admitted_wat" -o "$TMP_DIR/admitted.wasm" >/dev/null
printf '[PASS] admitted default build is GC-only and parses: %s\n' "$(basename "$admitted_fixture")"

migrated_fixture="$ROOT_DIR/src/build/test/compile_ok/63_arc_if_else_return_releases_managed_locals.do"
migrated_wat="$TMP_DIR/migrated-if-else.wat"
if ! build_fixture "$migrated_fixture" "$migrated_wat"; then
    printf '[FAIL] migrated if-else fixture failed to build: %s\n' "$migrated_fixture" >&2
    cat "$migrated_wat.stderr" >&2
    exit 1
fi
if rg -q '__arc_' "$migrated_wat"; then
    printf '[FAIL] migrated if-else fixture still contains ARC marker: %s\n' "$migrated_fixture" >&2
    exit 1
fi
if ! rg -q ';; gc-sync ' "$migrated_wat"; then
    printf '[FAIL] migrated if-else fixture lacks GC marker: %s\n' "$migrated_fixture" >&2
    exit 1
fi
"$WASM_TOOLS_BIN" parse "$migrated_wat" -o "$TMP_DIR/migrated-if-else.wasm" >/dev/null
printf '[PASS] migrated default build is GC-only and parses: %s\n' "$(basename "$migrated_fixture")"

host_wit_fixture="$ROOT_DIR/src/build/test/compile_ok/274_wasi_preopens_list_tuple_lower.do"
host_wit_wat="$TMP_DIR/host-wit.wat"
if ! build_fixture "$host_wit_fixture" "$host_wit_wat"; then
    printf '[FAIL] host/WIT residual fixture failed to build: %s\n' "$host_wit_fixture" >&2
    cat "$host_wit_wat.stderr" >&2
    exit 1
fi
if ! rg -q ';; wasi-bind source="entry" alias="host_preopens"' "$host_wit_wat"; then
    printf '[FAIL] host/WIT output lacks its binding manifest record: %s\n' "$host_wit_fixture" >&2
    exit 1
fi
if ! rg -q 'import "cm32p2\|wasi:filesystem/preopens" "get-directories"' "$host_wit_wat"; then
    printf '[FAIL] host/WIT output lacks its canonical import: %s\n' "$host_wit_fixture" >&2
    exit 1
fi
if ! rg -q '__arc_' "$host_wit_wat"; then
    printf '[FAIL] host/WIT residual output unexpectedly lacks ARC marker: %s\n' "$host_wit_fixture" >&2
    exit 1
fi
if rg -q ';; gc-sync' "$host_wit_wat"; then
    printf '[FAIL] host/WIT residual output selected the GC route: %s\n' "$host_wit_fixture" >&2
    exit 1
fi
"$WASM_TOOLS_BIN" parse "$host_wit_wat" -o "$TMP_DIR/host-wit.wasm" >/dev/null
printf '[PASS] host/WIT managed boundary remains ARC and parses: %s\n' "$(basename "$host_wit_fixture")"

residual_fixture="$ROOT_DIR/src/build/test/compile_ok/203_arc_field_reflection_get_return_fresh_local_defer_keeps_inc_lower.do"
residual_wat="$TMP_DIR/residual.wat"
if ! build_fixture "$residual_fixture" "$residual_wat"; then
    printf '[FAIL] residual fixture unexpectedly failed to build: %s\n' "$residual_fixture" >&2
    cat "$residual_wat.stderr" >&2
    exit 1
fi
if [[ "$MODE" == baseline ]]; then
    if rg -q '__arc_' "$residual_wat"; then
        printf '[FAIL] migrated field-reflection output still contains ARC marker: %s\n' "$residual_fixture" >&2
        exit 1
    fi
    if ! rg -q ';; gc-sync' "$residual_wat" || ! rg -q ';; field-reflect-gc type=User' "$residual_wat"; then
        printf '[FAIL] migrated field-reflection output lacks typed GC markers: %s\n' "$residual_fixture" >&2
        exit 1
    fi
    printf '[PASS] migrated field-reflection build is GC-only: %s\n' "$(basename "$residual_fixture")"
    assert_active_arc_residuals
else
    if rg -q '__arc_' "$residual_wat"; then
        printf '[FAIL] residual default output still contains ARC marker: %s\n' "$residual_fixture" >&2
        exit 1
    fi
    printf '[PASS] residual default build is ARC-free: %s\n' "$(basename "$residual_fixture")"
    assert_no_active_arc_residuals
fi

gc_core_fixture="$ROOT_DIR/examples/gc-p3-runtime/managed-struct-preserve-field.do"
gc_core_wat="$TMP_DIR/gc-core.wat"
if [[ "$MODE" == baseline ]]; then
    if ! build_fixture "$gc_core_fixture" "$gc_core_wat" --gc-core; then
        printf '[FAIL] --gc-core migration oracle was not accepted: %s\n' "$gc_core_fixture" >&2
        cat "$gc_core_wat.stderr" >&2
        exit 1
    fi
    if rg -q '__arc_' "$gc_core_wat"; then
        printf '[FAIL] --gc-core output contains ARC marker: %s\n' "$gc_core_fixture" >&2
        exit 1
    fi
    assert_gc_managed_output_shape "$gc_core_wat"
    run_gc_core_oracle "$gc_core_wat"
else
    cutover_wat="$TMP_DIR/gc-core-cutover.wat"
    if build_fixture "$gc_core_fixture" "$cutover_wat" --gc-core; then
        printf '[FAIL] --gc-core was accepted after cutover\n' >&2
        exit 1
    fi
    if [[ -e "$cutover_wat" ]]; then
        printf '[FAIL] --gc-core rejection left an output artifact: %s\n' "$cutover_wat" >&2
        exit 1
    fi
    if ! rg -q 'error\[UnexpectedCliArg\]' "$cutover_wat.stderr"; then
        printf '[FAIL] --gc-core rejection lacks a selector diagnostic\n' >&2
        cat "$cutover_wat.stderr" >&2
        exit 1
    fi
    printf '[PASS] --gc-core is rejected after cutover\n'
fi

if [[ "$MODE" == baseline ]]; then
    check_inventory 1
else
    check_inventory 0
fi

if [[ "$MODE" == baseline ]]; then
    printf 'G5c residual baseline gate passed: admitted GC, residual ARC, gc-core oracle, inventory pending\n'
else
    printf 'G5c cutover residual gate passed: admitted GC, no ARC residual, no gc-core selector, inventory complete\n'
fi
