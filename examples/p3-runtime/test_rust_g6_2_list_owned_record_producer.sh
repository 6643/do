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
tmp_dir=$(mktemp -d "$tmp_root/g6-2-list-owned-record-producer-rust.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

source="$repo_root/examples/p3-runtime/g6-2-owned-record-list-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-list-producer.wit"
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
test -f "$runner_dir/src/bin/g6_2_list_owned_record_producer.rs"
test -f "$runner_dir/src/bin/g6_2_list_owned_record_producer_abi.rs"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$wat"
cmp "$wit" "$probe_wit"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  cf7d047069cd9b30066debc88ce8edc159c9d2a90a310e56e384bb42c19cd6eb
for marker in \
  '[producer-record-byte-size] 12' \
  '[producer-record-alignment] 4' \
  '[producer-record-values-pointer-offset] 0' \
  '[producer-record-values-length-offset] 4' \
  '[producer-record-ticket-offset] 8' \
  '[producer-list-stride] 4' \
  '[producer-list-capacity] 3' \
  '[producer-stream-capacity] 1' \
  '[producer-record-transfer]' \
  '[producer-list-release-exactly-once]' \
  '[producer-resource-drop-exactly-once]'; do
  grep -Fq ";; $marker" "$wat"
done
if grep -Fq '__arc_' "$wat"; then
  printf 'list-owned-record producer emitted an ARC symbol\n' >&2
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
  zig_cache_root="$tmp_dir/zig-cache"
  mkdir -p "$zig_cache_root/global" "$zig_cache_root/local"
  export ZIG_GLOBAL_CACHE_DIR="$zig_cache_root/global"
  export ZIG_LOCAL_CACHE_DIR="$zig_cache_root/local"
fi

bin=do-p3-g6-2-list-owned-record-producer
cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" --bin "$bin"
runner="$runner_dir/target/debug/$bin"
test -x "$runner"

run_mode() {
  local mode="$1"
  local expected_received expected_result
  case "$mode" in
    ready) expected_received='[([], 111)]'; expected_result='Ok(())' ;;
    pending) expected_received='[([11, 22], 222)]'; expected_result='Ok(())' ;;
    sink-error-before) expected_received='[]'; expected_result='Err(Pipe)' ;;
    sink-error-after) expected_received='[([12], 333)]'; expected_result='Err(Pipe)' ;;
    cancel-before-transfer|early-drop-before-transfer) expected_received='[]'; expected_result='Err(Pipe)' ;;
    cancel-after-transfer) expected_received='[([16], 555)]'; expected_result='Err(Pipe)' ;;
    early-drop-after-transfer) expected_received='[([19, 20, 21], 777)]'; expected_result='Err(Pipe)' ;;
    repeat) expected_received='[([22, 23], 888), ([22, 23], 888)]'; expected_result='Ok(())' ;;
    invalid) expected_received='[]'; expected_result='Err(InvalidMode)' ;;
    *) printf 'unknown lifecycle mode: %s\n' "$mode" >&2; exit 1 ;;
  esac
  local output
  output=$("$runner" "$component" "$mode")
  printf '%s\n' "$output"
  grep -Fq "mode=$mode" <<<"$output"
  grep -Fq "received=$expected_received" <<<"$output"
  grep -Fq "result=$expected_result" <<<"$output"
  grep -Fq 'table-empty=true' <<<"$output"
  grep -Fq 'layout=record-offset:64 record-byte-size:12 record-alignment:4 values-pointer-offset:0 values-length-offset:4 ticket-offset:8 list-stride:4 list-capacity:3 stream-capacity:1' <<<"$output"
  case "$mode" in
    ready) grep -Fq 'list-read-releases=1 list-releases=1' <<<"$output" ;;
    pending) grep -Fq 'poll-calls=2' <<<"$output"; grep -Fq 'pending-polls=1' <<<"$output" ;;
    sink-error-before) grep -Fq 'list-read-releases=0 list-releases=1' <<<"$output" ;;
    sink-error-after) grep -Fq 'list-read-releases=1 list-releases=1' <<<"$output" ;;
    cancel-before-transfer|early-drop-before-transfer) grep -Fq 'poll-calls=0' <<<"$output"; grep -Fq 'pending-future-drops=1' <<<"$output" ;;
    cancel-after-transfer) grep -Fq 'list-read-releases=1 list-releases=1' <<<"$output"; grep -Fq 'cancel-calls=1' <<<"$output" ;;
    early-drop-after-transfer) grep -Fq 'list-read-releases=1 list-releases=1' <<<"$output"; grep -Fq 'cancel-calls=1' <<<"$output" ;;
    repeat) grep -Fq 'resource-created=2 resource-drops=2' <<<"$output"; grep -Fq 'list-read-releases=2 list-releases=2' <<<"$output" ;;
    invalid) grep -Fq 'resource-created=0 resource-drops=0' <<<"$output"; grep -Fq 'list-read-releases=0 list-releases=0' <<<"$output" ;;
  esac
}

run_mode ready
run_mode pending
run_mode sink-error-before
run_mode sink-error-after
run_mode cancel-before-transfer
run_mode cancel-after-transfer
run_mode early-drop-before-transfer
run_mode early-drop-after-transfer
run_mode repeat
run_mode invalid

printf 'G6.2 list-owned-record producer compiler-generated Rust/Wasmtime lifecycle gate passed modes=10 record-fields=2 list-release=1 resource-drops=1 table-empty=true\n'
