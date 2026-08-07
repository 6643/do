#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-c-min-list-resource-producer.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wat="$repo_root/examples/p3-runtime/g6-2-c-min-list-resource-producer-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/g6-2-c-min-list-resource-producer.wit"
core_wasm="$tmp_dir/canonical.core.wasm"
embedded="$tmp_dir/canonical.embedded.wasm"
component="$tmp_dir/canonical.component.wasm"

test -f "$wat"
test -f "$wit"
test -f "$runner_dir/src/bin/g6_2_c_min_list_resource_producer_abi.rs"

wasm-tools parse "$wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world c-min-producer \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

marker_value() {
  local marker="$1"
  awk -v marker="$marker" '
    $0 ~ "^[[:space:]]*;; \\[" marker "\\]$" { want = 1; next }
    want && $1 == "i32.const" { print $2; exit }
    want { exit 1 }
  ' "$wat"
}

list_pointer=$(marker_value 'producer-list-pointer')
list_length=$(marker_value 'producer-list-length')
element_stride=$(marker_value 'producer-list-element-stride')
ticket_offset=$(marker_value 'producer-list-ticket-offset')
stream_capacity=$(marker_value 'producer-stream-capacity')
test "$list_pointer" = 64
test "$list_length" = 68
test "$element_stride" = 4
test "$ticket_offset" = 0
test "$stream_capacity" = 1
printf 'C-min layout pointer=%s length=%s stride=%s ticket-offset=%s stream-capacity=%s\n' \
  "$list_pointer" "$list_length" "$element_stride" "$ticket_offset" "$stream_capacity"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-g6-2-c-min-list-resource-producer-abi
for mode in ready-empty ready-one ready-three pending sink-error early-drop invalid-mode; do
  cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$bin" -- "$component" "$mode"
done

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
    malformed-len)
      test "$(rg -c '^\s*;; \[mode-before-stream-write\]$' "$wat")" = 1
      sed '/;; \[mode-before-stream-write\]/a\
    local.get $frame\
    i32.const 68\
    i32.add\
    i32.const 4\
    i32.store' "$wat" >"$variant"
      ;;
    duplicate-drop)
      test "$(rg -c '^\s*;; \[mode-after-list-create\]$' "$wat")" = 1
      sed '/;; \[mode-after-list-create\]/a\
    local.get $handle\
    call $ticket-drop\
    local.get $handle\
    call $ticket-drop' "$wat" >"$variant"
      ;;
    *)
      printf 'unknown C-min variant: %s\n' "$mode" >&2
      return 2
      ;;
  esac

  wasm-tools parse "$variant" -o "$variant_core"
  wasm-tools component embed "$wit" "$variant_core" \
    --world c-min-producer \
    --features cm-async,cm-more-async-builtins \
    -o "$variant_embedded"
  wasm-tools component new --skip-validation "$variant_embedded" -o "$variant_component"
  wasm-tools validate --features cm-async,cm-more-async-builtins "$variant_component"
  printf '%s\n' "$variant_component"
}

cancel_before_component=$(build_variant cancel-before-transfer)
cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin "$bin" -- "$cancel_before_component" cancel-before-transfer

cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin "$bin" -- "$component" cancel-after-transfer

expect_trap() {
  local component_path="$1"
  local mode="$2"
  local expected_error="$3"
  local output
  if output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$bin" -- "$component_path" "$mode" 2>&1); then
    printf 'C-min mode unexpectedly completed: %s\n%s\n' "$mode" "$output" >&2
    return 1
  fi
  grep -Fqi "$expected_error" <<<"$output"
}

malformed_component=$(build_variant malformed-len)
expect_trap "$malformed_component" malformed-len 'unknown handle index 0'

duplicate_component=$(build_variant duplicate-drop)
expect_trap "$duplicate_component" duplicate-drop 'unknown handle index 4'

printf 'G6.2 C-min producer canonical ABI probe passed\n'
