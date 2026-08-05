#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-cli-stream-stdout-budget.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
core_path="$tmp_dir/cli-stream-stdout.wat"
wit_path="$tmp_dir/cli-stream-stdout.wit"
core_wasm="$tmp_dir/cli-stream-stdout.wasm"
embedded="$tmp_dir/cli-stream-stdout.embedded.wasm"
component="$tmp_dir/cli-stream-stdout.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
    --p3-wit-output "$wit_path" \
    "$repo_root/examples/p3-runtime/cli-stream-stdout-component.do" \
    -o "$core_path"
grep -Fq ';; [async-frame-budget-bytes] 64' "$core_path"
grep -Fq '(export "byte-budget-limit")' "$core_path"
sed -i '/^  export write:/i\\  export byte-budget-limit: func(limit: s64) -> s32;' "$wit_path"
wasm-tools parse "$core_path" -o "$core_wasm"
wasm-tools component embed "$wit_path" "$core_wasm" \
    --world stream-stdout-probe --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

if ! command -v cc >/dev/null; then
    export CC="$runner_dir/zig-cc.sh"
    export CXX="$runner_dir/zig-cc.sh"
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

success_output=$(DO_STREAM_WRITER_BUDGET_LIMIT=64 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-host-runner -- "$component")
case "$success_output" in
    *"Rust CLI stdout budget adapter passed limit=64 configured=1 frame=64 host-call-count=1"*) ;;
    *)
        printf 'missing CLI stdout budget success marker\n%s\n' "$success_output" >&2
        exit 1
        ;;
esac

rejected_output=$(DO_STREAM_WRITER_BUDGET_LIMIT=63 \
    DO_STREAM_WRITER_BUDGET_EXPECT_REJECT=1 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-cli-stream-stdout-host-runner -- "$component")
case "$rejected_output" in
    *"Rust CLI stdout budget adapter rejected limit=63 frame=64 host-call-count=0"*) ;;
    *)
        printf 'missing CLI stdout budget rejection marker\n%s\n' "$rejected_output" >&2
        exit 1
        ;;
esac

printf 'CLI stdout private budget adapter passed\n'
