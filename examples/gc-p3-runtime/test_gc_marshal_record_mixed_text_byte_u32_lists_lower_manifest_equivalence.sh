#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
do_bin=${DO_BIN:-$repo_root/bin/do}
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-record-mixed-text-byte-u32-lists-lower-call.do
wit=$repo_root/examples/gc-p3-runtime/marshal-record-mixed-text-byte-u32-lists-lower-assembly.wit
arc_core_wat=$repo_root/examples/gc-p3-runtime/marshal-record-mixed-text-byte-u32-lists-lower-arc.core.wat
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-mixed-text-byte-u32-lists-lower-equivalence.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

tool_version=$($wasm_tools_bin --version)
case "$tool_version" in
    "wasm-tools 1.255.0 (76e20611d"*) ;;
    *) printf 'unexpected wasm-tools version: %s\n' "$tool_version" >&2; exit 1 ;;
esac
if [[ ! -x "$do_bin" || ! -x "$runner_cc" ]]; then
    printf 'missing compiler or Rust runner linker\n' >&2
    exit 1
fi

(
    cd "$repo_root/src"
    "$zig_bin" build -Doptimize=Debug
)

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$input_do" -o "$tmp_dir/gc.core.wat"
awk '{ print } /  \(export "_start" \(func \$_start\)\)/ { print "  (func (export \"run\") (result i32) call $_start i32.const 51)" }' \
    "$tmp_dir/gc.core.wat" > "$tmp_dir/gc.component.core.wat"
"$wasm_tools_bin" parse "$tmp_dir/gc.component.core.wat" -o "$tmp_dir/gc.core.wasm"
"$wasm_tools_bin" parse "$arc_core_wat" -o "$tmp_dir/arc.core.wasm"

rg -q '^  ;; gc-sync ' "$tmp_dir/gc.core.wat"
if rg -q '__arc_' "$tmp_dir/gc.core.wat" || rg -q '^\s*\(import .*\(ref' "$tmp_dir/gc.core.wat" "$arc_core_wat"; then
    printf 'GC equivalence core contains an ARC marker or GC reference import\n' >&2
    exit 1
fi
rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32 i32 i32 i32 i32\)\)\)' "$tmp_dir/gc.core.wat"
test "$(rg -c 'array.get_s \$do_bytes' "$tmp_dir/gc.core.wat")" -eq 2
test "$(rg -c 'array.get \$do_u32' "$tmp_dir/gc.core.wat")" -eq 1
mapfile -t realloc_lines < <(rg -n 'call \$cabi_realloc' "$tmp_dir/gc.core.wat" | cut -d: -f1)
test "${#realloc_lines[@]}" -eq 6
call_line=$(rg -n 'call \$__gc_canonical_call' "$tmp_dir/gc.core.wat" | tail -1 | cut -d: -f1)
if [[ -z "$call_line" || "$call_line" -ge "${realloc_lines[3]}" ]]; then
    printf 'GC mixed text/byte-u32-list lower canonical call/free order is invalid\n' >&2
    exit 1
fi

"$wasm_tools_bin" component embed "$wit" "$tmp_dir/gc.core.wasm" --world probe -o "$tmp_dir/gc.embedded.wasm"
"$wasm_tools_bin" component embed "$wit" "$tmp_dir/arc.core.wasm" --world probe -o "$tmp_dir/arc.embedded.wasm"
"$wasm_tools_bin" component new "$tmp_dir/gc.embedded.wasm" -o "$tmp_dir/gc.component.wasm"
"$wasm_tools_bin" component new "$tmp_dir/arc.embedded.wasm" -o "$tmp_dir/arc.component.wasm"
"$wasm_tools_bin" validate "$tmp_dir/gc.component.wasm"
"$wasm_tools_bin" validate "$tmp_dir/arc.component.wasm"

output=$(
    CC="$runner_cc" CXX="$runner_cc" \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_cc" \
    "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
        --bin do-p3-gc-marshal-record-mixed-text-byte-u32-lists-lower-equivalence-runner -- \
        "$tmp_dir/gc.component.wasm" "$tmp_dir/arc.component.wasm"
)
grep -Fq 'GC/ARC mixed text/byte-u32-list record lower equivalence passed code=7 label=hello bytes=[10, 20, 5] values=[3, 4] allocations=3/3 frees=3/3 write-calls=1/1' <<<"$output"
printf '%s\n' "$output"
printf 'mixed text/byte-u32-list lower compiler/ARC equivalence passed\n'
