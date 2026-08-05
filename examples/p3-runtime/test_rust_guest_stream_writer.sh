#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-guest-stream-writer.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
core_path="$tmp_dir/guest-stream-writer.wat"
wit_path="$tmp_dir/guest-stream-writer.wit"
core_wasm="$tmp_dir/guest-stream-writer.wasm"
component="$tmp_dir/guest-stream-writer.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
    --p3-wit-output "$wit_path" \
    "$repo_root/examples/p3-runtime/cli-stream-stdout-guest-producer.do" \
    -o "$core_path"
sed -i '/^  export produce:/i\\  export byte-budget-limit: func(limit: s64) -> s32;' "$wit_path"
wasm-tools parse "$core_path" -o "$core_wasm"
bash "$repo_root/examples/p3-runtime/assemble_async_component.sh" \
    "$wit_path" "$core_wasm" stream-stdout-probe "$component"

if ! command -v cc >/dev/null; then
    export CC="$runner_dir/zig-cc.sh"
    export CXX="$runner_dir/zig-cc.sh"
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-guest-producer-host-runner -- "$component")

drop_output=$(DO_STREAM_WRITER_DROP_AFTER_FIRST=1 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-guest-producer-host-runner -- "$component")

error_output=$(DO_STREAM_WRITER_ERROR=1 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-guest-producer-host-runner -- "$component")

scheduler_output=$(DO_STREAM_WRITER_SCHEDULER_LIMIT=64 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-guest-producer-host-runner -- "$component")

scheduler_reject_output=$(DO_STREAM_WRITER_SCHEDULER_LIMIT=63 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-guest-producer-host-runner -- "$component")

budget_output=$(DO_STREAM_WRITER_BUDGET_LIMIT=64 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-guest-producer-host-runner -- "$component")

budget_reject_output=$(DO_STREAM_WRITER_BUDGET_LIMIT=63 \
    DO_STREAM_WRITER_BUDGET_EXPECT_REJECT=1 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-guest-producer-host-runner -- "$component")

case "$output" in
    *"Rust guest producer stream execution passed items=[65, 66, 67] host-call-count=1 pending-writes=1 writer-closed=true reader-drops=1"*) ;;
    *)
        printf 'missing guest producer runtime success marker\n%s\n' "$output" >&2
        exit 1
        ;;
esac

case "$drop_output" in
    *"Rust guest producer early reader drop passed items=[65] host-call-count=1 pending-writes=1 writer-closed=true reader-drops=1"*) ;;
    *)
        printf 'missing guest producer early-drop runtime success marker\n%s\n' "$drop_output" >&2
        exit 1
        ;;
esac

case "$error_output" in
    *"Rust guest producer host error passed result=err:pipe items=[65, 66, 67] host-call-count=1 pending-writes=1 writer-closed=true reader-drops=1"*) ;;
    *)
        printf 'missing guest producer host-error runtime success marker\n%s\n' "$error_output" >&2
        exit 1
        ;;
esac

case "$scheduler_output" in
    *"Rust guest producer scheduler admission passed limit=64 rejected=1 released=1 host-call-count=2 items=[65, 66, 67, 65, 66, 67]"*) ;;
    *)
        printf 'missing guest producer scheduler admission marker\n%s\n' "$scheduler_output" >&2
        exit 1
        ;;
esac

case "$scheduler_reject_output" in
    *"Rust guest producer scheduler rejected before call limit=63 frame=64 host-call-count=0"*) ;;
    *)
        printf 'missing guest producer scheduler early-rejection marker\n%s\n' "$scheduler_reject_output" >&2
        exit 1
        ;;
esac

case "$budget_output" in
    *"Rust guest producer budget adapter passed limit=64 configured=1 frame=64 host-call-count=1"*) ;;
    *)
        printf 'missing guest producer budget success marker\n%s\n' "$budget_output" >&2
        exit 1
        ;;
esac

case "$budget_reject_output" in
    *"Rust guest producer budget adapter rejected limit=63 frame=64 host-call-count=0"*) ;;
    *)
        printf 'missing guest producer budget rejection marker\n%s\n' "$budget_reject_output" >&2
        exit 1
        ;;
esac
