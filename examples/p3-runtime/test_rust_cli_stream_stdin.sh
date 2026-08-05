#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-cli-stream-stdin.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
core_path="$tmp_dir/cli-stream-stdin.wat"
wit_path="$tmp_dir/cli-stream-stdin.wit"
core_wasm="$tmp_dir/cli-stream-stdin.wasm"
embedded="$tmp_dir/cli-stream-stdin.embedded.wasm"
component="$tmp_dir/cli-stream-stdin.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
    --p3-wit-output "$wit_path" "$repo_root/examples/p3-runtime/cli-stream-stdin-component.do" \
    -o "$core_path"
sed -i '/^  export run:/i\\  export byte-budget-limit: func(limit: s64) -> s32;' "$wit_path"
wasm-tools parse "$core_path" -o "$core_wasm"
wasm-tools component embed "$wit_path" "$core_wasm" --world stream-stdin-probe -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

if ! command -v cc >/dev/null; then
    export CC="$runner_dir/zig-cc.sh"
    export CXX="$runner_dir/zig-cc.sh"
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

output=$(cargo run --quiet --manifest-path "$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml" \
    --bin do-p3-cli-stream-stdin-host-runner -- "$component")

ready_output=$(DO_STREAM_COMPLETION_READY=1 cargo run --quiet \
    --manifest-path "$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml" \
    --bin do-p3-cli-stream-stdin-host-runner -- "$component")

scheduler_output=$(DO_CLI_STDIN_SCHEDULER_LIMIT=32 cargo run --quiet \
    --manifest-path "$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml" \
    --bin do-p3-cli-stream-stdin-host-runner -- "$component")

scheduler_reject_output=$(DO_CLI_STDIN_SCHEDULER_LIMIT=31 cargo run --quiet \
    --manifest-path "$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml" \
    --bin do-p3-cli-stream-stdin-host-runner -- "$component")

budget_output=$(DO_CLI_STDIN_BUDGET_LIMIT=32 cargo run --quiet \
    --manifest-path "$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml" \
    --bin do-p3-cli-stream-stdin-host-runner -- "$component")

budget_reject_output=$(DO_CLI_STDIN_BUDGET_LIMIT=31 \
    DO_CLI_STDIN_BUDGET_EXPECT_REJECT=1 cargo run --quiet \
    --manifest-path "$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml" \
    --bin do-p3-cli-stream-stdin-host-runner -- "$component")

case "$output" in
    *"Rust CLI stdin stream execution passed items=[97, 98] eof=true completion-unread-dropped=true stream-dropped=true future-dropped=true"*) ;;
    *) printf 'missing CLI stdin runtime success marker\n%s\n' "$output" >&2; exit 1 ;;
esac

case "$ready_output" in
    *"Rust CLI stdin stream execution passed items=[97, 98] eof=true completion-unread-dropped=true stream-dropped=true future-dropped=true"*) ;;
    *) printf 'missing CLI stdin ready-future runtime success marker\n%s\n' "$ready_output" >&2; exit 1 ;;
esac

case "$scheduler_output" in
    *"Rust CLI stdin scheduler admission passed limit=32 rejected=1 released=1 provider-call-count=2 items=[97, 98, 97, 98]"*) ;;
    *) printf 'missing CLI stdin scheduler admission marker\n%s\n' "$scheduler_output" >&2; exit 1 ;;
esac

case "$scheduler_reject_output" in
    *"Rust CLI stdin scheduler rejected before call limit=31 frame=32 provider-call-count=0"*) ;;
    *) printf 'missing CLI stdin scheduler rejection marker\n%s\n' "$scheduler_reject_output" >&2; exit 1 ;;
esac

case "$budget_output" in
    *"Rust CLI stdin budget adapter passed limit=32 configured=1 frame=32 provider-call-count=1"*) ;;
    *) printf 'missing CLI stdin budget success marker\n%s\n' "$budget_output" >&2; exit 1 ;;
esac

case "$budget_reject_output" in
    *"Rust CLI stdin budget adapter rejected limit=31 frame=32 provider-call-count=0"*) ;;
    *) printf 'missing CLI stdin budget rejection marker\n%s\n' "$budget_reject_output" >&2; exit 1 ;;
esac
