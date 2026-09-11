#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
export TMPDIR="$tmp_root"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$repo_root/.tmp/do-tmp/g6-2-two-list-zig-cache/local}"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$repo_root/.tmp/do-tmp/g6-2-two-list-zig-cache/global}"
mkdir -p "$ZIG_LOCAL_CACHE_DIR" "$ZIG_GLOBAL_CACHE_DIR"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-two-list-owned-record-producer-rust.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

source="$repo_root/examples/p3-runtime/g6-2-owned-record-two-list-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-two-list-producer.wit"
canonical_wat="$repo_root/examples/p3-runtime/g6-2-owned-record-two-list-producer-canonical.wat"
wat="$tmp_dir/generated.wat"
wit="$tmp_dir/generated.wit"
core_wasm="$tmp_dir/generated.core.wasm"
embedded="$tmp_dir/generated.embedded.wasm"
component="$tmp_dir/generated.component.wasm"

test -x "$do_bin"
test -x "$toolchain_bin"
test -f "$source"
test -f "$probe_wit"
test -f "$canonical_wat"
test -f "$runner_dir/Cargo.toml"
test -f "$runner_dir/src/bin/g6_2_two_list_owned_record_producer.rs"
test -f "$runner_dir/src/bin/g6_2_two_list_owned_record_producer_abi.rs"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$wat"
cmp "$wit" "$probe_wit"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  14ba67e070346a127e75c7dfd73c71d6082ad7d9385c7d803834319dabc6404a
cmp "$wat" "$canonical_wat"

for marker in \
  '[producer-record-byte-size] 20' \
  '[producer-record-alignment] 4' \
  '[producer-first-pointer-offset] 0' \
  '[producer-first-length-offset] 4' \
  '[producer-second-pointer-offset] 8' \
  '[producer-second-length-offset] 12' \
  '[producer-ticket-offset] 16' \
  '[producer-list-stride] 4' \
  '[producer-list-capacity] 3' \
  '[producer-stream-capacity] 1' \
  '[producer-ticket-seed] 111' \
  '[producer-record-transfer]' \
  '[producer-list-release-exactly-once]' \
  '[producer-resource-drop-exactly-once]' \
  '[producer-child-before-parent-cleanup]'; do
  grep -Fq ";; $marker" "$wat"
done
grep -Fq '(func (export "[async-lift]produce")' "$wat"
if grep -Fq '__arc_' "$wat"; then
  printf 'two-list owned-record producer emitted an ARC symbol\n' >&2
  exit 1
fi
if grep -Eq '\(ref (null|extern|func|eq|struct|array)' "$wat"; then
  printf 'two-list owned-record producer crossed a GC reference boundary\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" owned-record-two-list-producer \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-g6-2-two-list-owned-record-producer
cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" --bin "$bin"
runner="$runner_dir/target/debug/$bin"
test -x "$runner"

run_mode() {
  local mode="$1"
  local expected_received="$2"
  local expected_result="$3"
  local expected_created="$4"
  local expected_drops="$5"
  local expected_host_calls="$6"
  local expected_pending="$7"
  local expected_stream_drops="$8"
  local expected_future_drops="$9"
  local expected_future_polls="${10}"
  local expected_completions="${11}"
  local expected_pending_future_drops="${12}"
  local expected_cancel_calls="${13}"
  local expected_poll_calls="${14}"
  local expected_list_read_releases="${15}"
  local expected_list_allocations=$((expected_created * 2))
  local output
  output=$("$runner" "$component" "$mode")
  printf '%s\n' "$output"
  grep -Fq "mode=$mode" <<<"$output"
  grep -Fq "received=$expected_received" <<<"$output"
  grep -Fq "result=$expected_result" <<<"$output"
  grep -Fq "resource-created=$expected_created" <<<"$output"
  grep -Fq "resource-drops=$expected_drops" <<<"$output"
  grep -Fq "host-calls=$expected_host_calls" <<<"$output"
  grep -Fq "pending-polls=$expected_pending" <<<"$output"
  grep -Fq "poll-calls=$expected_poll_calls" <<<"$output"
  grep -Fq "stream-drops=$expected_stream_drops" <<<"$output"
  grep -Fq "future-drops=$expected_future_drops" <<<"$output"
  grep -Fq "future-polls=$expected_future_polls" <<<"$output"
  grep -Fq "future-completions=$expected_completions" <<<"$output"
  grep -Fq "pending-future-drops=$expected_pending_future_drops" <<<"$output"
  grep -Fq "cancel-calls=$expected_cancel_calls" <<<"$output"
  grep -Fq "list-read-releases=$expected_list_read_releases" <<<"$output"
  grep -Fq "list-allocations=$expected_list_allocations" <<<"$output"
  grep -Fq "list-releases=$expected_list_allocations" <<<"$output"
  grep -Fq 'table-empty=true' <<<"$output"
  grep -Fq 'layout=record-offset:64 record-byte-size:20 record-alignment:4 first-pointer-offset:0 first-length-offset:4 second-pointer-offset:8 second-length-offset:12 ticket-offset:16 list-stride:4 list-capacity:3 stream-capacity:1' <<<"$output"
}

run_mode ready '[([], [10], 111)]' 'Ok(())' 1 1 1 0 1 1 1 1 0 0 1 2
run_mode pending '[([11, 22], [31], 222)]' 'Ok(())' 1 1 1 1 1 1 1 1 0 0 2 2
run_mode sink-error-before '[]' 'Err(Pipe)' 1 1 1 0 1 1 1 1 0 0 1 0
run_mode sink-error-after '[([12], [32, 33], 333)]' 'Err(Pipe)' 1 1 1 0 1 1 1 1 0 0 1 2
run_mode cancel-before-transfer '[]' 'Err(Pipe)' 1 1 1 0 1 1 1 0 1 1 0 0
run_mode cancel-after-transfer '[([16], [46], 555)]' 'Err(Pipe)' 1 1 1 0 1 1 1 0 1 1 1 2
run_mode early-drop-before-transfer '[]' 'Err(Pipe)' 1 1 1 0 1 1 1 0 1 1 0 0
run_mode early-drop-after-transfer '[([19, 20, 21], [79, 80], 777)]' 'Err(Pipe)' 1 1 1 0 1 1 1 0 1 1 1 2
run_mode repeat '[([22, 23], [82, 83, 84], 888), ([22, 23], [82, 83, 84], 888)]' 'Ok(())' 2 2 2 0 2 2 2 2 0 0 2 4
run_mode invalid '[]' 'Err(InvalidMode)' 0 0 0 0 0 0 0 0 0 0 0 0

printf 'G6.2 two-list owned-record producer compiler-generated Rust/Wasmtime lifecycle gate passed modes=10 record-fields=3 list-release=2 resource-drops=1 table-empty=true\n'
