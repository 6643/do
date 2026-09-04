#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
do_bin="$repo_root/bin/do"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"

tmp_root="${TMPDIR:-$repo_root/.tmp/do-tmp}"
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-general-producer-contract.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

test -x "$do_bin"
test -x "$toolchain_bin"
test -f "$DO_TOOLCHAIN_LOCK"
test -f "$runner_dir/Cargo.toml"

# Each delegated gate uses typed parse-core/embed-component/new-component/
# validate-component operations and owns its route-specific lifecycle matrix.
run_gate() {
  local label="$1"
  local script="$2"
  local log="$tmp_dir/$label.log"
  if ! bash "$repo_root/$script" >"$log" 2>&1; then
    printf 'FAIL %s\n' "$label" >&2
    sed -n '1,240p' "$log" >&2
    exit 1
  fi
  printf 'PASS %s: %s\n' "$label" "$(tail -n 1 "$log")"
}

run_gate direct-record examples/p3-runtime/test_g6_2_owned_record_producer_equivalence.sh
run_gate record-pair examples/p3-runtime/test_g6_2_owned_record_pair_producer_equivalence.sh
run_gate parameterized-pair examples/p3-runtime/test_g6_2_owned_record_pair_parameterized_producer_equivalence.sh
run_gate record-triple examples/p3-runtime/test_g6_2_owned_record_triple_producer_equivalence.sh
run_gate nested-record examples/p3-runtime/test_rust_g6_2_owned_record_nested_producer.sh
run_gate list-resource examples/p3-runtime/test_rust_g6_2_c_min_list_resource_producer.sh
run_gate dynamic-list-resource examples/p3-runtime/test_rust_g6_2_c_min_dynamic_list_producer.sh
run_gate batched-list-resource examples/p3-runtime/test_rust_g6_2_batched_list_resource_producer.sh
run_gate scalar-list examples/p3-runtime/test_rust_g6_2_scalar_list_producer.sh

printf 'G6.2 general producer contract gate passed routes=9 canonical-parity=5 lifecycle=9 table-empty=true\n'
