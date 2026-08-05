#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

root="$tmp_dir/root"
mkdir -p "$root"
printf 'd2-probe-bytes\n' >"$root/probe"

wat="$tmp_dir/preopen.wat"
wit="$tmp_dir/preopen.wit"
core="$tmp_dir/preopen.core.wasm"
embedded="$tmp_dir/preopen.embedded.wasm"
component="$tmp_dir/preopen.component.wasm"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/wasi-filesystem-preopen.do" \
  --p3-wasi-filesystem-preopen-component --p3-wit-output "$wit" -o "$wat"
wasm-tools parse "$wat" -o "$core"
wasm-tools component embed "$wit" "$core" --world preopen-probe -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate "$component"

runner_env=(
  CC="$runner_dir/zig-cc.sh"
  CXX="$runner_dir/zig-cc.sh"
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
  DO_D2_FILESYSTEM_ROOT="$root"
)
output=$(cd "$runner_dir" && env "${runner_env[@]}" cargo run --quiet --bin do-p3-wasi-filesystem-real -- "$component")
grep -Fq 'real-filesystem passed missing=false create=1 open=1 sync=1 drop=2' <<<"$output"
grep -Fq 'bytes=15' <<<"$output"
grep -Fq 'table-empty=true' <<<"$output"

missing_output=$(cd "$runner_dir" && env "${runner_env[@]}" DO_D2_FILESYSTEM_MISSING=1 \
  cargo run --quiet --bin do-p3-wasi-filesystem-real -- "$component")
grep -Fq 'real-filesystem passed missing=true create=1 open=0 sync=0 drop=1' <<<"$missing_output"
grep -Fq 'table-empty=true' <<<"$missing_output"

printf 'D2 real filesystem preopen/open/sync passed\n'
