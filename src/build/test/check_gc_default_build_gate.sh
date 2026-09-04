#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/examples/gc-p3-runtime"
DO_BIN="${DO_BIN:-$ROOT_DIR/bin/do}"
TOOLCHAIN_BIN="${DO_TOOLCHAIN_BIN:-$ROOT_DIR/bin/do-toolchain}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/do-gc-default-build.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT

if [[ ! -x "$DO_BIN" ]]; then
    printf 'missing do compiler executable: %s\n' "$DO_BIN" >&2
    exit 1
fi
if [[ ! -x "$TOOLCHAIN_BIN" ]]; then
    printf 'missing do-toolchain executable: %s\n' "$TOOLCHAIN_BIN" >&2
    exit 1
fi

assert_no_arc_marker() {
    local wat_file="$1"
    if rg -q '__arc_' "$wat_file"; then
        printf 'generated WAT contains obsolete ARC marker: %s\n' "$wat_file" >&2
        return 1
    fi
}

assert_gc_marker() {
    local wat_file="$1"
    if ! rg -q ';; gc-sync ' "$wat_file" || ! rg -q '\$do_' "$wat_file"; then
        printf 'generated WAT lacks the expected GC lowering markers: %s\n' "$wat_file" >&2
        return 1
    fi
}

# Keep the residual scan itself covered: a marker-bearing WAT must be rejected.
negative_wat="$TMP_DIR/negative-marker.wat"
printf '(module (func $__arc_negative_marker))\n' >"$negative_wat"
if assert_no_arc_marker "$negative_wat"; then
    printf 'ARC marker negative check unexpectedly accepted marker\n' >&2
    exit 1
fi
negative_gc_wat="$TMP_DIR/negative-gc-marker.wat"
printf '(module (func $_start))\n' >"$negative_gc_wat"
if assert_gc_marker "$negative_gc_wat"; then
    printf 'GC marker negative check unexpectedly accepted non-GC WAT\n' >&2
    exit 1
fi

expected_fixture_manifest=$(cat <<'EOF'
bool-list-set.do
f32-list-literal.do
f32-list-set.do
f64-list-literal.do
f64-list-set.do
five-level-nested-field-path.do
four-level-nested-field-path.do
gc-payload-union.do
generic-managed-identity.do
i16-list-literal.do
i16-list-set.do
i32-list-literal.do
i32-list-set.do
i64-list-literal.do
i64-list-set.do
i8-list.do
imported-text-identity.do
inferred-list-storage.do
inferred-text-binding.do
inferred-u32-list-storage.do
isize-list.do
list-literal.do
list-put.do
list-set.do
managed-field-call-producer.do
managed-struct-bool-field.do
managed-struct-f32-field.do
managed-struct-f64-field.do
managed-struct-i16-field.do
managed-struct-i32-field.do
managed-struct-i64-field.do
managed-struct-i8-field.do
managed-struct-isize-field.do
managed-struct-list.do
managed-struct-payload-renamed.do
managed-struct-payload.do
managed-struct-preserve-field.do
managed-struct-renamed.do
managed-struct-set.do
managed-struct-storage.do
managed-struct-u16-field.do
managed-struct-u32-field.do
managed-struct-u64-field.do
managed-struct-usize-field.do
managed-text-field-call-producer.do
managed-tuple-text-bytes.do
nested-byte-list-put.do
nested-byte-list.do
nested-field-path.do
nested-managed-struct.do
ordinary-host-c14-lift-call.do
ordinary-host-c14-lower-call.do
ordinary-host-c15b-call.do
ordinary-host-c15d-call.do
ordinary-host-c16d-call.do
ordinary-host-mixed-lower-call.do
ordinary-host-mixed-scalar-list-lower-call.do
ordinary-host-mixed-text-u32-list-lower-call.do
ordinary-host-record-byte-list-lift-call.do
ordinary-host-record-byte-list-lower-call.do
ordinary-host-record-mixed-text-byte-list-lift-call.do
ordinary-host-record-mixed-text-byte-u32-lists-lower-call.do
ordinary-host-record-mixed-text-two-u32-lists-lift-call.do
ordinary-host-record-mixed-text-two-u32-lists-lower-call.do
ordinary-host-record-mixed-text-u32-list-lift-call.do
ordinary-host-record-two-u32-lists-lower-call.do
ordinary-host-record-u32-list-lift-call.do
ordinary-host-record-u32-list-lower-call.do
parameterized-list-set-renamed.do
parameterized-list-set.do
scalar-call-graph.do
scalar-control-flow.do
scalar-leaf.do
scalar-list-put.do
text-branch.do
text-identity-renamed.do
text-identity.do
text-list-put.do
text-list.do
three-level-nested-field-path.do
two-level-nested-field-path.do
u16-list.do
u32-list-literal.do
u32-list-set.do
u64-list.do
usize-list.do
EOF
)
actual_fixture_manifest=$(find "$EXAMPLE_DIR" -maxdepth 1 -type f -name '*.do' -printf '%f\n' | sort)
if ! diff -u <(printf '%s\n' "$expected_fixture_manifest") <(printf '%s\n' "$actual_fixture_manifest" | rg -v '^(imported-text-helper|imported_text_helper)\.do$'); then
    printf 'admitted GC fixture manifest drifted\n' >&2
    exit 1
fi
mapfile -t fixtures < <(printf '%s\n' "$expected_fixture_manifest" | sed '/^$/d' | sed "s#^#$EXAMPLE_DIR/#")

pass_count=0
for fixture in "${fixtures[@]}"; do
    name="$(basename "$fixture" .do)"
    wat_file="$TMP_DIR/$name.wat"
    wasm_file="$TMP_DIR/$name.wasm"

    if ! DO_LIB_ROOT="$ROOT_DIR/lib" "$DO_BIN" build "$fixture" -o "$wat_file" >"$TMP_DIR/$name.stdout" 2>"$TMP_DIR/$name.stderr"; then
        printf 'GC default build failed: %s\n' "$fixture" >&2
        cat "$TMP_DIR/$name.stderr" >&2
        exit 1
    fi
    if [[ ! -s "$wat_file" ]]; then
        printf 'GC default build produced no WAT: %s\n' "$fixture" >&2
        exit 1
    fi
    if [[ "$name" == scalar-call-graph ]]; then
        if ! rg -q ';; gc-sync ' "$wat_file" ||
            ! rg -q 'call \$leaf' "$wat_file" ||
            ! rg -q 'call \$middle' "$wat_file"; then
            printf 'scalar-call-graph fixture lacks the expected GC call-chain markers: %s\n' "$wat_file" >&2
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'scalar-call-graph fixture contains an obsolete ARC marker: %s\n' "$wat_file" >&2
            exit 1
        fi
    elif [[ "$name" == scalar-control-flow ]]; then
        if ! rg -q ';; gc-sync ' "$wat_file"; then
            printf 'scalar-control-flow fixture lacks the expected GC lowering marker: %s\n' "$wat_file" >&2
            exit 1
        fi
        if ! rg -q ';; gc-root branch_join' "$wat_file" ||
            ! rg -q ';; gc-root guard_join' "$wat_file"; then
            printf 'scalar-control-flow fixture lacks the expected join markers: %s\n' "$wat_file" >&2
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'scalar-control-flow fixture contains an obsolete ARC marker: %s\n' "$wat_file" >&2
            exit 1
        fi
    elif [[ "$name" == scalar-leaf ]]; then
        if ! rg -q ';; gc-sync ' "$wat_file"; then
            printf 'scalar-leaf fixture lacks the expected GC lowering marker: %s\n' "$wat_file" >&2
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'scalar-leaf fixture contains an obsolete ARC marker: %s\n' "$wat_file" >&2
            exit 1
        fi
    else
        assert_no_arc_marker "$wat_file"
        assert_gc_marker "$wat_file"
    fi
    if [[ "$name" == ordinary-host-c15b-call ]]; then
        rg -q '\(import "demo:marshal-record-managed-lower/api@1.0.0" "write"' "$wat_file"
        rg -q '\(func \$write \(param \$input \(ref null \$writing\)\)' "$wat_file"
        call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
        free_line=$(rg -n 'call \$cabi_realloc' "$wat_file" | tail -1 | cut -d: -f1)
        if [[ -z "$call_line" || -z "$free_line" || "$call_line" -ge "$free_line" ]]; then
            printf 'ordinary C15-B canonical call/cleanup order is invalid: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-c14-lift-call ]]; then
        rg -q '\(import "demo:marshal-record-nested-lift-deeper/api@1.0.0" "read"' "$wat_file"
        rg -q '\(func \$read \(result i32 i64 i64 i64 i64\)' "$wat_file"
        if rg -q 'struct\.(new|get)' "$wat_file"; then
            printf 'ordinary C14 lift unexpectedly crossed a GC struct operation: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-c14-lower-call ]]; then
        rg -q '\(import "demo:marshal-record-nested-lower-deeper/api@1.0.0" "write"' "$wat_file"
        rg -q '\(type \$canonical_lower \(func \(param i32 i64 i64 i64 i64\)\)\)' "$wat_file"
        rg -q '\(func \$write \(param \$__gc_arg_0 i32\) \(param \$__gc_arg_1 i64\) \(param \$__gc_arg_2 i64\) \(param \$__gc_arg_3 i64\) \(param \$__gc_arg_4 i64\)' "$wat_file"
        if rg -q 'struct\.(new|get)' "$wat_file"; then
            printf 'ordinary C14 lower unexpectedly crossed a GC struct operation: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-c15d-call ]]; then
        rg -q '\(import "demo:marshal-record-managed-lower-multi/api@1.0.0" "write"' "$wat_file"
        rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32 i32 i32\)\)\)' "$wat_file"
        call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
        free_line=$(rg -n 'call \$cabi_realloc' "$wat_file" | tail -1 | cut -d: -f1)
        if [[ -z "$call_line" || -z "$free_line" || "$call_line" -ge "$free_line" ]]; then
            printf 'ordinary C15-D canonical call/cleanup order is invalid: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-c16d-call ]]; then
        rg -q '\(import "demo:marshal-record-managed-lift-multi/api@1.0.0" "read"' "$wat_file"
        rg -q '\(type \$canonical_lift \(func \(param i32\)\)\)' "$wat_file"
        test "$(rg -c 'array.set \$do_bytes' "$wat_file")" -eq 2
        test "$(rg -c 'struct.new \$do_text' "$wat_file")" -eq 2
        rg -q 'struct.new \$reading' "$wat_file"
    fi
    if [[ "$name" == ordinary-host-mixed-lower-call ]]; then
        rg -q '\(import "demo:marshal-record-mixed-lower/api@1.0.0" "write"' "$wat_file"
        rg -q '\(type \$canonical_lower \(func \(param i32 i64 i64\)\)\)' "$wat_file"
        if rg -q '^\s*\(import "demo:marshal-record-mixed-lower/api@1.0.0" "write".*\(ref' "$wat_file"; then
            printf 'ordinary mixed scalar lower canonical import unexpectedly carries a GC reference: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-mixed-scalar-list-lower-call ]]; then
        rg -q '\(import "demo:marshal-record-mixed-scalar-list-lower/api@1.0.0" "write"' "$wat_file"
        rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32 i32 i32\)\)\)' "$wat_file"
        if rg -q '^\s*\(import "demo:marshal-record-mixed-scalar-list-lower/api@1.0.0" "write".*\(ref' "$wat_file"; then
            printf 'ordinary mixed scalar-list lower canonical import unexpectedly carries a GC reference: %s\n' "$wat_file" >&2
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'ordinary mixed scalar-list lower route still contains ARC symbols: %s\n' "$wat_file" >&2
            exit 1
        fi
        test "$(rg -c 'array.get_s \$do_bytes' "$wat_file")" -eq 2
        test "$(rg -c 'i32.store8' "$wat_file")" -eq 2
        mapfile -t realloc_lines < <(rg -n 'call \$cabi_realloc' "$wat_file" | cut -d: -f1)
        test "${#realloc_lines[@]}" -eq 4
        call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
        if [[ -z "$call_line" || "$call_line" -ge "${realloc_lines[2]}" || "${realloc_lines[2]}" -ge "${realloc_lines[3]}" ]]; then
            printf 'ordinary mixed scalar-list lower canonical call/free order is invalid: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-mixed-text-u32-list-lower-call ]]; then
        rg -q '\(import "demo:marshal-record-mixed-text-u32-list-lower/api@1.0.0" "write"' "$wat_file"
        rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32 i32 i32\)\)\)' "$wat_file"
        if rg -q '^\s*\(import "demo:marshal-record-mixed-text-u32-list-lower/api@1.0.0" "write".*\(ref' "$wat_file"; then
            printf 'ordinary mixed text/u32-list lower canonical import unexpectedly carries a GC reference: %s\n' "$wat_file" >&2
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'ordinary mixed text/u32-list lower route still contains ARC symbols: %s\n' "$wat_file" >&2
            exit 1
        fi
        test "$(rg -c 'array.get_s \$do_bytes' "$wat_file")" -eq 1
        test "$(rg -c 'i32.store8' "$wat_file")" -eq 1
        test "$(rg -c 'array.get \$do_u32' "$wat_file")" -eq 1
        test "$(rg -c 'i32\.store$' "$wat_file")" -eq 1
        mapfile -t realloc_lines < <(rg -n 'call \$cabi_realloc' "$wat_file" | cut -d: -f1)
        test "${#realloc_lines[@]}" -eq 4
        call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
        if [[ -z "$call_line" || "$call_line" -ge "${realloc_lines[2]}" || "${realloc_lines[2]}" -ge "${realloc_lines[3]}" ]]; then
            printf 'ordinary mixed text/u32-list lower canonical call/free order is invalid: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-record-byte-list-lower-call ]]; then
        rg -q '\(import "demo:marshal-record-byte-list-lower/api@1.0.0" "write"' "$wat_file"
        rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32\)\)\)' "$wat_file"
        if rg -q '^\s*\(import.*\(ref' "$wat_file"; then
            printf 'ordinary byte-list record lower canonical import unexpectedly carries a GC reference: %s\n' "$wat_file" >&2
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'ordinary byte-list record lower route still contains ARC symbols: %s\n' "$wat_file" >&2
            exit 1
        fi
        rg -q 'array.get_s \$do_bytes' "$wat_file"
        rg -q 'i32.store8' "$wat_file"
        test "$(rg -c 'call \$cabi_realloc' "$wat_file")" -eq 2
        call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
        free_line=$(rg -n 'call \$cabi_realloc' "$wat_file" | tail -1 | cut -d: -f1)
        if [[ -z "$call_line" || -z "$free_line" || "$call_line" -ge "$free_line" ]]; then
            printf 'ordinary byte-list record lower canonical call/cleanup order is invalid: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-record-u32-list-lower-call ]]; then
        rg -q '\(import "demo:marshal-record-u32-list-lower/api@1.0.0" "write"' "$wat_file"
        rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32\)\)\)' "$wat_file"
        if rg -q '^\s*\(import.*\(ref' "$wat_file"; then
            printf 'ordinary u32-list record lower canonical import unexpectedly carries a GC reference: %s\n' "$wat_file" >&2
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'ordinary u32-list record lower route still contains ARC symbols: %s\n' "$wat_file" >&2
            exit 1
        fi
        rg -q 'array.get \$do_u32' "$wat_file"
        rg -q 'i32.store' "$wat_file"
        test "$(rg -c 'call \$cabi_realloc' "$wat_file")" -eq 2
        call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
        free_line=$(rg -n 'call \$cabi_realloc' "$wat_file" | tail -1 | cut -d: -f1)
        if [[ -z "$call_line" || -z "$free_line" || "$call_line" -ge "$free_line" ]]; then
            printf 'ordinary u32-list record lower canonical call/cleanup order is invalid: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-record-two-u32-lists-lower-call ]]; then
        rg -q '\(import "demo:marshal-record-two-u32-lists-lower/api@1.0.0" "write"' "$wat_file"
        rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32 i32 i32\)\)\)' "$wat_file"
        if rg -q '^\s*\(import.*\(ref' "$wat_file"; then
            printf 'ordinary two-u32-list record lower canonical import unexpectedly carries a GC reference: %s\n' "$wat_file" >&2
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'ordinary two-u32-list record lower route still contains ARC symbols: %s\n' "$wat_file" >&2
            exit 1
        fi
        test "$(rg -c 'array.get \$do_u32' "$wat_file")" -eq 2
        test "$(rg -c 'call \$cabi_realloc' "$wat_file")" -eq 4
        mapfile -t realloc_lines < <(rg -n 'call \$cabi_realloc' "$wat_file" | cut -d: -f1)
        call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
        second_free_line=$(rg -n 'local.get \$__cabi_ptr_1' "$wat_file" | tail -1 | cut -d: -f1)
        first_free_line=$(rg -n 'local.get \$__cabi_ptr_0' "$wat_file" | tail -1 | cut -d: -f1)
        if [[ "${#realloc_lines[@]}" -ne 4 || -z "$call_line" ||
            -z "$second_free_line" || -z "$first_free_line" ||
            "$call_line" -ge "${realloc_lines[2]}" ||
            "${realloc_lines[2]}" -ge "${realloc_lines[3]}" ||
            "$call_line" -ge "$second_free_line" ||
            "$second_free_line" -ge "$first_free_line" ]]; then
            printf 'ordinary two-u32-list record lower canonical call/cleanup order is invalid: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-record-mixed-text-two-u32-lists-lower-call ]]; then
        rg -q '\(import "demo:marshal-record-mixed-text-two-u32-lists-lower/api@1.0.0" "write"' "$wat_file"
        rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32 i32 i32 i32 i32\)\)\)' "$wat_file"
        if rg -q '^\s*\(import.*\(ref' "$wat_file"; then
            printf 'ordinary mixed text/two-u32-list lower canonical import unexpectedly carries a GC reference: %s\n' "$wat_file" >&2
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'ordinary mixed text/two-u32-list lower route still contains ARC symbols: %s\n' "$wat_file" >&2
            exit 1
        fi
        test "$(rg -c 'array.get_s \$do_bytes' "$wat_file")" -eq 1
        test "$(rg -c 'i32.store8' "$wat_file")" -eq 1
        test "$(rg -c 'array.get \$do_u32' "$wat_file")" -eq 2
        test "$(rg -c 'i32\.store$' "$wat_file")" -eq 2
        mapfile -t realloc_lines < <(rg -n 'call \$cabi_realloc' "$wat_file" | cut -d: -f1)
        call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
        second_free_line=$(rg -n 'local.get \$__cabi_ptr_2$' "$wat_file" | tail -1 | cut -d: -f1)
        first_free_line=$(rg -n 'local.get \$__cabi_ptr_1$' "$wat_file" | tail -1 | cut -d: -f1)
        label_free_line=$(rg -n 'local.get \$__cabi_ptr_0$' "$wat_file" | tail -1 | cut -d: -f1)
        if [[ "${#realloc_lines[@]}" -ne 6 || -z "$call_line" ||
            -z "$second_free_line" || -z "$first_free_line" || -z "$label_free_line" ||
            "$call_line" -ge "$second_free_line" ||
            "$second_free_line" -ge "$first_free_line" ||
            "$first_free_line" -ge "$label_free_line" ]]; then
            printf 'ordinary mixed text/two-u32-list lower canonical call/cleanup order is invalid: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-record-mixed-text-byte-u32-lists-lower-call ]]; then
        rg -q '\(import "demo:marshal-record-mixed-text-byte-u32-lists-lower/api@1.0.0" "write"' "$wat_file"
        rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32 i32 i32 i32 i32\)\)\)' "$wat_file"
        if rg -q '^\s*\(import.*\(ref' "$wat_file"; then
            printf 'ordinary mixed text/byte-u32-list record lower canonical import unexpectedly carries a GC reference: %s\n' "$wat_file"
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'ordinary mixed text/byte-u32-list record lower route still contains ARC symbols: %s\n' "$wat_file"
            exit 1
        fi
        test "$(rg -c 'array.get_s \$do_bytes' "$wat_file")" -eq 2
        test "$(rg -c 'i32.store8' "$wat_file")" -eq 2
        test "$(rg -c 'array.get \$do_u32' "$wat_file")" -eq 1
        test "$(rg -c 'i32\.store$' "$wat_file")" -eq 1
        mapfile -t realloc_lines < <(rg -n 'call \$cabi_realloc' "$wat_file" | cut -d: -f1)
        call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
        values_free_line=$(rg -n 'local.get \$__cabi_ptr_2$' "$wat_file" | tail -1 | cut -d: -f1)
        bytes_free_line=$(rg -n 'local.get \$__cabi_ptr_1$' "$wat_file" | tail -1 | cut -d: -f1)
        label_free_line=$(rg -n 'local.get \$__cabi_ptr_0$' "$wat_file" | tail -1 | cut -d: -f1)
        if [[ "${#realloc_lines[@]}" -ne 6 || -z "$call_line" ||
            -z "$values_free_line" || -z "$bytes_free_line" || -z "$label_free_line" ||
            "$call_line" -ge "$values_free_line" ||
            "$values_free_line" -ge "$bytes_free_line" ||
            "$bytes_free_line" -ge "$label_free_line" ]]; then
            printf 'ordinary mixed text/byte-u32-list record lower canonical call/cleanup order is invalid: %s\n' "$wat_file"
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-record-u32-list-lift-call ]]; then
        rg -q '\(import "demo:marshal-record-u32-list-lift/api@1.0.0" "read"' "$wat_file"
        rg -q '\(type \$canonical_lift \(func \(param i32\)\)\)' "$wat_file"
        if rg -q '^\s*\(import.*\(ref' "$wat_file"; then
            printf 'ordinary u32-list record lift canonical import unexpectedly carries a GC reference: %s\n' "$wat_file" >&2
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'ordinary u32-list record lift route still contains ARC symbols: %s\n' "$wat_file" >&2
            exit 1
        fi
        rg -q 'array.new_default \$do_u32' "$wat_file"
        rg -q 'array.set \$do_u32' "$wat_file"
        rg -q 'struct.new \$reading' "$wat_file"
        test "$(rg -c 'call \$cabi_realloc' "$wat_file")" -eq 1
        call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
        free_line=$(rg -n 'call \$cabi_realloc' "$wat_file" | tail -1 | cut -d: -f1)
        if [[ -z "$call_line" || -z "$free_line" || "$call_line" -ge "$free_line" ]]; then
            printf 'ordinary u32-list record lift canonical call/cleanup order is invalid: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-record-byte-list-lift-call ]]; then
        rg -q '\(import "demo:marshal-record-byte-list-lift/api@1.0.0" "read"' "$wat_file"
        rg -q '\(type \$canonical_lift \(func \(param i32\)\)\)' "$wat_file"
        if rg -q '^\s*\(import.*\(ref' "$wat_file"; then
            printf 'ordinary byte-list record lift canonical import unexpectedly carries a GC reference: %s\n' "$wat_file" >&2
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'ordinary byte-list record lift route still contains ARC symbols: %s\n' "$wat_file" >&2
            exit 1
        fi
        rg -q 'array.new_default \$do_bytes' "$wat_file"
        rg -q 'i32.load8_u' "$wat_file"
        rg -q 'array.set \$do_bytes' "$wat_file"
        rg -q 'struct.new \$reading' "$wat_file"
        test "$(rg -c 'call \$cabi_realloc' "$wat_file")" -eq 1
        call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
        free_line=$(rg -n 'call \$cabi_realloc' "$wat_file" | tail -1 | cut -d: -f1)
        if [[ -z "$call_line" || -z "$free_line" || "$call_line" -ge "$free_line" ]]; then
            printf 'ordinary byte-list record lift canonical call/cleanup order is invalid: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-record-mixed-text-u32-list-lift-call ]]; then
        rg -q '\(import "demo:marshal-record-mixed-text-u32-list-lift/api@1.0.0" "read"' "$wat_file"
        rg -q '\(type \$canonical_lift \(func \(param i32\)\)\)' "$wat_file"
        if rg -q '^\s*\(import.*\(ref' "$wat_file"; then
            printf 'ordinary mixed text/u32-list record lift canonical import unexpectedly carries a GC reference: %s\n' "$wat_file" >&2
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'ordinary mixed text/u32-list record lift route still contains ARC symbols: %s\n' "$wat_file" >&2
            exit 1
        fi
        rg -q 'array.new_default \$do_bytes' "$wat_file"
        rg -q 'array.set \$do_bytes' "$wat_file"
        rg -q 'array.new_default \$do_u32' "$wat_file"
        rg -q 'array.set \$do_u32' "$wat_file"
        rg -q 'struct.new \$reading' "$wat_file"
        test "$(rg -c 'call \$cabi_realloc' "$wat_file")" -eq 2
        call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
        free_line=$(rg -n 'call \$cabi_realloc' "$wat_file" | tail -1 | cut -d: -f1)
        if [[ -z "$call_line" || -z "$free_line" || "$call_line" -ge "$free_line" ]]; then
            printf 'ordinary mixed text/u32-list record lift canonical call/cleanup order is invalid: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    if [[ "$name" == ordinary-host-record-mixed-text-byte-list-lift-call ]]; then
        rg -q '\(import "demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0" "read"' "$wat_file"
        rg -q '\(type \$canonical_lift \(func \(param i32\)\)\)' "$wat_file"
        if rg -q '^\s*\(import.*\(ref' "$wat_file"; then
            printf 'ordinary mixed text/byte-list record lift canonical import unexpectedly carries a GC reference: %s\n' "$wat_file" >&2
            exit 1
        fi
        if rg -q '__arc_' "$wat_file"; then
            printf 'ordinary mixed text/byte-list record lift route still contains ARC symbols: %s\n' "$wat_file" >&2
            exit 1
        fi
        rg -q 'array.new_default \$do_bytes' "$wat_file"
        rg -q 'array.set \$do_bytes' "$wat_file"
        rg -q 'i32.load8_u' "$wat_file"
        rg -q 'struct.new \$reading' "$wat_file"
        test "$(rg -c 'call \$cabi_realloc' "$wat_file")" -eq 2
        call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
        free_line=$(rg -n 'call \$cabi_realloc' "$wat_file" | tail -1 | cut -d: -f1)
        if [[ -z "$call_line" || -z "$free_line" || "$call_line" -ge "$free_line" ]]; then
            printf 'ordinary mixed text/byte-list record lift canonical call/cleanup order is invalid: %s\n' "$wat_file" >&2
            exit 1
        fi
    fi
    "$TOOLCHAIN_BIN" parse-core "$wat_file" -o "$wasm_file" >/dev/null
    if [[ ! -s "$wasm_file" ]]; then
        printf 'wasm-tools parse produced no Wasm: %s\n' "$fixture" >&2
        exit 1
    fi

    pass_count=$((pass_count + 1))
    printf 'PASS %s\n' "$name"
done

printf 'GC default build gate passed: %d fixtures\n' "$pass_count"
