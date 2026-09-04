#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
do_bin=${DO_BIN:-$repo_root/bin/do}
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-map-u32-u32.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$toolchain_bin" ] || [ ! -x "$do_bin" ]; then
  printf 'missing do compiler or toolchain adapter\n' >&2
  exit 1
fi
if [ ! -f "$runner_manifest" ] || [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing Rust runner manifest or linker\n' >&2
  exit 1
fi

lower_do=$repo_root/examples/gc-p3-runtime/map-u32-u32-lower.do
lower_descriptor=demo:marshal-map-u32-u32/api.write@1.0.0/lower
lower_wit=$repo_root/examples/gc-p3-runtime/marshal-map-u32-u32-lower-assembly.wit
lift_do=$repo_root/examples/gc-p3-runtime/map-u32-u32-lift.do
lift_descriptor=demo:marshal-map-u32-u32/api.read@1.0.0/lift
lift_wit=$repo_root/examples/gc-p3-runtime/marshal-map-u32-u32-lift-assembly.wit

for path in "$lower_do" "$lower_wit" "$lift_do" "$lift_wit"; do
  if [ ! -f "$path" ]; then
    printf 'missing map Component fixture: %s\n' "$path" >&2
    exit 1
  fi
done

run_direction() {
  local direction=$1
  local input_do=$2
  local descriptor=$3
  local wit=$4
  local canonical_type=$5
  local wit_signature=$6
  local core="$tmp_dir/${direction}.core.wat"
  local wasm="$tmp_dir/${direction}.core.wasm"
  local embedded="$tmp_dir/${direction}.embedded.wasm"
  local component="$tmp_dir/${direction}.component.wasm"

  DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$input_do" --gc-wit-marshal "$descriptor" -o "$core"
  grep -Fq "$canonical_type" "$core"
  if grep -Fq '__arc_' "$core"; then
    printf '%s map route still contains ARC symbols\n' "$direction" >&2
    exit 1
  fi
  if grep -E '^[[:space:]]*\(import .*(\(param|\(result).*\(ref' "$core"; then
    printf '%s map reference crossed the canonical Component ABI\n' "$direction" >&2
    exit 1
  fi

  "$toolchain_bin" parse-core "$core" -o "$wasm"
  "$toolchain_bin" embed-component "$wit" "$wasm" probe --features component-map -o "$embedded"
  "$toolchain_bin" new-component "$embedded" -o "$component"
  "$toolchain_bin" validate-component "$component" --features component-map
  "$toolchain_bin" component-wit "$component" >"$tmp_dir/${direction}.component.wit"
  grep -Fq "$wit_signature" "$tmp_dir/${direction}.component.wit"

  local output
  output=$(
    CC="$cc_bin" CXX="$cxx_bin" \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
    "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
      --bin do-p3-gc-marshal-map-u32-u32 -- "$component" "$direction"
  )
  printf '%s\n' "$output"
  if [ "$direction" = lower ]; then
    grep -Fq 'GC map<u32,u32> lower host adapter passed entries=[7->70, 9->90] result=42 stats=17 write-calls=1 allocations=1 frees=1' <<<"$output"
  else
    grep -Fq 'GC map<u32,u32> lift host adapter passed entries=[7->70, 9->90] result=176 stats=17 read-calls=1 allocations=1 frees=1' <<<"$output"
  fi
}

run_direction lower "$lower_do" "$lower_descriptor" "$lower_wit" \
  '(type $canonical_lower (func (param i32 i32)))' \
  'write: func(value: map<u32, u32>)'
run_direction lift "$lift_do" "$lift_descriptor" "$lift_wit" \
  '(type $canonical_lift (func (param i32)))' \
  'read: func() -> map<u32, u32>'

printf 'manifest-backed map<u32,u32> lower/lift Component host execution passed\n'
