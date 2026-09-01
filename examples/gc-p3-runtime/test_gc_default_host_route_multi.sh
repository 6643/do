#!/usr/bin/env bash
set -euo pipefail
# Verification Status: verified

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
do_bin=$repo_root/bin/do
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-c15d-call.do
wit=$repo_root/examples/gc-p3-runtime/marshal-record-managed-lower-multi-assembly.wit
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-default-managed-lower-multi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler executable: %s\n' "$do_bin" >&2
  exit 1
fi
if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi
if [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing Rust runner linker\n' >&2
  exit 1
fi

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

# Ordinary compilation must select C15-D without the private selector flag.
"$do_bin" build "$input_do" -o "$tmp_dir/core.wat"
rg -q '^  ;; gc-sync ' "$tmp_dir/core.wat"
if rg -q '__arc_' "$tmp_dir/core.wat"; then
  printf 'default C15-D route still contains ARC runtime symbols\n' >&2
  exit 1
fi
rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32 i32 i32\)\)\)' "$tmp_dir/core.wat"
rg -q '\(import "demo:marshal-record-managed-lower-multi/api@1.0.0" "write"' "$tmp_dir/core.wat"
if rg -q '^\s*\(import "demo:marshal-record-managed-lower-multi/api@1.0.0" "write".*\(ref' "$tmp_dir/core.wat"; then
  printf 'GC reference crossed the default C15-D canonical import\n' >&2
  exit 1
fi
test "$(rg -c 'array.get_s \$do_bytes' "$tmp_dir/core.wat")" -eq 2
test "$(rg -c 'call \$cabi_realloc' "$tmp_dir/core.wat")" -eq 4
call_line=$(rg -n 'call \$__gc_canonical_call' "$tmp_dir/core.wat" | tail -1 | cut -d: -f1)
free_line=$(rg -n 'call \$cabi_realloc' "$tmp_dir/core.wat" | tail -1 | cut -d: -f1)
if [ -z "$call_line" ] || [ -z "$free_line" ] || [ "$call_line" -ge "$free_line" ]; then
  printf 'default C15-D call/free order is invalid\n' >&2
  exit 1
fi

awk '{ print } /  \(export "_start" \(func \$_start\)\)/ { print "  (func (export \"run\") (result i32) call $_start i32.const 34)" }' \
  "$tmp_dir/core.wat" > "$tmp_dir/component.core.wat"
"$toolchain_bin" parse-core "$tmp_dir/component.core.wat" -o "$tmp_dir/core.wasm"
"$toolchain_bin" embed-component "$wit" "$tmp_dir/core.wasm" probe --features none -o "$tmp_dir/embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/component.wasm" --features none

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-record-managed-lower-multi-host-runner -- "$tmp_dir/component.wasm"
)
grep -Fq 'GC multi-managed-field record lower host adapter passed code=7 label=hello note=world write-calls=1 allocations=2 frees=2' <<<"$output"
printf '%s\n' "$output"
printf 'default C15-D multi-managed-field record lower Component host execution passed\n'

lift_input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-c16d-call.do
lift_wit=$repo_root/examples/gc-p3-runtime/marshal-record-managed-lift-multi-assembly.wit

# The same ordinary build path must also select C16-D for managed-field lift.
"$do_bin" build "$lift_input_do" -o "$tmp_dir/lift.core.wat"
rg -q '^  ;; gc-sync ' "$tmp_dir/lift.core.wat"
if rg -q '__arc_' "$tmp_dir/lift.core.wat"; then
  printf 'default C16-D route still contains ARC runtime symbols\n' >&2
  exit 1
fi
rg -q '\(type \$canonical_lift \(func \(param i32\)\)\)' "$tmp_dir/lift.core.wat"
rg -q '\(import "demo:marshal-record-managed-lift-multi/api@1.0.0" "read"' "$tmp_dir/lift.core.wat"
if rg -q '^\s*\(import "demo:marshal-record-managed-lift-multi/api@1.0.0" "read".*\(ref' "$tmp_dir/lift.core.wat"; then
  printf 'GC reference crossed the default C16-D canonical import\n' >&2
  exit 1
fi
test "$(rg -c 'array.set \$do_bytes' "$tmp_dir/lift.core.wat")" -eq 2
test "$(rg -c 'struct.new \$do_text' "$tmp_dir/lift.core.wat")" -eq 2
rg -q 'struct.new \$reading' "$tmp_dir/lift.core.wat"

awk '{ print } /  \(export "_start" \(func \$_start\)\)/ { print "  (func (export \"run\") (result i32) call $_start i32.const 17)" }' \
  "$tmp_dir/lift.core.wat" > "$tmp_dir/lift.component.core.wat"
"$toolchain_bin" parse-core "$tmp_dir/lift.component.core.wat" -o "$tmp_dir/lift.core.wasm"
"$toolchain_bin" embed-component "$lift_wit" "$tmp_dir/lift.core.wasm" probe --features none -o "$tmp_dir/lift.embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/lift.embedded.wasm" -o "$tmp_dir/lift.component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/lift.component.wasm" --features none

lift_output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-record-managed-lift-multi-host-runner -- "$tmp_dir/lift.component.wasm"
)
grep -Fq 'GC managed multi-field record lift host adapter passed value=17' <<<"$lift_output"
printf '%s\n' "$lift_output"
printf 'default C16-D multi-managed-field record lift Component host execution passed\n'
