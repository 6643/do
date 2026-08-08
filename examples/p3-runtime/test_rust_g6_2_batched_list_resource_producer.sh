#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-batched-list-resource-producer-rust.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

source="$repo_root/examples/p3-runtime/g6-2-batched-list-resource-producer.do"
wat="$tmp_dir/generated.wat"
wit="$tmp_dir/generated.wit"
core_wasm="$tmp_dir/generated.core.wasm"
embedded="$tmp_dir/generated.embedded.wasm"
component="$tmp_dir/generated.component.wasm"

test -x "$do_bin"
test -f "$source"
test -f "$runner_dir/Cargo.toml"
test -f "$runner_dir/src/bin/g6_2_batched_list_resource_producer.rs"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$wat"
test -s "$wat"
test -s "$wit"

grep -Fq 'package do:g6-2-batched-list-producer@0.1.0;' "$wit"
grep -Fq 'world batched-list-producer' "$wit"
grep -Fq 'export produce: async func(mode: u32)' "$wit"
grep -Fq '[producer-batched-plan-layout] pointer=64 length=68 stride=4 ticket-offset=0 capacity=1 batches=2 lengths=2,1' "$wat"

wasm-tools parse "$wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world batched-list-producer \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-g6-2-batched-list-resource-producer
for mode in ready pending sink-error-first sink-error-second cancel-before-first cancel-after-first; do
  output=$(cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$bin" -- "$component" "$mode")
  printf '%s\n' "$output"
  grep -Fq "mode=$mode" <<<"$output"
  grep -Fq 'resource-created=3' <<<"$output"
  grep -Fq 'resource-drops=3' <<<"$output"
  grep -Fq 'list-allocations=2' <<<"$output"
  grep -Fq 'list-releases=2' <<<"$output"
  grep -Fq 'stream-drops=1' <<<"$output"
  grep -Fq 'future-drops=1' <<<"$output"
  grep -Fq 'cancel-calls=' <<<"$output"
  grep -Fq 'table-empty=true' <<<"$output"
done

printf 'G6.2 batched list resource producer compiler-generated Rust/Wasmtime gate passed\n'
