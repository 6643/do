#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/future-owned-canonical-abi.XXXXXX")
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

wat="$repo_root/examples/p3-runtime/future-owned-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/future-owned-canonical.wit"
core_wasm="$tmp_dir/future-owned.core.wasm"
embedded="$tmp_dir/future-owned.embedded.wasm"
component="$tmp_dir/future-owned.component.wasm"

test -f "$wat"
test -f "$wit"
test -f "$runner_dir/src/bin/future_owned_canonical_abi.rs"

"$wasm_tools" parse "$wat" -o "$core_wasm"
"$wasm_tools" component embed "$wit" "$core_wasm" \
  --world future-owned-canonical \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
"$wasm_tools" component new --skip-validation "$embedded" -o "$component"
"$wasm_tools" validate --features cm-async,cm-more-async-builtins "$component"
"$wasm_tools" component wit "$component" | grep -Fq 'read: func() -> future<ticket>'
"$wasm_tools" component wit "$component" | grep -Fq 'run: async func(mode: u32)'

marker_value() {
  local marker="$1"
  awk -v marker="$marker" '
    $0 ~ "^[[:space:]]*;; \\[" marker "\\]$" { want = 1; next }
    want && $1 == "i32.const" { print $2; exit }
    want { exit 1 }
  ' "$wat"
}

payload_offset=$(marker_value 'future-owned-payload')
test "$payload_offset" = 12
ticket_present_offset=$(marker_value 'future-owned-ticket-present')
test "$ticket_present_offset" = 20

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

run_mode() {
  local mode="$1"
  local expected="$2"
  local output
  output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-future-owned-canonical-abi -- "$component" "$mode")
  grep -Fq "$expected" <<<"$output"
  grep -Fq "observed-payload-offset=$payload_offset" <<<"$output"
  grep -Fq "observed-ticket-present-offset=$ticket_present_offset" <<<"$output"
}

run_mode 0 'mode=ready host-calls=1 polls=1 wakes=0 cancel-calls=0 future-drops=1 pending-future-drops=0 resource-created=1 resource-drops=1 table-empty=true'
run_mode 1 'mode=pending host-calls=1 polls=2 wakes=1 cancel-calls=0 future-drops=1 pending-future-drops=0 resource-created=1 resource-drops=1 table-empty=true'
run_mode 2 'mode=cancel host-calls=1 polls=1 wakes=0 cancel-calls=1 future-drops=1 pending-future-drops=1 resource-created=0 resource-drops=0 table-empty=true'

printf 'future<own<ticket>> canonical ABI/runtime matrix passed\n'
