#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-g6-2-owned-record-triple-producer-abi \
  --bin do-p3-g6-2-owned-record-triple-producer

# The canonical ABI gate executes the Rust/Wasmtime binary for every lifecycle
# row after assembling and validating the pinned Component.
bash "$repo_root/examples/p3-runtime/test_g6_2_owned_record_triple_producer_abi.sh"

printf 'G6.2 owned-record triple Rust/Wasmtime lifecycle gate passed modes=10 triple-fields=3 input-words=4 drops=3 table-empty=true\n'
