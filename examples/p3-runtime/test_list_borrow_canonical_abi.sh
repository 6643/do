#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/list-borrow-canonical-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wasm_tools=${WASM_TOOLS:-wasm-tools}
expected_version=${WASM_TOOLS_EXPECT_VERSION:-1.255.0}
tool_version=$("$wasm_tools" --version)
printf 'wasm-tools=%s\n' "$tool_version"
case "$tool_version" in
  "wasm-tools $expected_version"*) ;;
  *)
    printf 'expected wasm-tools %s, got: %s\n' "$expected_version" "$tool_version" >&2
    exit 1
    ;;
esac

wat="$repo_root/examples/p3-runtime/list-borrow-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/list-borrow-canonical.wit"
core_wasm="$tmp_dir/list-borrow.core.wasm"
embedded="$tmp_dir/list-borrow.embedded.wasm"
component="$tmp_dir/list-borrow.component.wasm"

test -f "$wat"
test -f "$wit"

"$wasm_tools" parse "$wat" -o "$core_wasm"
"$wasm_tools" component embed "$wit" "$core_wasm" \
  --world list-borrow-canonical \
  -o "$embedded"
"$wasm_tools" component new --skip-validation "$embedded" -o "$component"
"$wasm_tools" validate "$component"
"$wasm_tools" component wit "$component" | grep -Fq 'read: func(values: list<borrow<ticket>>) -> u32'
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
