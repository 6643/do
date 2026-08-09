#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-scalar-list-producer.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wat="$repo_root/examples/p3-runtime/g6-2-scalar-list-producer-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/g6-2-scalar-list-producer.wit"
runner="$runner_dir/src/bin/g6_2_scalar_list_producer_abi.rs"
core_wasm="$tmp_dir/canonical.core.wasm"
embedded="$tmp_dir/canonical.embedded.wasm"
component="$tmp_dir/canonical.component.wasm"

for path in "$wat" "$runner" "$wit"; do
  if [[ ! -f "$path" ]]; then
    printf 'missing probe artifact: %s\n' "$path" >&2
    exit 1
  fi
done

expected_tools_version=${WASM_TOOLS_EXPECT_VERSION:-1.255.0}
actual_tools_version=$(wasm-tools --version | awk 'NR == 1 { print $2 }')
if [[ "$actual_tools_version" != "$expected_tools_version" ]]; then
  printf 'wasm-tools version mismatch: expected %s, got %s\n' \
    "$expected_tools_version" "$actual_tools_version" >&2
  exit 1
fi

grep -Fq 'package do:g6-2-scalar-list-producer@0.1.0;' "$wit"
grep -Fq 'consume-via-stream: async func(data: stream<list<u32>>) -> result<_, error-code>;' "$wit"
grep -Fq 'export produce: async func(count: u32) -> result<_, error-code>;' "$wit"
if rg -n 'own<|borrow<|ref<|resource|pointer|reference' "$wit"; then
  printf 'scalar list probe unexpectedly contains an ownership or reference shape\n' >&2
  exit 1
fi

for marker in \
  'producer-list-pointer' \
  'producer-list-length' \
  'producer-list-element-stride' \
  'producer-list-capacity' \
  'producer-stream-item-slot' \
  'producer-cancel-before-transfer' \
  'producer-list-release-exactly-once'; do
  rg -q "^\\s*;; \\[$marker\\]$" "$wat"
done

wasm-tools parse "$wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world scalar-list-producer \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

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
test "$(marker_value 'producer-list-capacity')" = 3
test "$(marker_value 'producer-stream-item-slot')" = 0

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=g6_2_scalar_list_producer_abi
run_mode() {
  local mode="$1"
  local expected_releases="$2"
  local output
  output=$(cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$bin" -- "$component" "$mode")
  printf '%s\n' "$output"
  grep -Fq 'table-empty=true' <<<"$output"
  grep -Fq "list-releases=$expected_releases" <<<"$output"
}

for mode in count-0 count-1 count-2 count-3 pending sink-error early-drop \
  cancel-before-transfer cancel-after-transfer; do
  run_mode "$mode" 1
done
run_mode count-4 0

printf 'G6.2 scalar list producer canonical ABI probe passed\n'
