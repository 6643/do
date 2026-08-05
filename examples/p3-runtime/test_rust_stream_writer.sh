#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-cli-stream-stdout.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
core_path="$tmp_dir/cli-stream-stdout.wat"
wit_path="$tmp_dir/cli-stream-stdout.wit"
core_wasm="$tmp_dir/cli-stream-stdout.wasm"
component="$tmp_dir/cli-stream-stdout.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
    --p3-wit-output "$wit_path" "$repo_root/examples/p3-runtime/cli-stream-stdout-component.do" \
    -o "$core_path"
wasm-tools parse "$core_path" -o "$core_wasm"
bash "$repo_root/examples/p3-runtime/assemble_async_component.sh" \
    "$wit_path" "$core_wasm" stream-stdout-probe "$component"

if ! command -v cc >/dev/null; then
    export CC="$runner_dir/zig-cc.sh"
    export CXX="$runner_dir/zig-cc.sh"
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-host-runner -- "$component")

immediate_output=$(DO_STREAM_WRITER_CALLBACK_READY=1 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-host-runner -- "$component")

error_output=$(DO_STREAM_WRITER_ERROR=1 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-host-runner -- "$component")

reject_output=$(DO_STREAM_WRITER_SCHEDULER_LIMIT=63 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-host-runner -- "$component")

admit_output=$(DO_STREAM_WRITER_SCHEDULER_LIMIT=64 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-host-runner -- "$component")

case "$output" in
    *"Rust CLI stdout stream execution passed items=[97, 98] host-call-count=1 stream-dropped=true"*) ;;
    *) printf 'missing CLI stdout runtime success marker\n%s\n' "$output" >&2; exit 1 ;;
esac

case "$immediate_output" in
    *"Rust CLI stdout stream immediate callback passed result=ok host-call-count=1"*) ;;
    *) printf 'missing CLI stdout immediate callback success marker\n%s\n' "$immediate_output" >&2; exit 1 ;;
esac

case "$error_output" in
    *"Rust CLI stdout stream error callback passed result=err:pipe host-call-count=1"*) ;;
    *) printf 'missing CLI stdout error callback marker\n%s\n' "$error_output" >&2; exit 1 ;;
esac

case "$reject_output" in
    *"Rust CLI stdout scheduler rejected before call limit=63 frame=64 host-call-count=0"*) ;;
    *) printf 'missing CLI stdout scheduler rejection marker\n%s\n' "$reject_output" >&2; exit 1 ;;
esac

case "$admit_output" in
    *"Rust CLI stdout scheduler admission passed limit=64 rejected=1 released=1 host-call-count=2 items=[97, 98, 97, 98]"*) ;;
    *) printf 'missing CLI stdout scheduler admission marker\n%s\n' "$admit_output" >&2; exit 1 ;;
esac
