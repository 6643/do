#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
do_bin=${DO_BIN:-$repo_root/bin/do}
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-mixed-text-u32-list-lower-call.do
wit=$repo_root/examples/gc-p3-runtime/marshal-record-mixed-text-u32-list-lower-assembly.wit
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-default-mixed-text-u32-list-lower-host.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [[ ! -x "$do_bin" || ! -x "$toolchain_bin" || ! -x "$runner_cc" ]]; then
    printf 'missing compiler, do-toolchain, or Rust runner linker\n' >&2
    exit 1
fi

(
    cd "$repo_root/src"
    "$zig_bin" build -Doptimize=Debug
)

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$input_do" -o "$tmp_dir/core.wat"
rg -q '^  ;; gc-sync ' "$tmp_dir/core.wat"
if rg -q '__arc_' "$tmp_dir/core.wat"; then
    printf 'mixed text/u32-list lower route still contains ARC runtime symbols\n' >&2
    exit 1
fi
rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32 i32 i32\)\)\)' "$tmp_dir/core.wat"
rg -q '\(import "demo:marshal-record-mixed-text-u32-list-lower/api@1.0.0" "write"' "$tmp_dir/core.wat"
if rg -q '^\s*\(import .*\(ref' "$tmp_dir/core.wat"; then
    printf 'GC reference crossed the mixed text/u32-list canonical import\n' >&2
    exit 1
fi
rg -q 'array.get \$do_u32' "$tmp_dir/core.wat"
rg -q 'i32.store' "$tmp_dir/core.wat"
rg -q 'local.get \$align' "$tmp_dir/core.wat"
mapfile -t realloc_lines < <(rg -n 'call \$cabi_realloc' "$tmp_dir/core.wat" | cut -d: -f1)
test "${#realloc_lines[@]}" -eq 4
call_line=$(rg -n 'call \$__gc_canonical_call' "$tmp_dir/core.wat" | tail -1 | cut -d: -f1)
if [[ -z "$call_line" || "$call_line" -ge "${realloc_lines[2]}" || "${realloc_lines[2]}" -ge "${realloc_lines[3]}" ]]; then
    printf 'mixed text/u32-list lower canonical call/free order is invalid\n' >&2
    exit 1
fi

awk '{ print } /  \(export "_start" \(func \$_start\)\)/ { print "  (func (export \"run\") (result i32) call $_start i32.const 34)" }' \
    "$tmp_dir/core.wat" > "$tmp_dir/component.core.wat"
"$toolchain_bin" parse-core "$tmp_dir/component.core.wat" -o "$tmp_dir/core.wasm"
"$toolchain_bin" embed-component "$wit" "$tmp_dir/core.wasm" probe --features none -o "$tmp_dir/embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/component.wasm" --features none

output=$(
    CC="$runner_cc" CXX="$runner_cc" \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_cc" \
    "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
        --bin do-p3-gc-marshal-record-mixed-text-u32-list-lower-host-runner -- \
        "$tmp_dir/component.wasm"
)
grep -Fq 'GC mixed text/u32-list record lower host adapter passed code=7 label=hello payload=[10, 20, 5] write-calls=1 allocations=2 frees=2' <<<"$output"
printf '%s\n' "$output"
printf 'mixed text/u32-list lower Component host execution passed\n'
