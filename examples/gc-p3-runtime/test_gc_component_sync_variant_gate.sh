#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
probe=$repo_root/src/component_variant_gate_probe_main.zig
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-component-variant.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

run_positive() {
  local wit=$1
  local member=$2
  local direction=$3
  local mode=$4
  local stem=$5
  local wat="$tmp_dir/$stem.wat"
  local core="$tmp_dir/$stem.core.wasm"
  local embedded="$tmp_dir/$stem.embedded.wasm"
  local component="$tmp_dir/$stem.component.wasm"

  zig run "$probe" -- "$wit" "$member" "$direction" "$mode" "$wat"
  "$toolchain_bin" parse-core "$wat" -o "$core"
  if rg -q '^\s*\(import.*\(ref' "$wat"; then
    printf 'canonical variant import contains a GC reference: %s\n' "$stem" >&2
    exit 1
  fi
  "$toolchain_bin" embed-component "$wit" "$core" probe --features none -o "$embedded"
  "$toolchain_bin" new-component "$embedded" -o "$component"
  "$toolchain_bin" validate-component "$component" --features none
  cargo run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-variant -- "$component" "$mode"
}

run_positive "$repo_root/examples/gc-p3-runtime/variant-option.wit" send lower option option
run_positive "$repo_root/examples/gc-p3-runtime/variant-result-lower.wit" send lower result-text-lower result-text-lower
run_positive "$repo_root/examples/gc-p3-runtime/variant-result-lower.wit" send lower result-scalar-lower result-scalar-lower
run_positive "$repo_root/examples/gc-p3-runtime/variant-result-lift.wit" read lift result-text-lift result-text-lift
run_positive "$repo_root/examples/gc-p3-runtime/variant-result-lift.wit" read lift result-scalar-lift result-scalar-lift
run_positive "$repo_root/examples/gc-p3-runtime/variant-no-payload.wit" send lower variant-none variant-none

if zig run "$probe" -- "$repo_root/examples/gc-p3-runtime/variant-drift.wit" read lift drift "$tmp_dir/drift.wat"; then
  printf 'variant descriptor drift unexpectedly produced WAT\n' >&2
  exit 1
fi
test ! -e "$tmp_dir/drift.wat"

if zig run "$probe" -- "$repo_root/examples/gc-p3-runtime/variant-unsupported.wit" read lift unsupported "$tmp_dir/unsupported.wat"; then
  printf 'unsupported variant payload unexpectedly produced WAT\n' >&2
  exit 1
fi
test ! -e "$tmp_dir/unsupported.wat"

printf 'synchronous option/result/variant Component gate passed\n'
