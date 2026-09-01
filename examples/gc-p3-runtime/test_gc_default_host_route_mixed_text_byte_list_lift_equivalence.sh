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
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-record-mixed-text-byte-list-lift-call.do
wit=$repo_root/examples/gc-p3-runtime/marshal-record-mixed-text-byte-list-lift-assembly.wit
arc_core_wat=$repo_root/examples/gc-p3-runtime/marshal-record-mixed-text-byte-list-lift-arc.core.wat
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-default-mixed-text-byte-list-lift-equivalence.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$toolchain_bin" ] || [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing do-toolchain or Rust runner linker\n' >&2
  exit 1
fi

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$input_do" -o "$tmp_dir/gc.core.wat"
rg -q '^  ;; gc-sync ' "$tmp_dir/gc.core.wat"
if rg -q '__arc_' "$tmp_dir/gc.core.wat"; then
  printf 'default mixed text/byte-list lift equivalence GC route still contains ARC symbols\n' >&2
  exit 1
fi
rg -q '\(type \$canonical_lift \(func \(param i32\)\)\)' "$tmp_dir/gc.core.wat"
rg -q 'array.set \$do_bytes' "$tmp_dir/gc.core.wat"
rg -q 'i32.load8_u' "$tmp_dir/gc.core.wat"
if rg -q '^\s*\(import.*\(ref' "$tmp_dir/gc.core.wat" "$arc_core_wat"; then
  printf 'GC reference crossed canonical mixed text/byte-list lift import\n' >&2
  exit 1
fi

awk '{ print } /  \(export "_start" \(func \$_start\)\)/ { print "  (func (export \"run\") (result i32) call $_start i32.const 47)"; print "  (func (export \"stats\") (result i32) i32.const 34)" }' \
  "$tmp_dir/gc.core.wat" > "$tmp_dir/gc.component.core.wat"
"$toolchain_bin" parse-core "$tmp_dir/gc.component.core.wat" -o "$tmp_dir/gc.core.wasm"
"$toolchain_bin" parse-core "$arc_core_wat" -o "$tmp_dir/arc.core.wasm"
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
    --bin do-p3-gc-marshal-record-mixed-text-byte-list-lift-equivalence-runner -- \
    "$tmp_dir/gc.component.wasm" "$tmp_dir/arc.component.wasm"
)
grep -Fq 'GC/ARC mixed text/byte-list record lift equivalence passed result=47/47 stats=34/34 read-calls=1/1' <<<"$output"
printf '%s\n' "$output"
printf 'default mixed text/byte-list lift ARC/GC equivalence passed\n'
