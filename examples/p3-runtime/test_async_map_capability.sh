#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
wit="$repo_root/examples/p3-runtime/wit/async-map-capability.wit"
wat="$repo_root/examples/p3-runtime/async-map-capability-canonical.wat"
runner="$runner_dir/src/bin/async_map_capability.rs"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/async-map-capability.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

for path in "$wit" "$wat" "$runner"; do
  test -f "$path" || {
    printf 'missing async map probe artifact: %s\n' "$path" >&2
    exit 1
  }
done

  grep -Fq 'package demo:map-async-probe@0.1.0;' "$wit"
grep -Fq 'submit: async func(values: map<u32, u32>) -> u32;' "$wit"
grep -Fq 'export run: async func() -> u32;' "$wit"
grep -Fq '(type $async-submit (func (param i32 i32 i32) (result i32)))' "$wat"

for marker in \
  '[async-map-input-copy]' \
  '[async-map-input-overwrite]' \
  '[async-map-result-area]' \
  '[async-map-pending]' \
  '[async-map-complete]' \
  '[async-map-cancel]' \
  '[async-map-drop]' \
  '[async-map-frame-free]'; do
  grep -Fq ";; $marker" "$wat"
done

if grep -Fq '__arc_' "$wat"; then
  printf 'async map probe contains obsolete ARC marker\n' >&2
  exit 1
fi

core_wasm="$tmp_dir/async-map.core.wasm"
embedded="$tmp_dir/async-map.embedded.wasm"
component="$tmp_dir/async-map.component.wasm"
"$toolchain_bin" parse-core "$wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" probe \
  --features component-async-map -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async-map

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-async-map-capability-host-runner
cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" --bin "$bin"

for mode in ready pending cancel drop; do
  output=$(cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$bin" -- "$component" "$mode")
  printf '%s\n' "$output"
  grep -Fq "mode=$mode" <<<"$output"
  grep -Fq 'entries=[7->70, 9->90]' <<<"$output"
  grep -Fq 'input-mismatches=0' <<<"$output"
  if [[ "$mode" == ready || "$mode" == pending ]]; then
    grep -Fq 'result=42' <<<"$output"
  else
    grep -Fq 'result=0' <<<"$output"
  fi
  grep -Fq 'frame-frees=1' <<<"$output"
  grep -Fq 'table-empty=true' <<<"$output"
done

printf 'async map capability probe passed modes=4 input-copy=true result-area=true exactly-once=true\n'
