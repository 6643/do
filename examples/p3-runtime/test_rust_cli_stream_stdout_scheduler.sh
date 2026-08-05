#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-cli-stream-stdout-scheduler.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_path="$tmp_dir/cli-stream-stdout.wat"
wit_path="$tmp_dir/cli-stream-stdout.wit"
core_wasm="$tmp_dir/cli-stream-stdout.wasm"
component="$tmp_dir/cli-stream-stdout.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
    --p3-wit-output "$wit_path" \
    "$repo_root/examples/p3-runtime/cli-stream-stdout-component.do" \
    -o "$core_path"
grep -Fq '[async-lower]write-via-stream' "$core_path"
grep -Fq '[stream-new-0]write-via-stream' "$core_path"
grep -Fq '[stream-drop-writable-0]write-via-stream' "$core_path"
wasm-tools parse "$core_path" -o "$core_wasm"
bash "$repo_root/examples/p3-runtime/assemble_async_component.sh" \
    "$wit_path" "$core_wasm" stream-stdout-probe "$component"

if ! command -v cc >/dev/null; then
    export CC="$runner_dir/zig-cc.sh"
    export CXX="$runner_dir/zig-cc.sh"
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

run_runner() {
    cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
        --bin do-p3-cli-stream-stdout-host-runner -- "$component"
}

limit64_output=$(DO_STREAM_WRITER_SCHEDULER_LIMIT=64 run_runner)
case "$limit64_output" in
    *"Rust CLI stdout scheduler admission passed limit=64 rejected=1 released=1 host-call-count=2 items=[97, 98, 97, 98]"*) ;;
    *)
        printf 'missing CLI stdout scheduler admission marker\n%s\n' "$limit64_output" >&2
        exit 1
        ;;
esac

limit63_output=$(DO_STREAM_WRITER_SCHEDULER_LIMIT=63 run_runner)
case "$limit63_output" in
    *"Rust CLI stdout scheduler rejected before call limit=63 frame=64 host-call-count=0"*) ;;
    *)
        printf 'missing CLI stdout scheduler early-rejection marker\n%s\n' "$limit63_output" >&2
        exit 1
        ;;
esac

printf 'CLI stdout scheduler admission passed\n'
