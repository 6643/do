#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-scalar-list-producer-rust.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

source="$repo_root/examples/p3-runtime/g6-2-scalar-list-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-scalar-list-producer.wit"
wat="$tmp_dir/generated.wat"
wit="$tmp_dir/generated.wit"
core_wasm="$tmp_dir/generated.core.wasm"
embedded="$tmp_dir/generated.embedded.wasm"
component="$tmp_dir/generated.component.wasm"

test -x "$do_bin"
test -x "$toolchain_bin"
test -f "$source"
test -f "$probe_wit"
test -f "$runner_dir/Cargo.toml"
test -f "$runner_dir/src/bin/g6_2_scalar_list_producer.rs"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$wat"
cmp "$wit" "$probe_wit"
grep -Fq 'package do:g6-2-scalar-list-producer@0.1.0;' "$wit"
grep -Fq 'world scalar-list-producer' "$wit"
grep -Fq 'export produce: async func(count: u32)' "$wit"
grep -Fq '[producer-list-release-exactly-once]' "$wat"
grep -Fq '[producer-cancel-before-transfer]' "$wat"
if grep -Fq '[resource-drop]' "$wat"; then
  printf 'scalar-list promotion unexpectedly imports resource-drop\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" scalar-list-producer \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=g6_2_scalar_list_producer
run_mode() {
  local mode="$1"
  local expected_values="$2"
  local expected_releases="$3"
  local expected_host_calls="$4"
  local expected_stream_drops="$5"
  local output
  output=$(cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$bin" -- "$component" "$mode")
  printf '%s\n' "$output"
  grep -Fq "mode=$mode" <<<"$output"
  grep -Fq "values=$expected_values" <<<"$output"
  grep -Fq "host-calls=$expected_host_calls" <<<"$output"
  grep -Fq "stream-drops=$expected_stream_drops" <<<"$output"
  grep -Fq "list-releases=$expected_releases" <<<"$output"
  grep -Fq 'table-empty=true' <<<"$output"
}

run_mode count-0 '[]' 1 1 1
run_mode count-1 '[10]' 1 1 1
run_mode count-2 '[10, 20]' 1 1 1
run_mode count-3 '[10, 20, 30]' 1 1 1
run_mode pending '[10, 20, 30]' 1 1 1
run_mode sink-error '[10, 20, 30]' 1 1 1
run_mode early-drop '[10, 20, 30]' 1 1 1
run_mode cancel-before-transfer '[]' 1 1 0
run_mode cancel-after-transfer '[10, 20, 30]' 1 1 1
run_mode count-4 '[]' 0 0 0

printf 'G6.2 scalar list producer compiler-generated Rust/Wasmtime gate passed\n'
