#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/list-borrow-canonical-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

test -x "$toolchain_bin"

wat="$repo_root/examples/p3-runtime/list-borrow-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/list-borrow-canonical.wit"
core_wasm="$tmp_dir/list-borrow.core.wasm"
embedded="$tmp_dir/list-borrow.embedded.wasm"
component="$tmp_dir/list-borrow.component.wasm"

test -f "$wat"
test -f "$wit"

"$toolchain_bin" parse-core "$wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" list-borrow-canonical \
  --features none -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features none
"$toolchain_bin" component-wit "$component" | grep -Fq 'read: func(values: list<borrow<ticket>>) -> u32'
test -f "$runner_dir/src/bin/list_borrow_canonical_abi.rs"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

marker_value() {
  local marker="$1"
  awk -v marker="$marker" '
    $0 ~ "^[[:space:]]*;; \\[" marker "\\]$" { want = 1; next }
    want && $1 == "i32.const" { print $2; exit }
    want { exit 1 }
  ' "$wat"
}

list_pointer=$(marker_value 'borrow-list-pointer')
list_stride=$(marker_value 'borrow-list-element-stride')
test "$list_pointer" = 64
test "$list_stride" = 4

run_mode() {
  local mode="$1"
  local expected="$2"
  local output
  output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-list-borrow-canonical-abi -- "$component" "$mode")
  grep -Fq "mode=$mode values=$expected borrow-calls=1" <<<"$output"
  grep -Fq 'owner-drops=1 table-empty=true' <<<"$output"
  grep -Fq "observed-list-pointer=$list_pointer observed-list-element-stride=$list_stride" <<<"$output"
}

run_mode 0 '[]'
run_mode 1 '[111]'
run_mode 3 '[111,111,111]'

printf 'list<borrow<ticket>> canonical ABI matrix passed\n'
