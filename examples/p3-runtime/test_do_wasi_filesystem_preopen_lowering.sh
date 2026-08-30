#!/usr/bin/env bash
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
"$repo_root/bin/do" build "$repo_root/examples/p3-runtime/wasi-filesystem-preopen.do" --p3-wasi-filesystem-preopen-component --p3-wit-output "$tmp_dir/preopen.wit" -o "$tmp_dir/preopen.wat" >/dev/null
grep -Fq 'get-directories: func() -> list<tuple<own<descriptor>, string>>' "$tmp_dir/preopen.wit"
grep -Fq 'open-at: func(path-flags: u32, path: string, open-flags: u32, descriptor-flags: u32) -> result<own<descriptor>, error-code>' "$tmp_dir/preopen.wit"
grep -Fq 'sync: func() -> result<_, error-code>' "$tmp_dir/preopen.wit"
grep -Fq '[method]descriptor.open-at' "$tmp_dir/preopen.wat"
grep -Fq '[resource-drop]descriptor' "$tmp_dir/preopen.wat"
"$toolchain_bin" parse-core "$tmp_dir/preopen.wat" -o "$tmp_dir/preopen.wasm"
"$toolchain_bin" embed-component "$tmp_dir/preopen.wit" "$tmp_dir/preopen.wasm" preopen-probe -o "$tmp_dir/preopen.embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/preopen.embedded.wasm" -o "$tmp_dir/preopen.component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/preopen.component.wasm"
sed 's/return 1/return 2/' "$repo_root/examples/p3-runtime/wasi-filesystem-preopen.do" >"$tmp_dir/changed.do"
if "$repo_root/bin/do" build "$tmp_dir/changed.do" --p3-wasi-filesystem-preopen-component -o "$tmp_dir/changed.wat" >"$tmp_dir/stdout" 2>"$tmp_dir/stderr"; then exit 1; fi
grep -Fq 'UnsupportedWasiFilesystemPreopenComponent' "$tmp_dir/stderr"
