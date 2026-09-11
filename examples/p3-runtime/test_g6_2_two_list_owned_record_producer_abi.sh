#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root="${TMPDIR:-$repo_root/.tmp/do-tmp}"
mkdir -p "$tmp_root"
export TMPDIR="$tmp_root"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$repo_root/.tmp/do-tmp/g6-2-two-list-zig-cache/local}"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$repo_root/.tmp/do-tmp/g6-2-two-list-zig-cache/global}"
mkdir -p "$ZIG_LOCAL_CACHE_DIR" "$ZIG_GLOBAL_CACHE_DIR"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-two-list-owned-record-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wat="$repo_root/examples/p3-runtime/g6-2-owned-record-two-list-producer-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-two-list-producer.wit"
runner_source="$runner_dir/src/bin/g6_2_two_list_owned_record_producer_abi.rs"
core_wasm="$tmp_dir/canonical.core.wasm"
embedded="$tmp_dir/canonical.embedded.wasm"
component="$tmp_dir/canonical.component.wasm"

for path in "$wat" "$wit" "$runner_source" "$runner_dir/Cargo.toml"; do
  test -f "$path" || {
    printf 'missing two-list owned-record producer probe artifact: %s\n' "$path" >&2
    exit 1
  }
done
test -x "$toolchain_bin"

"$toolchain_bin" probe >/dev/null
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  14ba67e070346a127e75c7dfd73c71d6082ad7d9385c7d803834319dabc6404a
grep -Fq 'package do:g6-2-owned-record-two-list-producer@0.1.0;' "$wit"
grep -Fq 'world owned-record-two-list-producer' "$wit"
grep -Fq 'first: list<u32>' "$wit"
grep -Fq 'second: list<u32>' "$wit"
grep -Fq 'ticket: own<ticket>' "$wit"
grep -Fq 'consume-via-stream: async func(' "$wit"
grep -Fq 'data: stream<two-list-entry>' "$wit"
grep -Fq 'make-ticket: func(seed: u32) -> own<ticket>;' "$wit"

for marker in \
  'producer-record-byte-size' \
  'producer-record-alignment' \
  'producer-first-pointer-offset' \
  'producer-first-length-offset' \
  'producer-second-pointer-offset' \
  'producer-second-length-offset' \
  'producer-ticket-offset' \
  'producer-list-stride' \
  'producer-list-capacity' \
  'producer-stream-capacity' \
  'producer-ticket-seed' \
  'producer-record-transfer' \
  'producer-list-release-exactly-once' \
  'producer-resource-drop-exactly-once' \
  'producer-child-before-parent-cleanup'; do
  rg -q "^\\s*;; \\[${marker}\\]" "$wat"
done

marker_value() {
  local marker="$1"
  awk -v marker="$marker" '
    $0 ~ "^[[:space:]]*;; \\[" marker "\\]" {
      if ($0 ~ /\\] [0-9]+$/) { print $NF; exit }
      want = 1
      next
    }
    want && $1 == "i32.const" { print $2; exit }
    want { exit 1 }
  ' "$wat"
}

test "$(marker_value 'producer-record-byte-size')" = 20
test "$(marker_value 'producer-record-alignment')" = 4
test "$(marker_value 'producer-first-pointer-offset')" = 0
test "$(marker_value 'producer-first-length-offset')" = 4
test "$(marker_value 'producer-second-pointer-offset')" = 8
test "$(marker_value 'producer-second-length-offset')" = 12
test "$(marker_value 'producer-ticket-offset')" = 16
test "$(marker_value 'producer-list-stride')" = 4
test "$(marker_value 'producer-list-capacity')" = 3
test "$(marker_value 'producer-stream-capacity')" = 1
test "$(marker_value 'producer-ticket-seed')" = 111
if grep -Eq '\(ref (null|extern|func|eq|struct|array)' "$wat"; then
  printf 'two-list owned-record canonical probe contains a GC reference boundary\n' >&2
  exit 1
fi
if grep -Eq '\b(__arc_|array|struct)\b' "$wat"; then
  printf 'two-list owned-record canonical probe contains a forbidden GC/ARC marker\n' >&2
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

bin=do-p3-g6-2-two-list-owned-record-producer-abi
cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" --bin "$bin"
runner="$runner_dir/target/debug/$bin"
test -x "$runner"

for mode in ready pending sink-error-before sink-error-after cancel-before-transfer \
  cancel-after-transfer early-drop-before-transfer early-drop-after-transfer repeat invalid; do
  output=$("$runner" "$component" "$mode")
  printf '%s\n' "$output"
  grep -Fq "mode=$mode" <<<"$output"
  grep -Fq 'table-empty=true' <<<"$output"
done

printf 'G6.2 two-list owned-record producer canonical ABI probe passed modes=10 list-capacity=3 record-size=20 releases=2 table-empty=true\n'
