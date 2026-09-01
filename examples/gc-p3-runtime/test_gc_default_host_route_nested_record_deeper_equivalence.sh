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
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-default-nested-deeper-equivalence.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$toolchain_bin" ] || [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing do-toolchain or Rust runner linker\n' >&2
  exit 1
fi

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

build_equivalence() {
  local label=$1
  local input_do=$2
  local wit=$3
  local arc_core_wat=$4
  local runner_bin=$5
  local expected=$6
  local core_wat="$tmp_dir/$label.core.wat"
  local component_core_wat="$tmp_dir/$label.component.core.wat"
  local core_wasm="$tmp_dir/$label.core.wasm"
  local arc_wasm="$tmp_dir/$label.arc.wasm"
  local embedded="$tmp_dir/$label.embedded.wasm"
  local arc_embedded="$tmp_dir/$label.arc.embedded.wasm"
  local component="$tmp_dir/$label.component.wasm"
  local arc_component="$tmp_dir/$label.arc.component.wasm"

  "$do_bin" build "$input_do" -o "$core_wat"
  awk '{ print } /  \(export "_start" \(func \$_start\)\)/ { print "  (func (export \"run\") (result i32) call $_start i32.const 42)" }' \
    "$core_wat" > "$component_core_wat"
  "$toolchain_bin" parse-core "$component_core_wat" -o "$core_wasm"
  "$toolchain_bin" parse-core "$arc_core_wat" -o "$arc_wasm"
  rg -q '^  ;; gc-sync ' "$core_wat"
  if rg -q '__arc_' "$core_wat"; then
    printf '%s default C14 equivalence route still contains ARC runtime symbols\n' "$label" >&2
    return 1
  fi
  if rg -q '^\s*\(import.*\(ref' "$core_wat" "$arc_core_wat"; then
    printf '%s GC reference crossed canonical C14 import\n' "$label" >&2
    return 1
  fi
  "$toolchain_bin" embed-component "$wit" "$core_wasm" probe --features none -o "$embedded"
  "$toolchain_bin" embed-component "$wit" "$arc_wasm" probe --features none -o "$arc_embedded"
  "$toolchain_bin" new-component "$embedded" -o "$component"
  "$toolchain_bin" new-component "$arc_embedded" -o "$arc_component"
  "$toolchain_bin" validate-component "$component" --features none
  "$toolchain_bin" validate-component "$arc_component" --features none

  local output
  output=$(
    CC="$cc_bin" CXX="$cxx_bin" \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
    "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
      --bin "$runner_bin" -- "$component" "$arc_component"
  )
  grep -Fq "$expected" <<<"$output"
  printf '%s\n' "$output"
}

build_equivalence \
  lift \
  "$repo_root/examples/gc-p3-runtime/ordinary-host-c14-lift-call.do" \
  "$repo_root/examples/gc-p3-runtime/marshal-record-nested-lift-deeper-assembly.wit" \
  "$repo_root/examples/gc-p3-runtime/marshal-record-nested-lift-deeper-arc.core.wat" \
  do-p3-gc-marshal-record-nested-lift-deeper-equivalence-runner \
  'GC/ARC manifest four-level nested scalar record lift equivalence passed sums=42/42'
build_equivalence \
  lower \
  "$repo_root/examples/gc-p3-runtime/ordinary-host-c14-lower-call.do" \
  "$repo_root/examples/gc-p3-runtime/marshal-record-nested-lower-deeper-assembly.wit" \
  "$repo_root/examples/gc-p3-runtime/marshal-record-nested-lower-deeper-arc.core.wat" \
  do-p3-gc-marshal-record-nested-lower-deeper-equivalence-runner \
  'GC/ARC four-level nested scalar record lower equivalence passed results=42/42 write-calls=1/1'

printf 'default C14 four-level nested scalar record equivalence gates passed\n'
