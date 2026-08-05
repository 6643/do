#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-stream-writer-producer-helper-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
core_path="$tmp_dir/stream-writer-producer-helper.wat"
wit_path="$tmp_dir/stream-writer-producer-helper.wit"
core_wasm="$tmp_dir/stream-writer-producer-helper.wasm"
embedded_path="$tmp_dir/stream-writer-producer-helper.embedded.wasm"
component_path="$tmp_dir/stream-writer-producer-helper.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
  --p3-wit-output "$wit_path" \
  "$repo_root/examples/p3-runtime/stream-probe-guest-producer-helper.do" \
  -o "$core_path"
wasm-tools parse "$core_path" -o "$core_wasm"
wasm-tools component embed "$wit_path" "$core_wasm" \
  --world stream-writer-probe -o "$embedded_path"
wasm-tools component new "$embedded_path" -o "$component_path"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component_path"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

output=$(DO_STREAM_WRITER_VARIANT=custom cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-cli-stream-stdout-host-runner -- "$component_path")
ready=$(DO_STREAM_WRITER_VARIANT=custom DO_STREAM_WRITER_CALLBACK_READY=1 cargo run --quiet \
  --manifest-path "$runner_dir/Cargo.toml" --bin do-p3-cli-stream-stdout-host-runner -- "$component_path")
error_case=$(DO_STREAM_WRITER_VARIANT=custom DO_STREAM_WRITER_ERROR=1 cargo run --quiet \
  --manifest-path "$runner_dir/Cargo.toml" --bin do-p3-cli-stream-stdout-host-runner -- "$component_path")

grep -Fq 'Rust custom stream writer producer passed items=[65, 66] host-call-count=1 stream-dropped=true' <<<"$output"
grep -Fq 'Rust custom stream writer producer immediate passed result=ok host-call-count=1' <<<"$ready"
grep -Fq 'Rust custom stream writer producer error passed result=err:pipe host-call-count=1 stream-dropped=true' <<<"$error_case"

printf 'async-helper producer lease pending/ready/error runtime passed\n'
