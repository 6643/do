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
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
do_bin=${DO_BIN:-$repo_root/bin/do}
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-mixed-scalar-list-lower-call.do
wit=$repo_root/examples/gc-p3-runtime/marshal-record-mixed-scalar-list-lower-assembly.wit
arc_core_wat=$repo_root/examples/gc-p3-runtime/marshal-record-mixed-scalar-list-lower-arc.core.wat
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-default-mixed-scalar-list-lower-equivalence.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [[ ! -x "$do_bin" || ! -x "$toolchain_bin" || ! -x "$cc_bin" || ! -x "$cxx_bin" || ! -x "$linker_bin" ]]; then
  printf 'missing compiler, do-toolchain, or Rust runner linker\n' >&2
  exit 1
fi

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

# The GC side is the ordinary compiler route; the ARC side is the fixed
# linear-memory oracle for this exact descriptor.
"$do_bin" build "$input_do" -o "$tmp_dir/gc.core.wat"
awk '{ print } /  \(export "_start" \(func \$_start\)\)/ { print "  (func (export \"run\") (result i32) call $_start i32.const 34)" }' \
  "$tmp_dir/gc.core.wat" > "$tmp_dir/gc.component.core.wat"
"$toolchain_bin" parse-core "$tmp_dir/gc.component.core.wat" -o "$tmp_dir/gc.core.wasm"
"$toolchain_bin" parse-core "$arc_core_wat" -o "$tmp_dir/arc.core.wasm"

rg -q '^  ;; gc-sync ' "$tmp_dir/gc.core.wat"
if rg -q '__arc_' "$tmp_dir/gc.core.wat"; then
  printf 'default mixed scalar-list lower equivalence route still contains ARC runtime symbols\n' >&2
  exit 1
fi
rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32 i32 i32\)\)\)' "$tmp_dir/gc.core.wat"
if rg -q '^\s*\(import.*\(ref' "$tmp_dir/gc.core.wat"; then
  printf 'GC reference crossed the mixed scalar-list lower canonical import\n' >&2
  exit 1
fi
if rg -q '^\s*\(import.*\(ref' "$arc_core_wat"; then
  printf 'ARC oracle canonical import unexpectedly carries a GC reference\n' >&2
  exit 1
fi
test "$(rg -c 'array.get_s \$do_bytes' "$tmp_dir/gc.core.wat")" -eq 2
test "$(rg -c 'i32.store8' "$tmp_dir/gc.core.wat")" -eq 2
mapfile -t realloc_lines < <(rg -n 'call \$cabi_realloc' "$tmp_dir/gc.core.wat" | cut -d: -f1)
test "${#realloc_lines[@]}" -eq 4
call_line=$(rg -n 'call \$__gc_canonical_call' "$tmp_dir/gc.core.wat" | tail -1 | cut -d: -f1)
if [[ -z "$call_line" || "$call_line" -ge "${realloc_lines[2]}" || "${realloc_lines[2]}" -ge "${realloc_lines[3]}" ]]; then
  printf 'GC mixed scalar-list lower canonical call/free order is invalid\n' >&2
  exit 1
fi

"$toolchain_bin" embed-component "$wit" "$tmp_dir/gc.core.wasm" probe --features none -o "$tmp_dir/gc.embedded.wasm"
"$toolchain_bin" embed-component "$wit" "$tmp_dir/arc.core.wasm" probe --features none -o "$tmp_dir/arc.embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/gc.embedded.wasm" -o "$tmp_dir/gc.component.wasm"
"$toolchain_bin" new-component "$tmp_dir/arc.embedded.wasm" -o "$tmp_dir/arc.component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/gc.component.wasm" --features none
"$toolchain_bin" validate-component "$tmp_dir/arc.component.wasm" --features none

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-record-mixed-scalar-list-lower-equivalence-runner -- \
    "$tmp_dir/gc.component.wasm" "$tmp_dir/arc.component.wasm"
)
grep -Fq 'GC/ARC mixed scalar-list record lower equivalence passed code=7 label=hello payload=[10, 20, 5] allocations=2/2 frees=2/2 write-calls=1/1' <<< "$output"
printf '%s\n' "$output"
printf 'default mixed scalar-list record lower compiler/ARC equivalence passed\n'
