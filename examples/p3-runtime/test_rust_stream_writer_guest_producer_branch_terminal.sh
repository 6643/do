#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-stream-writer-branch-terminal-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_path="$tmp_dir/branch-terminal.wat"
wit_path="$tmp_dir/branch-terminal.wit"
core_wasm="$tmp_dir/branch-terminal.core.wasm"
component_path="$tmp_dir/branch-terminal.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
  --p3-wit-output "$wit_path" \
  "$repo_root/examples/p3-runtime/stream-probe-guest-producer-branch-terminal.do" \
  -o "$core_path"
cmp "$wit_path" "$repo_root/examples/p3-runtime/wit/stream-probe-guest-producer-branch-terminal.wit"
wasm-tools parse "$core_path" -o "$core_wasm"
bash "$repo_root/examples/p3-runtime/assemble_async_component.sh" \
  "$wit_path" "$core_wasm" stream-writer-probe "$component_path"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component_path"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

for mode in pending ready abort; do
  cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-stream-probe-guest-producer-dynamic-host-runner \
    -- "$component_path" "$mode" branch-terminal
done

printf 'branch terminal producer pending/ready/abort runtime passed\n'
