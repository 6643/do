#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
wasm_tools_bin=${WASM_TOOLS:-wasm-tools}
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-owned-record-triple-rust.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

source="$repo_root/examples/p3-runtime/g6-2-owned-record-triple-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-triple-producer.wit"
wat="$tmp_dir/generated.wat"
wit="$tmp_dir/generated.wit"
core_wasm="$tmp_dir/generated.core.wasm"
embedded="$tmp_dir/generated.embedded.wasm"
component="$tmp_dir/generated.component.wasm"

test -x "$do_bin"
test -f "$source"
test -f "$probe_wit"
test -f "$runner_dir/Cargo.toml"
test -f "$runner_dir/src/bin/g6_2_owned_record_triple_producer.rs"
command -v "$wasm_tools_bin" >/dev/null 2>&1

expected_tools_version=${WASM_TOOLS_EXPECT_VERSION:-1.255.0}
actual_tools_version=$($wasm_tools_bin --version | awk 'NR == 1 { print $2 }')
test "$actual_tools_version" = "$expected_tools_version"

# Keep the measured canonical ABI probe independent from the generated route.
bash "$repo_root/examples/p3-runtime/test_g6_2_owned_record_triple_producer_abi.sh"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$wat"
cmp "$wit" "$probe_wit"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  73fd57dc8f34f13023b48f2b82e439b212eab52192886f0d07a37d86e63658b1
cmp "$wat" "$repo_root/examples/p3-runtime/g6-2-owned-record-triple-producer-canonical.wat"

for marker in \
  'producer-record-byte-size' \
  'producer-record-left-offset' \
  'producer-record-middle-offset' \
  'producer-record-right-offset' \
  'producer-stream-capacity' \
  'producer-input-mode' \
  'producer-left-ticket-seed-param' \
  'producer-middle-ticket-seed-param' \
  'producer-right-ticket-seed-param' \
  'producer-seed-order' \
  'producer-input-word-count' \
  'producer-record-transfer' \
  'producer-resource-drop-exactly-once' \
  'producer-child-before-parent-cleanup'; do
  rg -q "^\\s*;; \\[${marker}\\]" "$wat"
done
grep -Fq '[producer-record-byte-size] 12' "$wat"
grep -Fq '[producer-record-left-offset] 0' "$wat"
grep -Fq '[producer-record-middle-offset] 4' "$wat"
grep -Fq '[producer-record-right-offset] 8' "$wat"
grep -Fq '[producer-stream-capacity] 1' "$wat"
grep -Fq '[producer-input-word-count] 4' "$wat"
grep -Fq '[producer-seed-order] left then middle then right' "$wat"
grep -Fq '(func (export "[async-lift]produce")' "$wat"
if grep -Fq '__arc_' "$wat"; then
  printf 'owned-record triple generated WAT emitted an ARC symbol\n' >&2
  exit 1
fi

"$wasm_tools_bin" parse "$wat" -o "$core_wasm"
"$wasm_tools_bin" component embed "$wit" "$core_wasm" \
  --world owned-record-triple-producer \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
"$wasm_tools_bin" component new --skip-validation "$embedded" -o "$component"
"$wasm_tools_bin" validate --features cm-async,cm-more-async-builtins "$component"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-g6-2-owned-record-triple-producer
cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" --bin "$bin"
runner="$runner_dir/target/debug/$bin"
test -x "$runner"

run_mode() {
  local mode="$1"
  local left_seed="$2"
  local middle_seed="$3"
  local right_seed="$4"
  local expected_received="$5"
  local expected_result="$6"
  local expected_created="$7"
  local expected_drops="$8"
  local expected_host_calls="$9"
  local expected_pending="${10}"
  local expected_stream_drops="${11}"
  local expected_future_drops="${12}"
  local expected_callback_calls="${13}"
  local expected_poll_calls="${14}"
  local expected_cancel_calls="${15}"
  local expected_pending_future_drops="${16}"
  local expected_completions="${17}"
  local expected_future_polls="${18}"
  local output
  output=$("$runner" "$component" "$mode" "$left_seed" "$middle_seed" "$right_seed")
  printf '%s\n' "$output"
  grep -Fq "mode=$mode" <<<"$output"
  grep -Fq "received=$expected_received" <<<"$output"
  grep -Fq "result=$expected_result" <<<"$output"
  grep -Fq "resource-created=$expected_created" <<<"$output"
  grep -Fq "resource-drops=$expected_drops" <<<"$output"
  grep -Fq "host-calls=$expected_host_calls" <<<"$output"
  grep -Fq "pending-polls=$expected_pending" <<<"$output"
  grep -Fq "stream-drops=$expected_stream_drops" <<<"$output"
  grep -Fq "future-drops=$expected_future_drops" <<<"$output"
  grep -Fq "future-polls=$expected_future_polls" <<<"$output"
  grep -Fq "callback-calls=$expected_callback_calls" <<<"$output"
  grep -Fq "poll-calls=$expected_poll_calls" <<<"$output"
  grep -Fq 'finish-calls=0' <<<"$output"
  grep -Fq "cancel-calls=$expected_cancel_calls" <<<"$output"
  grep -Fq "pending-future-drops=$expected_pending_future_drops" <<<"$output"
  grep -Fq "future-completions=$expected_completions" <<<"$output"
  grep -Fq "left-ticket-seed:$left_seed" <<<"$output"
  grep -Fq "middle-ticket-seed:$middle_seed" <<<"$output"
  grep -Fq "right-ticket-seed:$right_seed" <<<"$output"
  grep -Fq 'layout=record-offset:64 record-byte-size:12 left-offset:0 middle-offset:4 right-offset:8 stream-capacity:1' <<<"$output"
  grep -Fq 'table-empty=true' <<<"$output"
}

run_mode ready 111 222 333 '[111, 222, 333]' 'Ok(())' 3 3 1 0 1 1 1 1 0 0 1 1
run_mode pending 0 4294967295 1 '[0, 4294967295, 1]' 'Ok(())' 3 3 1 1 1 1 1 2 0 0 1 1
run_mode sink-error-before 444 555 666 '[]' 'Err(Pipe)' 3 3 1 0 1 1 1 1 0 0 1 1
run_mode sink-error-after 777 888 999 '[777, 888, 999]' 'Err(Pipe)' 3 3 1 0 1 1 1 1 0 0 1 1
run_mode cancel-before-transfer 1001 1002 1003 '[]' 'Err(Pipe)' 3 3 1 0 1 1 1 0 1 1 0 1
run_mode cancel-after-transfer 2001 2002 2003 '[2001, 2002, 2003]' 'Err(Pipe)' 3 3 1 0 1 1 1 1 1 1 0 1
run_mode early-drop-before-transfer 3001 3002 3003 '[]' 'Err(Pipe)' 3 3 1 0 1 1 1 0 1 1 0 1
run_mode early-drop-after-transfer 4001 4002 4003 '[4001, 4002, 4003]' 'Err(Pipe)' 3 3 1 0 1 1 1 1 1 1 0 1
run_mode repeat 111 222 333 '[111, 222, 333, 444, 555, 666]' 'Ok(())' 6 6 2 0 2 2 2 2 0 0 2 2
run_mode invalid 9 10 11 '[]' 'Err(InvalidMode)' 0 0 0 0 0 0 0 0 0 0 0 0

printf 'G6.2 owned-record triple compiler-generated Rust/Wasmtime lifecycle gate passed modes=10 triple-fields=3 input-words=4 drops=3 table-empty=true\n'
