#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-c-min-list-resource-producer-generated.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

source="$repo_root/examples/p3-runtime/g6-2-c-min-list-resource-producer.do"
wit="$tmp_dir/generated.wit"
wat="$tmp_dir/generated.wat"
core_wasm="$tmp_dir/generated.core.wasm"
embedded="$tmp_dir/generated.embedded.wasm"
component="$tmp_dir/generated.component.wasm"
bin=do-p3-g6-2-c-min-list-resource-producer-abi

test -x "$do_bin"
test -f "$source"
test -f "$runner_dir/Cargo.toml"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$wat"
test -s "$wat"
grep -Fq '[producer-list-pointer]' "$wat"
grep -Fq '[producer-list-length]' "$wat"
grep -Fq '[producer-list-element-stride]' "$wat"
grep -Fq '[producer-list-ticket-offset]' "$wat"
grep -Fq '[producer-stream-capacity]' "$wat"
grep -Fq '[producer-list-transfer]' "$wat"
grep -Fq '[producer-child-before-parent-cleanup]' "$wat"
grep -Fq 'export produce: async func(mode: u32)' "$wit"

wasm-tools parse "$wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world c-min-producer --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

run_mode() {
  local mode="$1"
  shift
  local output
  output=$(cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$bin" -- "$component" "$mode")
  for expected in "$@"; do
    grep -Fq "$expected" <<<"$output"
  done
  printf '%s\n' "$output"
}

run_mode ready-empty \
  'mode=ready-empty result=Some((Ok(()),)) entries=[]' \
  'resource-created=0 resource-drops=0' 'table-empty=true'
run_mode ready-one \
  'mode=ready-one result=Some((Ok(()),)) entries=[1]' \
  'resource-created=1 resource-drops=0' 'table-empty=true'
run_mode ready-three \
  'mode=ready-three result=Some((Ok(()),)) entries=[1, 2, 3]' \
  'resource-created=3 resource-drops=0' 'table-empty=true'
run_mode pending \
  'mode=pending result=Some((Ok(()),)) entries=[1, 2, 3]' \
  'pending-polls=1' 'table-empty=true'
run_mode sink-error \
  'mode=sink-error result=Some((Err(Pipe),)) entries=[1, 2, 3]' \
  'table-empty=true'
run_mode early-drop \
  'mode=early-drop result=Some((Err(Pipe),)) entries=[1, 2, 3]' \
  'table-empty=true'
run_mode invalid-mode \
  'mode=invalid-mode result=Some((Err(InvalidMode),)) entries=[]' \
  'host-calls=0' 'stream-drops=0' 'resource-created=0' 'table-empty=true'
run_mode cancel-after-transfer \
  'mode=cancel-after-transfer result=None entries=[1, 2, 3]' \
  'resource-created=3' 'resource-drops=0' 'table-empty=true'

cancel_wat="$tmp_dir/cancel-before-transfer.wat"
cancel_core="$tmp_dir/cancel-before-transfer.core.wasm"
cancel_embedded="$tmp_dir/cancel-before-transfer.embedded.wasm"
cancel_component="$tmp_dir/cancel-before-transfer.component.wasm"
sed '/;; \[mode-before-transfer\]/a\
    local.get $frame\
    i32.const 32\
    i32.add\
    i32.load\
    call $subtask-cancel\
    i32.const 4\
    i32.ne\
    if\
      unreachable\
    end\
    local.get $frame\
    i32.const 0\
    i32.const 0\
    call $cleanup\
    return' "$wat" >"$cancel_wat"
wasm-tools parse "$cancel_wat" -o "$cancel_core"
wasm-tools component embed "$wit" "$cancel_core" \
  --world c-min-producer --features cm-async,cm-more-async-builtins -o "$cancel_embedded"
wasm-tools component new --skip-validation "$cancel_embedded" -o "$cancel_component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$cancel_component"
cancel_output=$(cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
  --bin "$bin" -- "$cancel_component" cancel-before-transfer)
grep -Fq 'mode=cancel-before-transfer result=Some((Ok(()),)) entries=[]' <<<"$cancel_output"
grep -Fq 'resource-created=3' <<<"$cancel_output"
grep -Fq 'resource-drops=3' <<<"$cancel_output"
grep -Fq 'table-empty=true' <<<"$cancel_output"
printf '%s\n' "$cancel_output"

printf 'G6.2 C-min producer compiler-generated Component/Rust/Wasmtime gate passed\n'
