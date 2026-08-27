#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
wasm_tools_bin=${WASM_TOOLS:-wasm-tools}
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-owned-record-pair-parameterized-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wat="$repo_root/examples/p3-runtime/g6-2-owned-record-pair-parameterized-producer-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-pair-parameterized-producer.wit"
runner="$runner_dir/src/bin/g6_2_owned_record_pair_parameterized_producer_abi.rs"
core_wasm="$tmp_dir/canonical.core.wasm"
embedded="$tmp_dir/canonical.embedded.wasm"
component="$tmp_dir/canonical.component.wasm"

for path in "$wat" "$runner" "$wit"; do
  test -f "$path" || {
    printf 'missing pair producer probe artifact: %s\n' "$path" >&2
    exit 1
  }
done

expected_tools_version=${WASM_TOOLS_EXPECT_VERSION:-1.255.0}
actual_tools_version=$($wasm_tools_bin --version | awk 'NR == 1 { print $2 }')
test "$actual_tools_version" = "$expected_tools_version"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  e7abd3cf7b7543325865a0b4be4b32ae50a2470ac5083169250719f89b7ce53a

for marker in \
  'producer-record-byte-size' \
  'producer-record-left-offset' \
  'producer-record-right-offset' \
  'producer-stream-capacity' \
  'producer-input-mode' \
  'producer-left-ticket-seed-param' \
  'producer-right-ticket-seed-param' \
  'producer-seed-order' \
  'producer-input-word-count' \
  'producer-record-transfer' \
  'producer-resource-drop-exactly-once' \
  'producer-child-before-parent-cleanup'; do
  rg -q "^\\s*;; \\[${marker}\\]" "$wat"
done
if grep -Fq '__arc_' "$wat"; then
  printf 'pair producer canonical WAT contains ARC symbol\n' >&2
  exit 1
fi

$wasm_tools_bin parse "$wat" -o "$core_wasm"
$wasm_tools_bin component embed "$wit" "$core_wasm" \
  --world owned-record-pair-parameterized-producer \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
$wasm_tools_bin component new --skip-validation "$embedded" -o "$component"
$wasm_tools_bin validate --features cm-async,cm-more-async-builtins "$component"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-g6-2-owned-record-pair-parameterized-producer-abi
cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" --bin "$bin"

for mode in ready pending sink-error-before sink-error-after cancel-before-transfer \
  cancel-after-transfer early-drop-before-transfer early-drop-after-transfer repeat invalid; do
  case "$mode" in
    ready)
      left_seed=111
      right_seed=222
      expected_received='[111, 222]'
      ;;
    pending)
      left_seed=0
      right_seed=4294967295
      expected_received='[0, 4294967295]'
      ;;
    sink-error-before)
      left_seed=333
      right_seed=444
      expected_received='[]'
      ;;
    sink-error-after)
      left_seed=555
      right_seed=666
      expected_received='[555, 666]'
      ;;
    cancel-before-transfer)
      left_seed=777
      right_seed=888
      expected_received='[]'
      ;;
    cancel-after-transfer)
      left_seed=999
      right_seed=1000
      expected_received='[999, 1000]'
      ;;
    early-drop-before-transfer)
      left_seed=1234
      right_seed=5678
      expected_received='[]'
      ;;
    early-drop-after-transfer)
      left_seed=42
      right_seed=43
      expected_received='[42, 43]'
      ;;
    repeat)
      left_seed=111
      right_seed=222
      expected_received='[111, 222, 333, 444]'
      ;;
    invalid)
      left_seed=9
      right_seed=10
      expected_received='[]'
      ;;
  esac
  output=$(cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$bin" -- "$component" "$mode" "$left_seed" "$right_seed")
  printf '%s\n' "$output"
  grep -Fq "mode=$mode" <<<"$output"
  grep -Fq "received=$expected_received" <<<"$output"
  grep -Fq "left-ticket-seed:$left_seed" <<<"$output"
  grep -Fq "right-ticket-seed:$right_seed" <<<"$output"
  grep -Fq 'table-empty=true' <<<"$output"
  case "$mode" in
    ready|pending|sink-error-before|sink-error-after|cancel-before-transfer|cancel-after-transfer|early-drop-before-transfer|early-drop-after-transfer)
      expected_callback=1
      ;;
    repeat)
      expected_callback=2
      ;;
    invalid)
      expected_callback=0
      ;;
  esac
  case "$mode" in
    ready|sink-error-before|sink-error-after)
      expected_polls=1
      ;;
    pending)
      expected_polls=2
      ;;
    cancel-after-transfer|early-drop-after-transfer)
      expected_polls=1
      ;;
    repeat)
      expected_polls=2
      ;;
    cancel-before-transfer|early-drop-before-transfer|invalid)
      expected_polls=0
      ;;
  esac
  case "$mode" in
    cancel-before-transfer|cancel-after-transfer|early-drop-before-transfer|early-drop-after-transfer)
      expected_cancel=1
      expected_pending_future_drops=1
      expected_completions=0
      ;;
    repeat)
      expected_cancel=0
      expected_pending_future_drops=0
      expected_completions=2
      ;;
    invalid)
      expected_cancel=0
      expected_pending_future_drops=0
      expected_completions=0
      ;;
    *)
      expected_cancel=0
      expected_pending_future_drops=0
      expected_completions=1
      ;;
  esac
  grep -Fq "callback-calls=$expected_callback" <<<"$output"
  grep -Fq "poll-calls=$expected_polls" <<<"$output"
  grep -Fq 'finish-calls=0' <<<"$output"
  grep -Fq "cancel-calls=$expected_cancel" <<<"$output"
  grep -Fq "pending-future-drops=$expected_pending_future_drops" <<<"$output"
  grep -Fq "future-completions=$expected_completions" <<<"$output"
done

printf 'G6.2 parameterized owned-record pair canonical ABI probe passed modes=10 pair-fields=2 input-words=3 drops=2 table-empty=true\n'
