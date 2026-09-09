#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
canonical_wat="$repo_root/examples/p3-runtime/g6-2-owned-record-mixed-producer-canonical.wat"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-mixed-producer.wit"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-mixed-owned-record-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

runner="$runner_dir/src/bin/g6_2_mixed_owned_record_producer_abi.rs"
core_wasm="$tmp_dir/canonical.core.wasm"
embedded="$tmp_dir/canonical.embedded.wasm"
component="$tmp_dir/canonical.component.wasm"

test -x "$toolchain_bin"
test -f "$canonical_wat"
test -f "$probe_wit"
test -f "$runner"

test "$(sha256sum "$probe_wit" | awk '{print $1}')" = \
  5fe1c2ed6a0c348bf6f0e96596afc419bbbd379345421f02fa36f05aa472d9ed
grep -Fq 'package do:g6-2-owned-record-mixed-producer@0.1.0;' "$probe_wit"
grep -Fq 'world owned-record-mixed-producer' "$probe_wit"
grep -Fq 'record mixed-entry' "$probe_wit"
grep -Fq 'data: stream<mixed-entry>' "$probe_wit"
grep -Fq 'ticket: own<ticket>' "$probe_wit"
grep -Fq 'make-ticket: func(seed: u32) -> own<ticket>;' "$probe_wit"

for marker in \
  'producer-record-byte-size' \
  'producer-record-alignment' \
  'producer-record-code-offset' \
  'producer-record-ticket-offset' \
  'producer-stream-capacity' \
  'producer-ticket-seed' \
  'producer-record-transfer' \
  'producer-resource-drop-exactly-once' \
  'producer-child-before-parent-cleanup'; do
  rg -q "^\\s*;; \\[${marker}\\]" "$canonical_wat"
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
  ' "$canonical_wat"
}

test "$(marker_value 'producer-record-byte-size')" = 8
test "$(marker_value 'producer-record-alignment')" = 4
test "$(marker_value 'producer-record-code-offset')" = 0
test "$(marker_value 'producer-record-ticket-offset')" = 4
test "$(marker_value 'producer-stream-capacity')" = 1
test "$(marker_value 'producer-ticket-seed')" = 111
if grep -Eq '\(ref (null|extern|func|eq|struct|array)' "$canonical_wat"; then
  printf 'mixed owned-record canonical probe contains a GC reference boundary\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$canonical_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$probe_wit" "$core_wasm" owned-record-mixed-producer \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-g6-2-mixed-owned-record-producer-abi
cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" --bin "$bin"
for mode in ready pending sink-error-before sink-error-after cancel-before-transfer \
  cancel-after-transfer early-drop-before-transfer early-drop-after-transfer repeat invalid; do
  output=$(cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$bin" -- "$component" "$mode")
  printf '%s\n' "$output"
  grep -Fq "mode=$mode" <<<"$output"
  grep -Fq 'table-empty=true' <<<"$output"
done

printf 'G6.2 mixed owned-record producer canonical ABI probe passed\n'
