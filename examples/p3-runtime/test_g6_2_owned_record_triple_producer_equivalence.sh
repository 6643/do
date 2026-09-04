#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
canonical_wat="$repo_root/examples/p3-runtime/g6-2-owned-record-triple-producer-canonical.wat"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-triple-producer.wit"
source="$repo_root/examples/p3-runtime/g6-2-owned-record-triple-producer.do"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-owned-record-triple-equivalence.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

test -x "$do_bin"
test -x "$toolchain_bin"
test -f "$canonical_wat"
test -f "$probe_wit"
test -f "$source"
test -f "$runner_dir/Cargo.toml"
test -f "$runner_dir/src/bin/g6_2_owned_record_triple_producer_abi.rs"
canonical_component="$tmp_dir/canonical.component.wasm"
generated_wat="$tmp_dir/generated.wat"
generated_wit="$tmp_dir/generated.wit"
generated_component="$tmp_dir/generated.component.wasm"

assemble_component() {
  local wat="$1"
  local wit="$2"
  local stem="$3"
  local output="$4"
  local core_wasm="$tmp_dir/$stem.core.wasm"
  local embedded="$tmp_dir/$stem.embedded.wasm"
  "$toolchain_bin" parse-core "$wat" -o "$core_wasm"
  "$toolchain_bin" embed-component "$wit" "$core_wasm" owned-record-triple-producer \
    --features component-async -o "$embedded"
  "$toolchain_bin" new-component "$embedded" -o "$output"
  "$toolchain_bin" validate-component "$output" --features component-async
}

assemble_component "$canonical_wat" "$probe_wit" canonical "$canonical_component"
DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$generated_wit" -o "$generated_wat"
cmp "$generated_wit" "$probe_wit"
test "$(sha256sum "$generated_wit" | awk '{print $1}')" = \
  73fd57dc8f34f13023b48f2b82e439b212eab52192886f0d07a37d86e63658b1
cmp "$generated_wat" "$canonical_wat"
if grep -Fq '__arc_' "$generated_wat"; then
  printf 'owned-record triple generated WAT emitted an ARC symbol\n' >&2
  exit 1
fi
assemble_component "$generated_wat" "$generated_wit" generated "$generated_component"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-g6-2-owned-record-triple-producer-abi
cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" --bin "$bin"
runner="$runner_dir/target/debug/$bin"
test -x "$runner"

run_equivalent() {
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
  local canonical_output="$tmp_dir/canonical-$mode.out"
  local generated_output="$tmp_dir/generated-$mode.out"

  "$runner" "$canonical_component" "$mode" "$left_seed" "$middle_seed" "$right_seed" >"$canonical_output"
  "$runner" "$generated_component" "$mode" "$left_seed" "$middle_seed" "$right_seed" >"$generated_output"
  diff -u "$canonical_output" "$generated_output"

  grep -Fq "mode=$mode" "$canonical_output"
  grep -Fq "received=$expected_received" "$canonical_output"
  grep -Fq "result=$expected_result" "$canonical_output"
  grep -Fq "resource-created=$expected_created" "$canonical_output"
  grep -Fq "resource-drops=$expected_drops" "$canonical_output"
  grep -Fq "host-calls=$expected_host_calls" "$canonical_output"
  grep -Fq "pending-polls=$expected_pending" "$canonical_output"
  grep -Fq "stream-drops=$expected_stream_drops" "$canonical_output"
  grep -Fq "future-drops=$expected_future_drops" "$canonical_output"
  grep -Fq "future-polls=$expected_future_polls" "$canonical_output"
  grep -Fq "callback-calls=$expected_callback_calls" "$canonical_output"
  grep -Fq "poll-calls=$expected_poll_calls" "$canonical_output"
  grep -Fq 'finish-calls=0' "$canonical_output"
  grep -Fq "cancel-calls=$expected_cancel_calls" "$canonical_output"
  grep -Fq "pending-future-drops=$expected_pending_future_drops" "$canonical_output"
  grep -Fq "future-completions=$expected_completions" "$canonical_output"
  grep -Fq "left-ticket-seed:$left_seed" "$canonical_output"
  grep -Fq "middle-ticket-seed:$middle_seed" "$canonical_output"
  grep -Fq "right-ticket-seed:$right_seed" "$canonical_output"
  grep -Fq 'layout=record-offset:64 record-byte-size:12 left-offset:0 middle-offset:4 right-offset:8 stream-capacity:1' "$canonical_output"
  grep -Fq 'table-empty=true' "$canonical_output"
  printf 'PASS %s: canonical and generated triple lifecycle observations agree\n' "$mode"
}

run_equivalent ready 111 222 333 '[111, 222, 333]' 'Ok(())' 3 3 1 0 1 1 1 1 0 0 1 1
run_equivalent pending 0 4294967295 1 '[0, 4294967295, 1]' 'Ok(())' 3 3 1 1 1 1 1 2 0 0 1 1
run_equivalent sink-error-before 444 555 666 '[]' 'Err(Pipe)' 3 3 1 0 1 1 1 1 0 0 1 1
run_equivalent sink-error-after 777 888 999 '[777, 888, 999]' 'Err(Pipe)' 3 3 1 0 1 1 1 1 0 0 1 1
run_equivalent cancel-before-transfer 1001 1002 1003 '[]' 'Err(Pipe)' 3 3 1 0 1 1 1 0 1 1 0 1
run_equivalent cancel-after-transfer 2001 2002 2003 '[2001, 2002, 2003]' 'Err(Pipe)' 3 3 1 0 1 1 1 1 1 1 0 1
run_equivalent early-drop-before-transfer 3001 3002 3003 '[]' 'Err(Pipe)' 3 3 1 0 1 1 1 0 1 1 0 1
run_equivalent early-drop-after-transfer 4001 4002 4003 '[4001, 4002, 4003]' 'Err(Pipe)' 3 3 1 0 1 1 1 1 1 1 0 1
run_equivalent repeat 111 222 333 '[111, 222, 333, 444, 555, 666]' 'Ok(())' 6 6 2 0 2 2 2 2 0 0 2 2
run_equivalent invalid 9 10 11 '[]' 'Err(InvalidMode)' 0 0 0 0 0 0 0 0 0 0 0 0

printf 'canonical/generated owned-record triple equivalence passed modes=10 triple-fields=3 input-words=4 table-empty=true\n'
