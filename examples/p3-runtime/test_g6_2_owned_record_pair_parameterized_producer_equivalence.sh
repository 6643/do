#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
canonical_wat="$repo_root/examples/p3-runtime/g6-2-owned-record-pair-parameterized-producer-canonical.wat"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-pair-parameterized-producer.wit"
source="$repo_root/examples/p3-runtime/g6-2-owned-record-pair-parameterized-producer.do"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-owned-record-pair-parameterized-equivalence.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

test -x "$do_bin"
test -x "$toolchain_bin"
test -f "$canonical_wat"
test -f "$probe_wit"
test -f "$source"
test -f "$runner_dir/Cargo.toml"
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
  "$toolchain_bin" parse-core "$wat" -o "$core_wasm"
  "$toolchain_bin" embed-component "$wit" "$core_wasm" owned-record-pair-parameterized-producer \
    --features component-async -o "$embedded"
  "$toolchain_bin" new-component "$embedded" -o "$output"
  "$toolchain_bin" validate-component "$output" --features component-async
}

assemble_component "$canonical_wat" "$probe_wit" canonical "$canonical_component"
DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$generated_wit" -o "$generated_wat"
cmp "$generated_wit" "$probe_wit"
test "$(sha256sum "$generated_wit" | awk '{print $1}')" = \
  e7abd3cf7b7543325865a0b4be4b32ae50a2470ac5083169250719f89b7ce53a
cmp "$generated_wat" "$canonical_wat"
assemble_component "$generated_wat" "$generated_wit" generated "$generated_component"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-g6-2-owned-record-pair-parameterized-producer-abi
cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" --bin "$bin"
runner="$runner_dir/target/debug/$bin"
test -x "$runner"

run_equivalent() {
  local mode="$1"
  local left_seed="$2"
  local right_seed="$3"
  local canonical_output="$tmp_dir/canonical-$mode.out"
  local generated_output="$tmp_dir/generated-$mode.out"
  "$runner" "$canonical_component" "$mode" "$left_seed" "$right_seed" >"$canonical_output"
  "$runner" "$generated_component" "$mode" "$left_seed" "$right_seed" >"$generated_output"
  diff -u "$canonical_output" "$generated_output"
  grep -Fq "mode=$mode" "$canonical_output"
  grep -Fq 'table-empty=true' "$canonical_output"
  printf 'PASS %s: canonical and generated parameterized pair lifecycle observations agree\n' "$mode"
}

run_equivalent ready 111 222
run_equivalent pending 0 4294967295
run_equivalent sink-error-before 333 444
run_equivalent sink-error-after 555 666
run_equivalent cancel-before-transfer 777 888
run_equivalent cancel-after-transfer 999 1000
run_equivalent early-drop-before-transfer 1234 5678
run_equivalent early-drop-after-transfer 42 43
run_equivalent repeat 111 222
run_equivalent invalid 9 10

printf 'canonical/generated parameterized owned-record pair equivalence passed modes=10 pair-fields=2 input-words=3 table-empty=true\n'
