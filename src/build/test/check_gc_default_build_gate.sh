#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/examples/gc-p3-runtime"
DO_BIN="${DO_BIN:-$ROOT_DIR/bin/do}"
WASM_TOOLS_BIN="${WASM_TOOLS_BIN:-$(command -v wasm-tools || true)}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/do-gc-default-build.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT

if [[ ! -x "$DO_BIN" ]]; then
    printf 'missing do compiler executable: %s\n' "$DO_BIN" >&2
    exit 1
fi
if [[ -z "$WASM_TOOLS_BIN" || ! -x "$WASM_TOOLS_BIN" ]]; then
    printf 'missing wasm-tools executable: %s\n' "${WASM_TOOLS_BIN:-<unset>}" >&2
    exit 1
fi
wasm_tools_version="$("$WASM_TOOLS_BIN" --version 2>/dev/null || true)"
if [[ "$wasm_tools_version" != 'wasm-tools 1.255.0'* ]]; then
    printf 'unsupported wasm-tools version: %s (expected 1.255.0)\n' "${wasm_tools_version:-<unknown>}" >&2
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
parameterized-list-set-renamed.do
parameterized-list-set.do
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
    assert_no_arc_marker "$wat_file"
    assert_gc_marker "$wat_file"
    "$WASM_TOOLS_BIN" parse "$wat_file" -o "$wasm_file" >/dev/null
    if [[ ! -s "$wasm_file" ]]; then
        printf 'wasm-tools parse produced no Wasm: %s\n' "$fixture" >&2
        exit 1
    fi

    pass_count=$((pass_count + 1))
    printf 'PASS %s\n' "$name"
done

printf 'GC default build gate passed: %d fixtures\n' "$pass_count"
