#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-owned-record-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wat="$repo_root/examples/p3-runtime/g6-2-owned-record-producer-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-producer.wit"
runner="$runner_dir/src/bin/g6_2_owned_record_producer_abi.rs"
core_wasm="$tmp_dir/canonical.core.wasm"
embedded="$tmp_dir/canonical.embedded.wasm"
component="$tmp_dir/canonical.component.wasm"

for path in "$wat" "$runner"; do
  if [[ ! -f "$path" ]]; then
    printf 'missing probe artifact: %s\n' "$path" >&2
    exit 1
  fi
done

if [[ ! -f "$wit" ]]; then
  printf 'missing WIT source: %s\n' "$wit" >&2
  exit 1
fi

expected_tools_version=${WASM_TOOLS_EXPECT_VERSION:-1.255.0}
actual_tools_version=$(wasm-tools --version | awk 'NR == 1 { print $2 }')
if [[ "$actual_tools_version" != "$expected_tools_version" ]]; then
  printf 'wasm-tools version mismatch: expected %s, got %s\n' \
    "$expected_tools_version" "$actual_tools_version" >&2
  exit 1
fi

test "$(sha256sum "$wit" | awk '{print $1}')" = \
  6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace
grep -Fq 'package do:g6-2-owned-record-producer@0.1.0;' "$wit"
grep -Fq 'world owned-record-producer' "$wit"
grep -Fq 'data: stream<resource-entry>' "$wit"
grep -Fq 'resource-entry { ticket: own<ticket> }' "$wit"
grep -Fq 'make-ticket: func(seed: u32) -> own<ticket>;' "$wit"
grep -Fq 'consume-via-stream: async func(' "$wit"

for marker in \
  'producer-record-byte-size' \
  'producer-record-ticket-offset' \
  'producer-stream-capacity' \
  'producer-ticket-seed' \
  'producer-record-transfer' \
  'producer-resource-drop-exactly-once' \
  'producer-child-before-parent-cleanup'; do
  rg -q "^\\s*;; \\[$marker\\]" "$wat"
done

wasm-tools parse "$wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world owned-record-producer \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

marker_value() {
  local marker="$1"
  awk -v marker="$marker" '
    $0 ~ "^[[:space:]]*;; \\[" marker "\\]" {
      if ($0 ~ /\] [0-9]+$/) { print $NF; exit }
      want = 1
      next
    }
    want && $1 == "i32.const" { print $2; exit }
    want { exit 1 }
  ' "$wat"
}

test "$(marker_value 'producer-record-byte-size')" = 4
test "$(marker_value 'producer-record-ticket-offset')" = 0
test "$(marker_value 'producer-stream-capacity')" = 1
test "$(marker_value 'producer-ticket-seed')" = 111

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-g6-2-owned-record-producer-abi
for mode in ready pending sink-error-before sink-error-after cancel-before-transfer \
  cancel-after-transfer early-drop-before-transfer early-drop-after-transfer repeat invalid; do
  output=$(cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$bin" -- "$component" "$mode")
  printf '%s\n' "$output"
  grep -Fq "mode=$mode" <<<"$output"
  grep -Fq 'table-empty=true' <<<"$output"
done

printf 'G6.2 owned record producer canonical ABI probe passed\n'
