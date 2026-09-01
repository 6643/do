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
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-default-nested-deeper-host.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$toolchain_bin" ] || [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing do-toolchain or Rust runner linker\n' >&2
  exit 1
fi

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

build_and_run() {
  local label=$1
  local input_do=$2
  local wit=$3
  local runner_bin=$4
  local expected=$5
  local core_wat="$tmp_dir/$label.core.wat"
  local component_core_wat="$tmp_dir/$label.component.core.wat"
  local core_wasm="$tmp_dir/$label.core.wasm"
  local embedded="$tmp_dir/$label.embedded.wasm"
  local component="$tmp_dir/$label.component.wasm"

  "$do_bin" build "$input_do" -o "$core_wat"
  rg -q '^  ;; gc-sync ' "$core_wat"
  if rg -q '__arc_' "$core_wat"; then
    printf '%s default C14 route still contains ARC runtime symbols\n' "$label" >&2
    return 1
  fi
  if [ "$label" = lift ]; then
    rg -q '\(type \$canonical_lift \(func \(param i32\)\)\)' "$core_wat"
    rg -q '\(import "demo:marshal-record-nested-lift-deeper/api@1.0.0" "read"' "$core_wat"
    rg -q '\(func \$read \(result i32 i64 i64 i64 i64\)' "$core_wat"
    rg -q 'i32.load' "$core_wat"
    rg -q 'i64.load' "$core_wat"
  else
    rg -q '\(type \$canonical_lower \(func \(param i32 i64 i64 i64 i64\)\)\)' "$core_wat"
    rg -q '\(import "demo:marshal-record-nested-lower-deeper/api@1.0.0" "write"' "$core_wat"
    rg -q '\(func \$write \(param \$__gc_arg_0 i32\) \(param \$__gc_arg_1 i64\) \(param \$__gc_arg_2 i64\) \(param \$__gc_arg_3 i64\) \(param \$__gc_arg_4 i64\)' "$core_wat"
    rg -q 'local.get \$value\.detail\.header\.leaf\.code' "$core_wat"
    rg -q 'local.get \$value\.detail\.header\.leaf\.count' "$core_wat"
  fi
  if rg -q 'struct\.(new|get)' "$core_wat"; then
    printf '%s inline C14 record unexpectedly crossed a GC struct operation\n' "$label" >&2
    return 1
  fi
  if rg -q '^\s*\(import.*\(ref' "$core_wat"; then
    printf '%s GC reference crossed the canonical C14 import\n' "$label" >&2
    return 1
  fi

  awk '{ print } /  \(export "_start" \(func \$_start\)\)/ { print "  (func (export \"run\") (result i32) call $_start i32.const 42)" }' \
    "$core_wat" > "$component_core_wat"
  "$toolchain_bin" parse-core "$component_core_wat" -o "$core_wasm"
  "$toolchain_bin" embed-component "$wit" "$core_wasm" probe --features none -o "$embedded"
  "$toolchain_bin" new-component "$embedded" -o "$component"
  "$toolchain_bin" validate-component "$component" --features none

  local output
  output=$(
    CC="$cc_bin" CXX="$cxx_bin" \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
    "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
      --bin "$runner_bin" -- "$component"
  )
  grep -Fq "$expected" <<<"$output"
  printf '%s\n' "$output"
}

build_and_run \
  lift \
  "$repo_root/examples/gc-p3-runtime/ordinary-host-c14-lift-call.do" \
  "$repo_root/examples/gc-p3-runtime/marshal-record-nested-lift-deeper-assembly.wit" \
  do-p3-gc-marshal-record-nested-lift-deeper-host-runner \
  'GC four-level nested scalar record lift host adapter passed sum=42'
build_and_run \
  lower \
  "$repo_root/examples/gc-p3-runtime/ordinary-host-c14-lower-call.do" \
  "$repo_root/examples/gc-p3-runtime/marshal-record-nested-lower-deeper-assembly.wit" \
  do-p3-gc-marshal-record-nested-lower-deeper-host-runner \
  'GC four-level nested scalar record lower host adapter passed result=42 write-calls=1'

printf 'default C14 four-level nested scalar record host gates passed\n'
