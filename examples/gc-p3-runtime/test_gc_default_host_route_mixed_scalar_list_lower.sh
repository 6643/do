#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
do_bin=${DO_BIN:-$repo_root/bin/do}
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-mixed-scalar-list-lower-call.do
wat_file=$(mktemp "${TMPDIR:-/tmp}/do-g5c-default-mixed-scalar-list-lower.XXXXXX.wat")
trap 'rm -f "$wat_file"' EXIT

if [[ ! -x "$do_bin" ]]; then
    printf '[FAIL] missing do compiler executable: %s\n' "$do_bin" >&2
    exit 1
fi
if [[ ! -x "$toolchain_bin" ]]; then
    printf '[FAIL] missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
    exit 1
fi

# This invocation intentionally has no --gc-wit-marshal selector: the ordinary
# host declaration must select the manifest-backed route by itself.
"$do_bin" build "$input_do" -o "$wat_file" >/dev/null

rg -q '^  ;; gc-sync ' "$wat_file"
if rg -q '__arc_' "$wat_file"; then
    printf '[FAIL] mixed scalar-list lower default route still contains ARC runtime symbols\n' >&2
    exit 1
fi
rg -q '\(import "demo:marshal-record-mixed-scalar-list-lower/api@1.0.0" "write"' "$wat_file"
rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32 i32 i32\)\)\)' "$wat_file"
if rg -q '^\s*\(import "demo:marshal-record-mixed-scalar-list-lower/api@1.0.0" "write".*\(ref' "$wat_file"; then
    printf '[FAIL] mixed scalar-list lower canonical import carries a GC reference\n' >&2
    exit 1
fi
rg -q 'array.get_s \$do_bytes' "$wat_file"
test "$(rg -c 'array.get_s \$do_bytes' "$wat_file")" -eq 2
test "$(rg -c 'i32.store8' "$wat_file")" -eq 2
rg -q 'block \$__mixed_cleanup' "$wat_file"

mapfile -t realloc_lines < <(rg -n 'call \$cabi_realloc' "$wat_file" | cut -d: -f1)
if [[ "${#realloc_lines[@]}" -ne 4 ]]; then
    printf '[FAIL] expected two allocation and two free call sites, got %s\n' "${#realloc_lines[@]}" >&2
    exit 1
fi
call_line=$(rg -n 'call \$__gc_canonical_call' "$wat_file" | tail -1 | cut -d: -f1)
first_free_line=${realloc_lines[2]}
second_free_line=${realloc_lines[3]}
if [[ -z "$call_line" || "$call_line" -ge "$first_free_line" || "$first_free_line" -ge "$second_free_line" ]]; then
    printf '[FAIL] mixed scalar-list lower canonical call/free order is invalid\n' >&2
    exit 1
fi

"$toolchain_bin" validate-core "$wat_file" >/dev/null
printf 'GREEN: mixed scalar-list record lower uses automatic manifest-backed GC/WIT route\n'
