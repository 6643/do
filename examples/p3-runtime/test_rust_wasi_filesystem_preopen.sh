#!/usr/bin/env bash
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
test -x "$toolchain_bin"
"$repo_root/bin/do" build "$repo_root/examples/p3-runtime/wasi-filesystem-preopen.do" --p3-wasi-filesystem-preopen-component --p3-wit-output "$tmp_dir/preopen.wit" -o "$tmp_dir/preopen.wat" >/dev/null
"$toolchain_bin" parse-core "$tmp_dir/preopen.wat" -o "$tmp_dir/preopen.wasm"
"$toolchain_bin" embed-component "$tmp_dir/preopen.wit" "$tmp_dir/preopen.wasm" \
  preopen-probe --features none -o "$tmp_dir/preopen.embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/preopen.embedded.wasm" -o "$tmp_dir/preopen.component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/preopen.component.wasm" --features none
output=$(cd "$repo_root/examples/p3-runtime/rust-host-runner" && CC="$PWD/zig-cc.sh" CXX="$PWD/zig-cc.sh" CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" cargo run --quiet --bin do-p3-wasi-filesystem-preopen-host-runner -- "$tmp_dir/preopen.component.wasm")
for marker in 'Rust WASI filesystem preopen adapter passed' 'preopen create=1' 'preopen open=1' 'preopen sync=1' 'preopen drop=2'; do case "$output" in *"$marker"*) ;; *) printf 'missing marker: %s\n%s\n' "$marker" "$output" >&2; exit 1;; esac; done
