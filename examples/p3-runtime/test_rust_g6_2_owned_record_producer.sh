#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-owned-record-producer-rust.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

source="$repo_root/examples/p3-runtime/g6-2-owned-record-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-producer.wit"
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
test -f "$runner_dir/src/bin/g6_2_owned_record_producer.rs"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$wat"
cmp "$wit" "$probe_wit"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace
grep -Fq '[producer-record-transfer]' "$wat"
grep -Fq '[producer-resource-drop-exactly-once]' "$wat"
if grep -Fq '__arc_' "$wat"; then
  printf 'owned-record producer emitted an ARC symbol\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" owned-record-producer \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-g6-2-owned-record-producer
run_mode() {
  local mode="$1"
  local expected_received="$2"
  local expected_result="$3"
  local expected_created="$4"
  local expected_drops="$5"
  local expected_pending="$6"
  local expected_stream_drops="$7"
  local expected_future_drops="$8"
  local output
  output=$(cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$bin" -- "$component" "$mode")
  printf '%s\n' "$output"
  grep -Fq "mode=$mode" <<<"$output"
  grep -Fq "received=$expected_received" <<<"$output"
  grep -Fq "result=$expected_result" <<<"$output"
  grep -Fq "resource-created=$expected_created" <<<"$output"
  grep -Fq "resource-drops=$expected_drops" <<<"$output"
  grep -Fq "pending-polls=$expected_pending" <<<"$output"
  grep -Fq "stream-drops=$expected_stream_drops" <<<"$output"
  grep -Fq "future-drops=$expected_future_drops" <<<"$output"
  grep -Fq 'table-empty=true' <<<"$output"
}

run_mode ready '[111]' 'Ok(())' 1 1 0 1 1
run_mode pending '[111]' 'Ok(())' 1 1 1 1 1
run_mode sink-error-before '[]' 'Err(Pipe)' 1 1 0 1 1
run_mode sink-error-after '[111]' 'Err(Pipe)' 1 1 0 1 1
run_mode cancel-before-transfer '[]' 'Err(Pipe)' 1 1 0 1 1
run_mode cancel-after-transfer '[111]' 'Err(Pipe)' 1 1 0 1 1
run_mode early-drop-before-transfer '[]' 'Err(Pipe)' 1 1 0 1 1
run_mode early-drop-after-transfer '[111]' 'Err(Pipe)' 1 1 0 1 1
run_mode repeat '[111, 111]' 'Ok(())' 2 2 0 2 2
run_mode invalid '[]' 'Err(InvalidMode)' 0 0 0 0 0

printf 'G6.2 owned-record producer compiler-generated Rust/Wasmtime gate passed\n'
