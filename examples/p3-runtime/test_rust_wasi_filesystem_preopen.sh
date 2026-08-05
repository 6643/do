#!/usr/bin/env bash
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
"$repo_root/bin/do" build "$repo_root/examples/p3-runtime/wasi-filesystem-preopen.do" --p3-wasi-filesystem-preopen-component --p3-wit-output "$tmp_dir/preopen.wit" -o "$tmp_dir/preopen.wat" >/dev/null
wasm-tools parse "$tmp_dir/preopen.wat" -o "$tmp_dir/preopen.wasm"
wasm-tools component embed "$tmp_dir/preopen.wit" --world preopen-probe -o "$tmp_dir/preopen.embedded.wasm" "$tmp_dir/preopen.wasm"
wasm-tools component new -o "$tmp_dir/preopen.component.wasm" "$tmp_dir/preopen.embedded.wasm"
output=$(cd "$repo_root/examples/p3-runtime/rust-host-runner" && CC="$PWD/zig-cc.sh" CXX="$PWD/zig-cc.sh" CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" cargo run --quiet --bin do-p3-wasi-filesystem-preopen-host-runner -- "$tmp_dir/preopen.component.wasm")
for marker in 'Rust WASI filesystem preopen adapter passed' 'preopen create=1' 'preopen open=1' 'preopen sync=1' 'preopen drop=2'; do case "$output" in *"$marker"*) ;; *) printf 'missing marker: %s\n%s\n' "$marker" "$output" >&2; exit 1;; esac; done
