#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-c-min-dynamic-list-producer.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wat="$repo_root/examples/p3-runtime/g6-2-c-min-dynamic-list-producer-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/g6-2-c-min-dynamic-list-producer.wit"
core_wasm="$tmp_dir/canonical.core.wasm"
embedded="$tmp_dir/canonical.embedded.wasm"
component="$tmp_dir/canonical.component.wasm"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf 'missing probe artifact: %s\n' "$path" >&2
    return 1
  fi
}

require_file "$wat"
require_file "$wit"
require_file "$runner_dir/src/bin/g6_2_c_min_dynamic_list_producer_abi.rs"

"$toolchain_bin" parse-core "$wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" dynamic-list-producer \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

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
printf 'dynamic layout pointer=%s length=%s stride=%s ticket-offset=%s stream-capacity=%s\n' \
  "$list_pointer" "$list_length" "$element_stride" "$ticket_offset" "$stream_capacity"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

bin=do-p3-g6-2-c-min-dynamic-list-producer-abi
for mode in ready-empty ready-one ready-two ready-three pending sink-error early-drop invalid-mode; do
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
    source-partial-failure)
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

  "$toolchain_bin" parse-core "$variant" -o "$variant_core"
  "$toolchain_bin" embed-component "$wit" "$variant_core" dynamic-list-producer \
    --features component-async -o "$variant_embedded"
  "$toolchain_bin" new-component "$variant_embedded" -o "$variant_component"
  "$toolchain_bin" validate-component "$variant_component" --features component-async
  printf '%s\n' "$variant_component"
}

cancel_before_component=$(build_variant cancel-before-transfer)
cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin "$bin" -- "$cancel_before_component" cancel-before-transfer

source_partial_component=$(build_variant source-partial-failure)
cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin "$bin" -- "$source_partial_component" source-partial-failure

cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin "$bin" -- "$component" cancel-after-transfer

printf 'G6.2 bounded dynamic list producer canonical ABI probe passed\n'
