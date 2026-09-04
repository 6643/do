#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-owned-record-nested-equivalence.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

source="$repo_root/examples/p3-runtime/g6-2-owned-record-nested-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-nested-producer.wit"
canonical_wat="$repo_root/examples/p3-runtime/g6-2-owned-record-nested-producer-canonical.wat"
generated_wat="$tmp_dir/generated.wat"
generated_wit="$tmp_dir/generated.wit"
canonical_core="$tmp_dir/canonical.core.wasm"
canonical_embedded="$tmp_dir/canonical.embedded.wasm"
canonical_component="$tmp_dir/canonical.component.wasm"
generated_core="$tmp_dir/generated.core.wasm"
generated_embedded="$tmp_dir/generated.embedded.wasm"
generated_component="$tmp_dir/generated.component.wasm"

test -x "$do_bin"
test -x "$toolchain_bin"
test -f "$source"
test -f "$probe_wit"
test -f "$canonical_wat"
test -f "$runner_dir/Cargo.toml"
test -f "$runner_dir/src/bin/g6_2_owned_record_nested_producer.rs"
assemble_component() {
  local wat="$1"
  local wit="$2"
  local core="$3"
  local embedded="$4"
  local component="$5"
  "$toolchain_bin" parse-core "$wat" -o "$core"
  "$toolchain_bin" embed-component "$wit" "$core" owned-record-nested-producer \
    --features component-async -o "$embedded"
  "$toolchain_bin" new-component "$embedded" -o "$component"
  "$toolchain_bin" validate-component "$component" --features component-async
}

assemble_component "$canonical_wat" "$probe_wit" "$canonical_core" \
  "$canonical_embedded" "$canonical_component"
DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$generated_wit" -o "$generated_wat"
cmp "$generated_wit" "$probe_wit"
cmp "$generated_wat" "$canonical_wat"
assemble_component "$generated_wat" "$generated_wit" "$generated_core" \
  "$generated_embedded" "$generated_component"

if grep -Fq '__arc_' "$generated_wat" || grep -Fq '__arc_' "$canonical_wat"; then
  printf 'owned-record nested parity contains an ARC symbol\n' >&2
  exit 1
fi
if rg -n 'ref\.null|struct\.new|array\.new' "$generated_wat" "$canonical_wat"; then
  printf 'owned-record nested parity crosses a Wasm GC reference boundary\n' >&2
  exit 1
fi

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=g6_2_owned_record_nested_producer
cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" --bin "$bin"
runner="$runner_dir/target/debug/$bin"
test -x "$runner"

for mode in ready pending sink-error-before sink-error-after \
  cancel-before-transfer cancel-after-transfer early-drop-before-transfer \
  early-drop-after-transfer repeat invalid; do
  "$runner" "$canonical_component" "$mode" >"$tmp_dir/canonical.$mode"
  "$runner" "$generated_component" "$mode" >"$tmp_dir/generated.$mode"
  cmp "$tmp_dir/canonical.$mode" "$tmp_dir/generated.$mode"
done

printf 'G6.2 owned-record nested canonical/generated equivalence gate passed artifacts=byte-identical lifecycle-modes=10\n'
