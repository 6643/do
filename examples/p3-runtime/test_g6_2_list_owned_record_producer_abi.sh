#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root="${TMPDIR:-$repo_root/.tmp/do-tmp}"
mkdir -p "$tmp_root"
export TMPDIR="$tmp_root"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$repo_root/.tmp/zig-cache}"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$repo_root/.tmp/zig-gcache}"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-list-owned-record-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    fd -H -I --max-depth 1 --type f --type d . "$tmp_dir" -X rm -rf --
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wat="$repo_root/examples/p3-runtime/g6-2-owned-record-list-producer-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-list-producer.wit"
runner_source="$runner_dir/src/bin/g6_2_list_owned_record_producer_abi.rs"
core_wasm="$tmp_dir/canonical.core.wasm"
embedded="$tmp_dir/canonical.embedded.wasm"
component="$tmp_dir/canonical.component.wasm"

test -x "$toolchain_bin"
for path in "$wat" "$wit" "$runner_source" "$runner_dir/Cargo.toml"; do
  test -f "$path" || {
    printf 'missing list-owned-record producer probe artifact: %s\n' "$path" >&2
    exit 1
  }
done

"$toolchain_bin" probe >/dev/null
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  cf7d047069cd9b30066debc88ce8edc159c9d2a90a310e56e384bb42c19cd6eb
rg -Fq 'package do:g6-2-owned-record-list-producer@0.1.0;' "$wit"
rg -Fq 'world owned-record-list-producer' "$wit"
rg -Fq 'record list-entry' "$wit"
rg -Fq 'values: list<u32>' "$wit"
rg -Fq 'ticket: own<ticket>' "$wit"
rg -Fq 'data: stream<list-entry>' "$wit"
rg -Fq 'make-ticket: func(seed: u32) -> own<ticket>;' "$wit"

for marker in \
  'producer-record-byte-size' \
  'producer-record-alignment' \
  'producer-record-values-pointer-offset' \
  'producer-record-values-length-offset' \
  'producer-record-ticket-offset' \
  'producer-list-stride' \
  'producer-list-capacity' \
  'producer-stream-capacity' \
  'producer-record-transfer' \
  'producer-list-release-exactly-once' \
  'producer-resource-drop-exactly-once' \
  'producer-child-before-parent-cleanup'; do
  rg -q "^\\s*;; \\[${marker}\\]" "$wat"
done
rg -Fq '[producer-record-byte-size] 12' "$wat"
rg -Fq '[producer-record-alignment] 4' "$wat"
rg -Fq '[producer-record-values-pointer-offset] 0' "$wat"
rg -Fq '[producer-record-values-length-offset] 4' "$wat"
rg -Fq '[producer-record-ticket-offset] 8' "$wat"
rg -Fq '[producer-list-stride] 4' "$wat"
rg -Fq '[producer-list-capacity] 3' "$wat"
rg -Fq '[producer-stream-capacity] 1' "$wat"
if rg -q '\(ref (null|extern|func|eq|struct|array)' "$wat"; then
  printf 'list-owned-record canonical probe contains a GC reference boundary\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" owned-record-list-producer \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-g6-2-list-owned-record-producer-abi
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
  local expected_poll_calls="$7"
  local expected_stream_drops="$8"
  local expected_future_drops="$9"
  local expected_pending="${10}"
  local expected_pending_future_drops="${11}"
  local expected_cancel_calls="${12}"
  local expected_list_reads="${13}"
  local expected_list_releases="${14}"
  local output
  output=$("$runner" "$component" "$mode")
  printf '%s\n' "$output"
  rg -Fq "mode=$mode" <<<"$output"
  rg -Fq "received=$expected_received" <<<"$output"
  rg -Fq "result=$expected_result" <<<"$output"
  rg -Fq "resource-created=$expected_created" <<<"$output"
  rg -Fq "resource-drops=$expected_drops" <<<"$output"
  rg -Fq "host-calls=$expected_host_calls" <<<"$output"
  rg -Fq "poll-calls=$expected_poll_calls" <<<"$output"
  rg -Fq "stream-drops=$expected_stream_drops" <<<"$output"
  rg -Fq "future-drops=$expected_future_drops" <<<"$output"
  rg -Fq "pending-polls=$expected_pending" <<<"$output"
  rg -Fq "pending-future-drops=$expected_pending_future_drops" <<<"$output"
  rg -Fq "cancel-calls=$expected_cancel_calls" <<<"$output"
  rg -Fq "list-read-releases=$expected_list_reads" <<<"$output"
  rg -Fq "list-releases=$expected_list_releases" <<<"$output"
  rg -Fq 'table-empty=true' <<<"$output"
}

run_mode ready '[([], 111)]' 'Ok(())' 1 1 1 1 1 1 0 0 0 1 1
run_mode pending '[([11, 22], 222)]' 'Ok(())' 1 1 1 2 1 1 1 0 0 1 1
run_mode sink-error-before '[]' 'Err(Pipe)' 1 1 1 1 1 1 0 0 0 0 1
run_mode sink-error-after '[([12], 333)]' 'Err(Pipe)' 1 1 1 1 1 1 0 0 0 1 1
run_mode cancel-before-transfer '[]' 'Err(Pipe)' 1 1 1 0 1 1 0 1 1 0 1
run_mode cancel-after-transfer '[([16], 555)]' 'Err(Pipe)' 1 1 1 1 1 1 0 1 1 1 1
run_mode early-drop-before-transfer '[]' 'Err(Pipe)' 1 1 1 0 1 1 0 1 1 0 1
run_mode early-drop-after-transfer '[([19, 20, 21], 777)]' 'Err(Pipe)' 1 1 1 1 1 1 0 1 1 1 1
run_mode repeat '[([22, 23], 888), ([22, 23], 888)]' 'Ok(())' 2 2 2 2 2 2 0 0 0 2 2
run_mode invalid '[]' 'Err(InvalidMode)' 0 0 0 0 0 0 0 0 0 0 0

printf 'G6.2 list-owned-record producer canonical ABI probe passed modes=10 list-capacity=3 record-size=12 drops=1 table-empty=true\n'
