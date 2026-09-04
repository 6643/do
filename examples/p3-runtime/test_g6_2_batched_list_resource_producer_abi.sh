#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-batched-list-resource-producer.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wat="$repo_root/examples/p3-runtime/g6-2-batched-list-resource-producer-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/g6-2-batched-list-resource-producer.wit"
runner="$runner_dir/src/bin/g6_2_batched_list_resource_producer_abi.rs"
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

grep -Fq 'package do:g6-2-batched-list-producer@0.1.0;' "$wit"
grep -Fq 'world batched-list-producer' "$wit"
grep -Fq 'data: stream<list<resource-entry>>' "$wit"
grep -Fq 'i32.const 111' "$wat"
grep -Fq 'i32.const 222' "$wat"
grep -Fq 'i32.const 333' "$wat"
for marker in \
  'producer-batch-0' \
  'producer-batch-1' \
  'producer-batch-transfer-0' \
  'producer-batch-transfer-1' \
  'producer-batch-child-before-parent-cleanup' \
  'producer-batch-list-release'; do
  rg -q "^\s*;; \[$marker\]$" "$wat"
done

"$toolchain_bin" parse-core "$wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" batched-list-producer \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

marker_value() {
  local marker="$1"
  awk -v marker="$marker" '
    $0 ~ "^[[:space:]]*;; \\[" marker "\\]$" { want = 1; next }
    want && $1 == "i32.const" { print $2; exit }
    want { exit 1 }
  ' "$wat"
}

test "$(marker_value 'producer-list-pointer')" = 64
test "$(marker_value 'producer-list-length')" = 68
test "$(marker_value 'producer-list-element-stride')" = 4
test "$(marker_value 'producer-list-ticket-offset')" = 0
test "$(marker_value 'producer-stream-capacity')" = 1

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-g6-2-batched-list-resource-producer-abi
for mode in ready pending sink-error-first sink-error-second cancel-before-first cancel-after-first; do
  output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$bin" -- "$component" "$mode")
  printf '%s\n' "$output"
  grep -Fq 'table-empty=true' <<<"$output"
done

printf 'G6.2 batched list resource producer canonical ABI probe passed\n'
