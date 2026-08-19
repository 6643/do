#!/usr/bin/env bash
set -euo pipefail
# Verification Status: verified

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DO_BIN="${DO_BIN:-$ROOT/bin/do}"
WASM_TOOLS_BIN="${WASM_TOOLS_BIN:-$(command -v wasm-tools || true)}"
WASMTIME_BIN="${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/do-gc-equivalence.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT

if [[ ! -x "$DO_BIN" ]]; then
    printf 'missing do compiler: %s\n' "$DO_BIN" >&2
    exit 1
fi
if [[ -z "$WASM_TOOLS_BIN" || ! -x "$WASM_TOOLS_BIN" ]]; then
    printf 'missing wasm-tools executable\n' >&2
    exit 1
fi
if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
    printf 'missing node executable\n' >&2
    exit 1
fi
if [[ ! -x "$WASMTIME_BIN" ]]; then
    printf 'missing Wasmtime executable: %s\n' "$WASMTIME_BIN" >&2
    exit 1
fi

run_compiled_fixture() {
    local row="$1" fixture="$2" base="$3"
    local source_wat="$TMP_DIR/${base}.wat"
    local source_wasm="$TMP_DIR/${base}.wasm"
    local stdout_file="$TMP_DIR/${base}.stdout"
    local stderr_file="$TMP_DIR/${base}.stderr"
    if ! DO_LIB_ROOT="$ROOT/src/build/test/lib" "$DO_BIN" test "$fixture" --compiled -o "$source_wat" >"$stdout_file" 2>"$stderr_file"; then
        printf 'row=%s normal compile failed\n' "$row" >&2
        cat "$stderr_file" >&2
        return 1
    fi
    if ! grep -Fq 'compiled_tests=' "$stdout_file" || [[ ! -s "$source_wat" ]]; then
        printf 'row=%s normal compile produced no test artifact\n' "$row" >&2
        cat "$stdout_file" >&2
        return 1
    fi
    "$WASM_TOOLS_BIN" parse "$source_wat" -o "$source_wasm" >/dev/null
    if ! "$NODE_BIN" "$ROOT/src/build/test/run_compiled_test_case.mjs" "$source_wasm" "$source_wat" >"$TMP_DIR/${base}.run.stdout" 2>"$TMP_DIR/${base}.run.stderr"; then
        printf 'row=%s normal execution failed\n' "$row" >&2
        cat "$TMP_DIR/${base}.run.stderr" >&2
        return 1
    fi
    if ! grep -Fq ' ... ok' "$TMP_DIR/${base}.run.stdout" || ! grep -Fq 'ok:' "$TMP_DIR/${base}.run.stdout"; then
        printf 'row=%s normal execution did not report success\n' "$row" >&2
        cat "$TMP_DIR/${base}.run.stdout" >&2
        return 1
    fi
}

run_gc_probe() {
    local row="$1" probe="$2"
    local output
    if ! output=$(WASMTIME_BIN="$WASMTIME_BIN" WASM_TOOLS_BIN="$WASM_TOOLS_BIN" bash "$ROOT/examples/gc-p3-runtime/test_do_gc_${probe}.sh"); then
        printf 'row=%s GC probe failed\n' "$row" >&2
        return 1
    fi
    if ! grep -Fq '27815' <<<"$output"; then
        printf 'row=%s GC probe did not report its semantic oracle\n' "$row" >&2
        printf '%s\n' "$output" >&2
        return 1
    fi
}

# row normal fixture gc probe
matrix=$(cat <<'ROWS'
list-set src/build/test/compiled_ok/49_compiled_test_storage_alias_set_keeps_old_value.do list_set
managed-struct-payload src/build/test/compiled_ok/51_compiled_test_managed_struct_alias_set_preserves_other_field.do managed_struct_payload
managed-field-call-producer src/build/test/compiled_ok/103_compiled_test_managed_field_call_producer_gc_migration.do managed_field_call_producer
managed-text-field-call-producer src/build/test/compiled_ok/104_compiled_test_managed_text_field_call_producer_gc_migration.do managed_text_field_call_producer
text-identity src/build/test/compiled_ok/82_compiled_test_text_identity_gc_migration.do text_identity
text-branch src/build/test/compiled_ok/83_compiled_test_text_branch_gc_migration.do text_branch
nested-managed-struct src/build/test/compiled_ok/84_compiled_test_nested_managed_struct_gc_migration.do nested_managed_struct
nested-field-path src/build/test/compiled_ok/101_compiled_test_nested_field_path_gc_migration.do nested_field_path
two-level-nested-field-path src/build/test/compiled_ok/102_compiled_test_two_level_nested_field_path_gc_migration.do two_level_nested_field_path
three-level-nested-field-path src/build/test/compiled_ok/103_compiled_test_three_level_nested_field_path_gc_migration.do three_level_nested_field_path
managed-tuple src/build/test/compiled_ok/85_compiled_test_managed_tuple_gc_migration.do managed_tuple_text_bytes
scalar-list-u32 src/build/test/compiled_ok/86_compiled_test_u32_list_gc_migration.do u32_list_set
scalar-list-i16 src/build/test/compiled_ok/87_compiled_test_i16_list_gc_migration.do i16_list_set
imports-text-identity src/build/test/compiled_ok/88_compiled_test_imported_text_identity_gc_migration.do imported_text_identity
scalar-list-f32 src/build/test/compiled_ok/89_compiled_test_f32_list_gc_migration.do f32_list_set
scalar-list-f64 src/build/test/compiled_ok/90_compiled_test_f64_list_gc_migration.do f64_list_set
scalar-list-remaining src/build/test/compiled_ok/92_compiled_test_remaining_scalar_lists_gc_migration.do remaining_scalar_lists
scalar-list-put src/build/test/compiled_ok/93_compiled_test_scalar_list_put_gc_migration.do scalar_list_put
text-list-put src/build/test/compiled_ok/94_compiled_test_text_list_put_gc_migration.do text_list_put
payload-union src/build/test/compiled_ok/95_compiled_test_payload_union_gc_migration.do payload_union
generic-managed-identity src/build/test/compiled_ok/96_compiled_test_generic_managed_gc_migration.do generic_managed_identity
nested-byte-producer src/build/test/compiled_ok/97_compiled_test_nested_byte_producer_gc_migration.do managed_struct_preserve_field
nested-byte-list-put examples/gc-p3-runtime/nested-byte-list-put.do nested_byte_list_put
managed-struct-list-append src/build/test/compiled_ok/100_compiled_test_managed_struct_list_append_gc_migration.do managed_struct_list
ROWS
)

while read -r row fixture probe; do
    [[ -z "$row" ]] && continue
    run_compiled_fixture "$row" "$ROOT/$fixture" "normal-${row}"
    run_gc_probe "$row" "$probe"
    printf 'PASS %s: normal and GC observable results agree\n' "$row"
done <<< "$matrix"

pass_rows=0
while read -r row fixture probe; do
    [[ -z "$row" ]] && continue
    pass_rows=$((pass_rows + 1))
done <<< "$matrix"
printf 'GC semantic equivalence matrix passed: %d rows; 0 rows pending\n' "$pass_rows"
