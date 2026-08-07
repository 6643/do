#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-c-min-dynamic-list-resource-producer-generated.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

source="$repo_root/examples/p3-runtime/g6-2-c-min-dynamic-list-resource-producer.do"
wit="$tmp_dir/generated.wit"
wat="$tmp_dir/generated.wat"
core_wasm="$tmp_dir/generated.core.wasm"
embedded="$tmp_dir/generated.embedded.wasm"
component="$tmp_dir/generated.component.wasm"
bin=do-p3-g6-2-c-min-dynamic-list-producer

test -x "$do_bin"
test -f "$source"
test -f "$runner_dir/Cargo.toml"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$wat"
test -s "$wat"
grep -Fq '[producer-plan-layout] pointer=64 length=68 stride=4 ticket-offset=0 capacity=1' "$wat"
grep -Fq '[producer-list-transfer]' "$wat"
grep -Fq '[producer-child-before-parent-cleanup]' "$wat"
grep -Fq 'export produce: async func(count: u32)' "$wit"

wasm-tools parse "$wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world dynamic-list-producer --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

test -f "$runner_dir/src/bin/g6_2_c_min_dynamic_list_producer.rs"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

run_case() {
  local count="$1"
  local mode="$2"
  shift 2
  local output
  output=$(cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$bin" -- "$component" "$count" "$mode")
  for expected in "$@"; do
    grep -Fq "$expected" <<<"$output"
  done
  printf '%s\n' "$output"
}

run_case 0 ready \
  'count=0 mode=ready result=Some((Ok(()),)) entries=[]' \
  'resource-created=0 resource-drops=0' 'table-empty=true'
run_case 1 ready \
  'count=1 mode=ready result=Some((Ok(()),)) entries=[1]' \
  'resource-created=1 resource-drops=0' 'table-empty=true'
run_case 2 ready \
  'count=2 mode=ready result=Some((Ok(()),)) entries=[1, 2]' \
  'resource-created=2 resource-drops=0' 'table-empty=true'
run_case 3 ready \
  'count=3 mode=ready result=Some((Ok(()),)) entries=[1, 2, 3]' \
  'resource-created=3 resource-drops=0' 'table-empty=true'
run_case 3 pending \
  'count=3 mode=pending result=Some((Ok(()),)) entries=[1, 2, 3]' \
  'pending-polls=1' 'table-empty=true'
run_case 3 sink-error \
  'count=3 mode=sink-error result=Some((Err(Pipe),)) entries=[1, 2, 3]' \
  'table-empty=true'
run_case 3 early-drop \
  'count=3 mode=early-drop result=Some((Err(Pipe),)) entries=[1, 2, 3]' \
  'stream-drops=1' 'table-empty=true'
run_case 4 invalid-mode \
  'count=4 mode=invalid-mode result=Some((Err(InvalidMode),)) entries=[]' \
  'host-calls=0' 'resource-created=0' 'stream-drops=0' 'table-empty=true'
run_case 3 cancel-after-transfer \
  'count=3 mode=cancel-after-transfer result=None entries=[1, 2, 3]' \
  'resource-created=3' 'resource-drops=0' 'table-empty=true'

build_variant() {
  local mode="$1"
  local variant="$tmp_dir/$mode.wat"
  local variant_core="$tmp_dir/$mode.core.wasm"
  local variant_embedded="$tmp_dir/$mode.embedded.wasm"
  local variant_component="$tmp_dir/$mode.component.wasm"

  case "$mode" in
    cancel-before-transfer)
      test "$(rg -c '^\s*;; \[mode-before-transfer\]$' "$wat")" = 1
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
    return' "$wat" >"$variant"
      ;;
    source-failure)
      test "$(rg -c '^\s*;; \[mode-before-ticket-3\]$' "$wat")" = 1
      sed '/;; \[mode-before-ticket-3\]/a\
    local.get $index\
    i32.const 2\
    i32.eq\
    if\
      i32.const -2\
      return\
    end' "$wat" >"$variant"
      ;;
    *)
      printf 'unknown dynamic producer variant: %s\n' "$mode" >&2
      return 2
      ;;
  esac

  wasm-tools parse "$variant" -o "$variant_core"
  wasm-tools component embed "$wit" "$variant_core" \
    --world dynamic-list-producer --features cm-async,cm-more-async-builtins -o "$variant_embedded"
  wasm-tools component new --skip-validation "$variant_embedded" -o "$variant_component"
  wasm-tools validate --features cm-async,cm-more-async-builtins "$variant_component"
  printf '%s\n' "$variant_component"
}

cancel_before_component=$(build_variant cancel-before-transfer)
cancel_before_output=$(cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
  --bin "$bin" -- "$cancel_before_component" 3 cancel-before-transfer)
grep -Fq 'count=3 mode=cancel-before-transfer result=Some((Ok(()),)) entries=[]' <<<"$cancel_before_output"
grep -Fq 'resource-created=3 resource-drops=3' <<<"$cancel_before_output"
grep -Fq 'table-empty=true' <<<"$cancel_before_output"
printf '%s\n' "$cancel_before_output"

source_failure_component=$(build_variant source-failure)
source_failure_output=$(cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
  --bin "$bin" -- "$source_failure_component" 3 source-failure)
grep -Fq 'count=3 mode=source-failure result=Some((Err(Io),)) entries=[]' <<<"$source_failure_output"
grep -Fq 'resource-created=2 resource-drops=2' <<<"$source_failure_output"
grep -Fq 'table-empty=true' <<<"$source_failure_output"
printf '%s\n' "$source_failure_output"

printf 'G6.2 bounded dynamic list producer compiler-generated Component/Rust/Wasmtime gate passed\n'
