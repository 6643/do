#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"
DO_BIN="${DO_BIN:-$ROOT_DIR/bin/do}"
TOOLCHAIN_BIN="${DO_TOOLCHAIN_BIN:-$ROOT_DIR/bin/do-toolchain}"
# Residual downstream gates still consume this historical environment contract.
WASM_TOOLS_BIN="${WASM_TOOLS_BIN:-$(command -v wasm-tools || true)}"
WASMTIME_BIN="${WASMTIME_BIN:-$(command -v wasmtime || true)}"
ZIG_BIN="${ZIG_BIN:-zig}"
CARGO_BIN="${CARGO_BIN:-cargo}"
MODE="${1:-baseline}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/do-gc-g5c-residual.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$ROOT_DIR/toolchain/toolchain.lock.json}"

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
if [[ ! -x "$TOOLCHAIN_BIN" ]]; then
    printf '[FAIL] missing do-toolchain executable: %s\n' "$TOOLCHAIN_BIN" >&2
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

toolchain_probe_output="$($TOOLCHAIN_BIN probe 2>&1)" || {
    printf '[FAIL] current toolchain probe failed:\n%s\n' "$toolchain_probe_output" >&2
    exit 1
}
if [[ "$toolchain_probe_output" != *'"schema":1'* || "$toolchain_probe_output" != *'"wasm_tools":'* ]]; then
    printf '[FAIL] current toolchain probe returned no wasm-tools identity:\n%s\n' "$toolchain_probe_output" >&2
    exit 1
fi
printf '[PASS] pinned wasm-tools identity verified by do-toolchain probe\n'

run_future_frame_equivalence_gate() {
    local gate_output="$TMP_DIR/gc-async-frame-equivalence.output"
    if ! DO_BIN="$DO_BIN" \
        WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_async_frame_equivalence.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] bounded Future G5b GC/linear equivalence gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] bounded Future G5b GC/linear equivalence gate included\n'
}

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

run_random_equivalence_gate() {
    local gate_output="$TMP_DIR/gc-wasi-random-equivalence.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_wasi_random_list_lift_equivalence.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed WASI random ARC/GC equivalence gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed WASI random ARC/GC equivalence gate included\n'
}

run_text_equivalence_gate() {
    local gate_output="$TMP_DIR/gc-marshal-text-equivalence.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_text_equivalence.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed text ARC/GC equivalence gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed text ARC/GC equivalence gate included\n'
}

run_u32_lower_equivalence_gate() {
    local gate_output="$TMP_DIR/gc-marshal-u32-equivalence.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_u32_equivalence.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed list<u32> lower ARC/GC equivalence gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed list<u32> lower ARC/GC equivalence gate included\n'
}

run_u32_lift_equivalence_gate() {
    local gate_output="$TMP_DIR/gc-marshal-u32-lift-equivalence.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_u32_lift_equivalence.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed list<u32> lift ARC/GC equivalence gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed list<u32> lift ARC/GC equivalence gate included\n'
}

run_record_lower_manifest_host_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-lower-manifest-host.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_lower_manifest_host.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed scalar record lower host gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed scalar record lower host gate included\n'
}

run_record_lower_manifest_equivalence_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-lower-manifest-equivalence.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_lower_manifest_equivalence.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed scalar record lower ARC/GC equivalence gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed scalar record lower ARC/GC equivalence gate included\n'
}

run_record_lift_manifest_host_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-lift-manifest-host.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_lift_manifest_host.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed scalar record lift host gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed scalar record lift host gate included\n'
}

run_record_lift_manifest_equivalence_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-lift-manifest-equivalence.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_lift_manifest_equivalence.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed scalar record lift ARC/GC equivalence gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed scalar record lift ARC/GC equivalence gate included\n'
}

run_mixed_record_lift_manifest_host_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-mixed-lift-manifest-host.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_lift_manifest_host.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed mixed scalar record lift host gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed mixed scalar record lift host gate included\n'
}

run_mixed_record_lift_manifest_equivalence_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-mixed-lift-manifest-equivalence.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_lift_manifest_equivalence.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed mixed scalar record lift ARC/GC equivalence gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed mixed scalar record lift ARC/GC equivalence gate included\n'
}

run_indirect_record_lower_manifest_host_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-indirect-lower-manifest-host.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_manifest_host.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed indirect scalar record lower host gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed indirect scalar record lower host gate included\n'
}

run_indirect_record_lower_manifest_equivalence_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-indirect-lower-manifest-equivalence.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_manifest_equivalence.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed indirect scalar record lower ARC/GC equivalence gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed indirect scalar record lower ARC/GC equivalence gate included\n'
}

run_nested_record_lift_manifest_host_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-nested-lift-manifest-host.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_host.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed nested scalar record lift host gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed nested scalar record lift host gate included\n'
}

run_nested_record_lift_manifest_equivalence_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-nested-lift-manifest-equivalence.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_equivalence.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed nested scalar record lift ARC/GC equivalence gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed nested scalar record lift ARC/GC equivalence gate included\n'
}

run_nested_record_lower_manifest_host_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-nested-lower-manifest-host.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_manifest_host.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed nested scalar record lower host gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed nested scalar record lower host gate included\n'
}

run_nested_record_lower_manifest_equivalence_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-nested-lower-manifest-equivalence.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_manifest_equivalence.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed nested scalar record lower ARC/GC equivalence gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed nested scalar record lower ARC/GC equivalence gate included\n'
}

run_nested_record_lower_deep_manifest_host_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-nested-lower-deep-manifest-host.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deep_manifest_host.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed three-level nested scalar record lower host gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed three-level nested scalar record lower host gate included\n'
}

run_nested_record_lower_deep_manifest_equivalence_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-nested-lower-deep-manifest-equivalence.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deep_manifest_equivalence.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed three-level nested scalar record lower ARC/GC equivalence gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed three-level nested scalar record lower ARC/GC equivalence gate included\n'
}

run_nested_record_lift_deep_manifest_host_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-nested-lift-deep-manifest-host.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deep_manifest_host.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed three-level nested scalar record lift host gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed three-level nested scalar record lift host gate included\n'
}

run_nested_record_lift_deep_manifest_equivalence_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-nested-lift-deep-manifest-equivalence.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deep_manifest_equivalence.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed three-level nested scalar record lift ARC/GC equivalence gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed three-level nested scalar record lift ARC/GC equivalence gate included\n'
}

run_nested_record_deeper_manifest_gate() {
    local direction="$1" phase="$2"
    local script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_nested_${direction}_deeper_manifest_${phase}.sh"
    local gate_output="$TMP_DIR/gc-marshal-record-nested-${direction}-deeper-manifest-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed four-level nested scalar record %s %s gate failed\n' "$direction" "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed four-level nested scalar record %s %s gate included\n' "$direction" "$phase"
}

run_nested_record_deeper_compiler_gate() {
    local direction="$1" phase="$2"
    local script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_nested_${direction}_deeper_compiler_${phase}.sh"
    local gate_output="$TMP_DIR/gc-marshal-record-nested-${direction}-deeper-compiler-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] compiler-wired four-level nested scalar record %s %s gate failed\n' "$direction" "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] compiler-wired four-level nested scalar record %s %s gate included\n' "$direction" "$phase"
}

run_nested_record_deeper_compiler_negative_gate() {
    local gate_output="$TMP_DIR/gc-marshal-record-nested-deeper-compiler-negative.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        bash "$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_nested_deeper_compiler_boundary_negative.sh" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] compiler-wired four-level nested scalar record negative gate failed\n' >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] compiler-wired four-level nested scalar record negative gate included\n'
}

run_managed_record_lift_manifest_gate() {
    local phase="$1"
    local script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_manifest_${phase}.sh"
    local gate_output="$TMP_DIR/gc-marshal-record-managed-lift-manifest-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed managed-field record lift %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed managed-field record lift %s gate included\n' "$phase"
}

run_managed_record_lower_manifest_gate() {
    local phase="$1"
    local script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_manifest_${phase}.sh"
    local gate_output="$TMP_DIR/gc-marshal-record-managed-lower-manifest-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed managed-field record lower %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed managed-field record lower %s gate included\n' "$phase"
}

run_byte_list_record_lower_manifest_gate() {
    local phase="$1"
    local script
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lower_manifest_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lower_manifest_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lower_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown byte-list record lower gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    local gate_output="$TMP_DIR/gc-marshal-record-byte-list-lower-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        DO_BIN="$DO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed byte-list record lower %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed byte-list record lower %s gate included\n' "$phase"
}

run_byte_list_record_lift_manifest_gate() {
    local phase="$1"
    local script
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lift_manifest_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lift_manifest_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lift_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown byte-list record lift gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    local gate_output="$TMP_DIR/gc-marshal-record-byte-list-lift-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        DO_BIN="$DO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed byte-list record lift %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed byte-list record lift %s gate included\n' "$phase"
}

run_u32_list_record_lift_manifest_gate() {
    local phase="$1"
    local script
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_u32_list_lift_manifest_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_u32_list_lift_manifest_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_u32_list_lift_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown u32-list record lift gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    local gate_output="$TMP_DIR/gc-marshal-record-u32-list-lift-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        DO_BIN="$DO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed u32-list record lift %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed u32-list record lift %s gate included\n' "$phase"
}

run_mixed_text_u32_list_record_lift_manifest_gate() {
    local phase="$1"
    local script
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_u32_list_lift_manifest_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_u32_list_lift_manifest_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_u32_list_lift_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown mixed text/u32-list record lift gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    local gate_output="$TMP_DIR/gc-marshal-record-mixed-text-u32-list-lift-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        DO_BIN="$DO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed mixed text/u32-list record lift %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed mixed text/u32-list record lift %s gate included\n' "$phase"
}

run_mixed_text_byte_list_record_lift_manifest_gate() {
    local phase="$1"
    local script
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_list_lift_manifest_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_list_lift_manifest_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_list_lift_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown mixed text/byte-list record lift gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    local gate_output="$TMP_DIR/gc-marshal-record-mixed-text-byte-list-lift-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        DO_BIN="$DO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed mixed text/byte-list record lift %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed mixed text/byte-list record lift %s gate included\n' "$phase"
}

run_mixed_text_two_u32_lists_record_lift_manifest_gate() {
    local phase="$1"
    local script
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_two_u32_lists_lift_manifest_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_two_u32_lists_lift_manifest_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_two_u32_lists_lift_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown mixed text/two-u32-list record lift gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    local gate_output="$TMP_DIR/gc-marshal-record-mixed-text-two-u32-lists-lift-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        DO_BIN="$DO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed mixed text/two-u32-list record lift %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed mixed text/two-u32-list record lift %s gate included\n' "$phase"
}

run_two_u32_lists_lower_gate() {
    local phase="$1" script gate_output
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_two_u32_lists_lower_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_two_u32_lists_lower_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_two_u32_lists_lower_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown two-u32-list record lower gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    gate_output="$TMP_DIR/gc-marshal-record-two-u32-lists-lower-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        DO_BIN="$DO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed two-u32-list record lower %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed two-u32-list record lower %s gate included\n' "$phase"
}

run_mixed_text_byte_u32_lists_lower_gate() {
    local phase="$1" script gate_output
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_u32_lists_lower_manifest_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_u32_lists_lower_manifest_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_u32_lists_lower_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown mixed text/byte-u32-list record lower gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    gate_output="$TMP_DIR/gc-marshal-record-mixed-text-byte-u32-lists-lower-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        DO_BIN="$DO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] manifest-backed mixed text/byte-u32-list record lower %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] manifest-backed mixed text/byte-u32-list record lower %s gate included\n' "$phase"
}

run_default_multi_managed_route_gate() {
    local phase="$1"
    local script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_multi${phase}.sh"
    local gate_output="$TMP_DIR/gc-default-managed-multi${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] default multi-managed-text route%s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] default multi-managed-text route%s gate included\n' "$phase"
}

run_default_c14_nested_record_deeper_gate() {
    local phase="$1" script gate_output
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_nested_record_deeper.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_nested_record_deeper_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_nested_record_deeper_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown default C14 nested-record gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    gate_output="$TMP_DIR/gc-default-c14-nested-record-deeper-${phase}.output"
    if ! DO_BIN="$DO_BIN" \
        WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] default C14 four-level nested scalar record %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] default C14 four-level nested scalar record %s gate included\n' "$phase"
}

run_default_mixed_lower_gate() {
    local phase="$1" script gate_output
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_lower_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_lower_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_lower_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown default mixed-lower gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    gate_output="$TMP_DIR/gc-default-mixed-lower-${phase}.output"
    if ! DO_BIN="$DO_BIN" \
        WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] default mixed scalar record lower %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] default mixed scalar record lower %s gate included\n' "$phase"
}

run_default_mixed_scalar_list_lower_gate() {
    local phase="$1" script gate_output
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_scalar_list_lower_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_scalar_list_lower_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_scalar_list_lower_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown default mixed scalar-list lower gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    gate_output="$TMP_DIR/gc-default-mixed-scalar-list-lower-${phase}.output"
    if ! DO_BIN="$DO_BIN" \
        WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] default mixed scalar-list record lower %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] default mixed scalar-list record lower %s gate included\n' "$phase"
}

run_default_mixed_text_u32_list_lower_gate() {
    local phase="$1" script gate_output
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lower_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lower_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lower_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown default mixed text/u32-list lower gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    gate_output="$TMP_DIR/gc-default-mixed-text-u32-list-lower-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        DO_BIN="$DO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] default mixed text/u32-list lower %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] default mixed text/u32-list lower %s gate included\n' "$phase"
}

run_default_mixed_text_u32_list_lift_gate() {
    local phase="$1" script gate_output
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lift_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lift_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lift_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown default mixed text/u32-list lift gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    gate_output="$TMP_DIR/gc-default-mixed-text-u32-list-lift-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        DO_BIN="$DO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] default mixed text/u32-list lift %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] default mixed text/u32-list lift %s gate included\n' "$phase"
}

run_default_mixed_text_byte_list_lift_gate() {
    local phase="$1" script gate_output
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_byte_list_lift_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_byte_list_lift_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_byte_list_lift_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown default mixed text/byte-list lift gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    gate_output="$TMP_DIR/gc-default-mixed-text-byte-list-lift-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        DO_BIN="$DO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] default mixed text/byte-list lift %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] default mixed text/byte-list lift %s gate included\n' "$phase"
}

run_default_mixed_text_two_u32_lists_lift_gate() {
    local phase="$1" script gate_output
    case "$phase" in
        host)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_two_u32_lists_lift_host.sh"
            ;;
        equivalence)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_two_u32_lists_lift_equivalence.sh"
            ;;
        negative)
            script="$ROOT_DIR/examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_two_u32_lists_lift_negative.sh"
            ;;
        *)
            printf '[FAIL] unknown default mixed text/two-u32-list lift gate phase: %s\n' "$phase" >&2
            return 1
            ;;
    esac
    gate_output="$TMP_DIR/gc-default-mixed-text-two-u32-lists-lift-${phase}.output"
    if ! WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        ZIG_BIN="$ZIG_BIN" \
        CARGO_BIN="$CARGO_BIN" \
        DO_BIN="$DO_BIN" \
        bash "$script" >"$gate_output" 2>&1; then
        cat "$gate_output" >&2
        printf '[FAIL] default mixed text/two-u32-list lift %s gate failed\n' "$phase" >&2
        return 1
    fi
    tail -n 1 "$gate_output"
    printf '[PASS] default mixed text/two-u32-list lift %s gate included\n' "$phase"
}

run_future_frame_equivalence_gate
run_descriptor_manifest_gate
run_random_equivalence_gate
run_text_equivalence_gate
run_u32_lower_equivalence_gate
run_u32_lift_equivalence_gate
run_record_lower_manifest_host_gate
run_record_lower_manifest_equivalence_gate
run_record_lift_manifest_host_gate
run_record_lift_manifest_equivalence_gate
run_mixed_record_lift_manifest_host_gate
run_mixed_record_lift_manifest_equivalence_gate
run_indirect_record_lower_manifest_host_gate
run_indirect_record_lower_manifest_equivalence_gate
run_nested_record_lift_manifest_host_gate
run_nested_record_lift_manifest_equivalence_gate
run_nested_record_lower_manifest_host_gate
run_nested_record_lower_manifest_equivalence_gate
run_nested_record_lower_deep_manifest_host_gate
run_nested_record_lower_deep_manifest_equivalence_gate
run_nested_record_lift_deep_manifest_host_gate
run_nested_record_lift_deep_manifest_equivalence_gate
run_nested_record_deeper_manifest_gate lower host
run_nested_record_deeper_manifest_gate lower equivalence
run_nested_record_deeper_manifest_gate lift host
run_nested_record_deeper_manifest_gate lift equivalence
run_nested_record_deeper_compiler_gate lower host
run_nested_record_deeper_compiler_gate lower equivalence
run_nested_record_deeper_compiler_gate lift host
run_nested_record_deeper_compiler_gate lift equivalence
run_nested_record_deeper_compiler_negative_gate
run_managed_record_lift_manifest_gate host
run_managed_record_lift_manifest_gate equivalence
run_managed_record_lower_manifest_gate host
run_managed_record_lower_manifest_gate equivalence
run_byte_list_record_lower_manifest_gate host
run_byte_list_record_lower_manifest_gate equivalence
run_byte_list_record_lower_manifest_gate negative
run_byte_list_record_lift_manifest_gate host
run_byte_list_record_lift_manifest_gate equivalence
run_byte_list_record_lift_manifest_gate negative
run_u32_list_record_lift_manifest_gate host
run_u32_list_record_lift_manifest_gate equivalence
run_u32_list_record_lift_manifest_gate negative
run_mixed_text_u32_list_record_lift_manifest_gate host
run_mixed_text_u32_list_record_lift_manifest_gate equivalence
run_mixed_text_u32_list_record_lift_manifest_gate negative
run_mixed_text_byte_list_record_lift_manifest_gate host
run_mixed_text_byte_list_record_lift_manifest_gate equivalence
run_mixed_text_byte_list_record_lift_manifest_gate negative
run_mixed_text_two_u32_lists_record_lift_manifest_gate host
run_mixed_text_two_u32_lists_record_lift_manifest_gate equivalence
run_mixed_text_two_u32_lists_record_lift_manifest_gate negative
run_two_u32_lists_lower_gate host
run_two_u32_lists_lower_gate equivalence
run_two_u32_lists_lower_gate negative
run_mixed_text_byte_u32_lists_lower_gate host
run_mixed_text_byte_u32_lists_lower_gate equivalence
run_mixed_text_byte_u32_lists_lower_gate negative
run_default_multi_managed_route_gate ""
run_default_multi_managed_route_gate "_equivalence"
run_default_c14_nested_record_deeper_gate host
run_default_c14_nested_record_deeper_gate equivalence
run_default_c14_nested_record_deeper_gate negative
run_default_mixed_lower_gate host
run_default_mixed_lower_gate equivalence
run_default_mixed_lower_gate negative
run_default_mixed_scalar_list_lower_gate host
run_default_mixed_scalar_list_lower_gate equivalence
run_default_mixed_scalar_list_lower_gate negative
run_default_mixed_text_u32_list_lower_gate host
run_default_mixed_text_u32_list_lower_gate equivalence
run_default_mixed_text_u32_list_lower_gate negative
run_default_mixed_text_u32_list_lift_gate host
run_default_mixed_text_u32_list_lift_gate equivalence
run_default_mixed_text_u32_list_lift_gate negative
run_default_mixed_text_byte_list_lift_gate host
run_default_mixed_text_byte_list_lift_gate equivalence
run_default_mixed_text_byte_list_lift_gate negative
run_default_mixed_text_two_u32_lists_lift_gate host
run_default_mixed_text_two_u32_lists_lift_gate equivalence
run_default_mixed_text_two_u32_lists_lift_gate negative

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
    "$TOOLCHAIN_BIN" parse-core "$wat_file" -o "$TMP_DIR/gc-core.wasm" >/dev/null
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
"$TOOLCHAIN_BIN" parse-core "$admitted_wat" -o "$TMP_DIR/admitted.wasm" >/dev/null
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
"$TOOLCHAIN_BIN" parse-core "$migrated_wat" -o "$TMP_DIR/migrated-if-else.wasm" >/dev/null
printf '[PASS] migrated default build is GC-only and parses: %s\n' "$(basename "$migrated_fixture")"

host_wit_fixture="$ROOT_DIR/src/build/test/compile_ok/274_wasi_preopens_list_tuple_lower.do"
host_wit_wat="$TMP_DIR/host-wit.wat"
host_wit_status=0
if build_fixture "$host_wit_fixture" "$host_wit_wat"; then
    host_wit_status=0
else
    host_wit_status=$?
fi
if [[ "$host_wit_status" -eq 0 ]]; then
    printf '[FAIL] host/WIT residual fixture unexpectedly accepted: %s\n' "$host_wit_fixture" >&2
    exit 1
fi
if [[ -e "$host_wit_wat" ]]; then
    printf '[FAIL] host/WIT residual fixture left a WAT artifact after rejection: %s\n' "$host_wit_fixture" >&2
    exit 1
fi
if ! grep -Fq 'error[UnsupportedGcSyncModuleGraph]' "$host_wit_wat.stderr"; then
    printf '[FAIL] host/WIT residual fixture missing diagnostic error[UnsupportedGcSyncModuleGraph]: %s\n' "$host_wit_fixture" >&2
    cat "$host_wit_wat.stderr" >&2
    exit 1
fi
printf '[PASS] host/WIT residual fixture rejected before WAT emission with error[UnsupportedGcSyncModuleGraph] (status=%s): %s\n' "$host_wit_status" "$(basename "$host_wit_fixture")"

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
    printf 'G5c residual baseline gate passed: bounded Future G5b equivalence, admitted GC, residual ARC, gc-core oracle, manifest random/text/list<u32>/scalar-record/mixed/mixed-lower/managed-field/managed-field-lower/byte-list-record-lower/nested-record/mixed-text-u32-list lift-lower/two-u32-list lower equivalence including three-level and four-level nested lower/lift, default multi-managed-text and C14 nested-record/mixed-lower/mixed-text-u32-list-lower/mixed-text-u32-list-lift/two-u32-list lower host/equivalence/negative, inventory pending\n'
else
    printf 'G5c cutover residual gate passed: bounded Future G5b equivalence, admitted GC, mixed-lower coverage, no ARC residual, no gc-core selector, inventory complete\n'
fi
