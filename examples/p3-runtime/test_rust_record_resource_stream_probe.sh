#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-record-resource-stream-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/record-resource-stream.wat"
core_wasm="$tmp_dir/record-resource-stream.wasm"
wit="$tmp_dir/record-resource-stream.wit"
embedded="$tmp_dir/record-resource-stream.embedded.wasm"
component="$tmp_dir/record-resource-stream.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/record-resource-stream-probe-component.do" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"
wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world record-resource-stream-probe --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

pending=$(DO_RECORD_RESOURCE_STREAM_COMPLETION=pending cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-record-resource-stream-host-runner -- "$component")
ready=$(DO_RECORD_RESOURCE_STREAM_COMPLETION=ready cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-record-resource-stream-host-runner -- "$component")
error_case=$(DO_RECORD_RESOURCE_STREAM_COMPLETION=error cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-record-resource-stream-host-runner -- "$component")

grep -Fq 'Rust generic record-resource stream pending passed entries=[(1,111),(2,222)] eof=true stream-reads=3 completion-polls=2 pending-wakes=1 resource-created=2 resource-drops=2 stream-drops=1 future-drops=1 table-empty=true result=Ok' <<<"$pending"
grep -Fq 'Rust generic record-resource stream ready passed entries=[(1,111),(2,222)] eof=true stream-reads=3 completion-polls=1 pending-wakes=0 resource-created=2 resource-drops=2 stream-drops=1 future-drops=1 table-empty=true result=Ok' <<<"$ready"
grep -Fq 'Rust generic record-resource stream error passed entries=[(1,111),(2,222)] eof=true stream-reads=3 completion-polls=1 pending-wakes=0 resource-created=2 resource-drops=2 stream-drops=1 future-drops=1 table-empty=true result=Err(io)' <<<"$error_case"

printf 'Rust generic record-resource stream pending/ready/error runtime passed\n'
