#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-stream-reader.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
core_path="$tmp_dir/stream-probe.wat"
wit_path="$tmp_dir/stream-probe.wit"
core_wasm="$tmp_dir/stream-probe.wasm"
embedded="$tmp_dir/stream-probe.embedded.wasm"
component="$tmp_dir/stream-probe.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
    --p3-wit-output "$wit_path" "$repo_root/examples/p3-runtime/stream-probe-component.do" \
    -o "$core_path"
wasm-tools parse "$core_path" -o "$core_wasm"
wasm-tools component embed "$wit_path" "$core_wasm" --world stream-probe -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

if ! command -v cc >/dev/null; then
    export CC="$runner_dir/zig-cc.sh"
    export CXX="$runner_dir/zig-cc.sh"
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-stream-reader-host-runner -- "$component")
case "$output" in
    *"Rust custom stream reader execution passed items=[97, 98] eof=true completion-unread-dropped=true stream-drops=1 future-drops=1"*) ;;
    *) printf 'missing custom stream reader runtime success marker\n%s\n' "$output" >&2; exit 1 ;;
esac
