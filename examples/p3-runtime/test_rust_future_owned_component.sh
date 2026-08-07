#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
component=${1:?usage: $0 <component.wasm>}
cargo_bin=${CARGO_BIN:-cargo}

test -f "$component"
test -f "$runner_dir/Cargo.toml"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

run_mode() {
  local mode="$1"
  local expected="$2"
  local output
  output=$("$cargo_bin" run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-future-owned-canonical-abi -- "$component" "$mode")
  grep -Fq "$expected" <<<"$output"
  grep -Fq 'observed-payload-offset=12' <<<"$output"
  grep -Fq 'observed-ticket-present-offset=20' <<<"$output"
  printf '%s\n' "$output"
}

run_mode ready \
  'mode=ready host-calls=1 polls=1 wakes=0 cancel-calls=0 future-drops=1 pending-future-drops=0 resource-created=1 resource-drops=1 table-empty=true'
run_mode pending \
  'mode=pending host-calls=1 polls=2 wakes=1 cancel-calls=0 future-drops=1 pending-future-drops=0 resource-created=1 resource-drops=1 table-empty=true'
run_mode cancel \
  'mode=cancel host-calls=1 polls=1 wakes=0 cancel-calls=1 future-drops=1 pending-future-drops=1 resource-created=0 resource-drops=0 table-empty=true'

printf 'rust future<own<ticket>> compiler Component runtime gate passed\n'
