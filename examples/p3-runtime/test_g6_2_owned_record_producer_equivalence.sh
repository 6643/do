#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
canonical_wat="$repo_root/examples/p3-runtime/g6-2-owned-record-producer-canonical.wat"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-producer.wit"
source="$repo_root/examples/p3-runtime/g6-2-owned-record-producer.do"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-owned-record-producer-equivalence.XXXXXX")
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
  local core_wasm="$tmp_dir/$stem.core.wasm"
  local embedded="$tmp_dir/$stem.embedded.wasm"
  "$toolchain_bin" parse-core "$wat" -o "$core_wasm"
  "$toolchain_bin" embed-component "$wit" "$core_wasm" owned-record-producer \
    --features component-async -o "$embedded"
  "$toolchain_bin" new-component "$embedded" -o "$4"
  "$toolchain_bin" validate-component "$4" --features component-async
}

assemble_component "$canonical_wat" "$probe_wit" canonical "$canonical_component"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$generated_wit" -o "$generated_wat"
cmp "$generated_wit" "$probe_wit"
test "$(sha256sum "$generated_wit" | awk '{print $1}')" = \
  6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace
assemble_component "$generated_wat" "$generated_wit" generated "$generated_component"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-g6-2-owned-record-producer-abi
runner="$runner_dir/target/debug/do-p3-g6-2-owned-record-producer-abi"
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
  printf 'PASS %s: canonical and generated lifecycle observations agree\n' "$mode"
done

printf 'canonical/generated direct owned-record producer equivalence passed modes=10 resources=1/1 drops=1/1 table-empty=true\n'
