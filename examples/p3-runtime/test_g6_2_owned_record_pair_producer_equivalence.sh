#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
wasm_tools_bin=${WASM_TOOLS:-wasm-tools}
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
canonical_wat="$repo_root/examples/p3-runtime/g6-2-owned-record-pair-producer-canonical.wat"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-pair-producer.wit"
source="$repo_root/examples/p3-runtime/g6-2-owned-record-pair-producer.do"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-owned-record-pair-producer-equivalence.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

test -x "$do_bin"
test -f "$canonical_wat"
test -f "$probe_wit"
test -f "$source"
test -f "$runner_dir/Cargo.toml"
command -v "$wasm_tools_bin" >/dev/null 2>&1

expected_tools_version=${WASM_TOOLS_EXPECT_VERSION:-1.255.0}
actual_tools_version=$($wasm_tools_bin --version | awk 'NR == 1 { print $2 }')
test "$actual_tools_version" = "$expected_tools_version"

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
  "$wasm_tools_bin" parse "$wat" -o "$core_wasm"
  "$wasm_tools_bin" component embed "$wit" "$core_wasm" \
    --world owned-record-pair-producer \
    --features cm-async,cm-more-async-builtins \
    -o "$embedded"
  "$wasm_tools_bin" component new --skip-validation "$embedded" -o "$output"
  "$wasm_tools_bin" validate --features cm-async,cm-more-async-builtins "$output"
}

assemble_component "$canonical_wat" "$probe_wit" canonical "$canonical_component"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$generated_wit" -o "$generated_wat"
cmp "$generated_wit" "$probe_wit"
test "$(sha256sum "$generated_wit" | awk '{print $1}')" = \
  89345a5213936735d7f065cd54ed42b83d159b80305a1a900ae00df2e811704d
cmp "$generated_wat" "$canonical_wat"
assemble_component "$generated_wat" "$generated_wit" generated "$generated_component"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-g6-2-owned-record-pair-producer-abi
runner="$runner_dir/target/debug/do-p3-g6-2-owned-record-pair-producer-abi"
test -x "$runner"

modes=(ready pending sink-error-before sink-error-after cancel-before-transfer \
  cancel-after-transfer early-drop-before-transfer early-drop-after-transfer repeat invalid)
for mode in "${modes[@]}"; do
  canonical_output="$tmp_dir/canonical-$mode.out"
  generated_output="$tmp_dir/generated-$mode.out"
  "$runner" "$canonical_component" "$mode" >"$canonical_output"
  "$runner" "$generated_component" "$mode" >"$generated_output"
  diff -u "$canonical_output" "$generated_output"
  grep -Fq "mode=$mode" "$canonical_output"
  grep -Fq 'table-empty=true' "$canonical_output"
  printf 'PASS %s: canonical and generated pair lifecycle observations agree\n' "$mode"
done

printf 'canonical/generated owned-record pair producer equivalence passed modes=10 resources=2/2 drops=2/2 table-empty=true\n'
