#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-record-resource-list-stream.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

fixture="$repo_root/examples/p3-runtime/record-resource-list-stream-probe-component.do"
canonical_template="$repo_root/examples/p3-runtime/record-resource-list-stream-canonical.wat"
compiler_template="$repo_root/src/build/record_resource_list_stream_template.wat"
wat="$tmp_dir/generated.wat"
wit="$tmp_dir/generated.wit"
wit_dir="$tmp_dir/wit"
core_wasm="$tmp_dir/generated.core.wasm"
embedded="$tmp_dir/generated.embedded.wasm"
component="$tmp_dir/generated.component.wasm"
mkdir -p "$wit_dir"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

cmp -s "$canonical_template" "$compiler_template"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  --p3-async-component "$fixture" --p3-wit-output "$wit" -o "$wat"
grep -Fq 'do:record-resource-list-stream-probe/source@0.1.0' "$wat"
grep -Fq 'do:record-resource-list-stream-probe/probe@0.1.0' "$wat"
grep -Fq 'stream<list<resource-entry>>' "$wit"
grep -Fq 'ticket: own<ticket>' "$wit"

marker_value() {
  local marker="$1"
  awk -v marker="$marker" '
    $0 ~ "^[[:space:]]*;; \\[" marker "\\]$" { want = 1; next }
    want && $1 == "i32.const" { print $2; exit }
    want { exit 1 }
  ' "$wat"
}

pointer=$(marker_value 'list-result-pointer')
length_offset=$(marker_value 'list-result-length')
stride=$(marker_value 'list-element-stride')
ticket_offset=$(marker_value 'list-ticket-offset')
test "$pointer" = 64
test "$length_offset" = 68
test "$stride" = 4
test "$ticket_offset" = 0

cp "$wit" "$wit_dir/record-resource-list-stream-probe.wit"
wasm-tools parse "$wat" -o "$core_wasm"
wasm-tools validate --features cm-async,cm-more-async-builtins "$core_wasm"
wasm-tools component embed "$wit_dir" "$core_wasm" \
  --world record-resource-list-stream-probe \
  --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

run_generated() {
  local component_path="$1"
  local mode="$2"
  local output
  output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-record-resource-list-stream-abi -- "$component_path" --generated "$mode")
  printf '%s\n' "$output"
}

expect_ready() {
  local mode="$1"
  local entries="$2"
  local created="$3"
  local output
  output=$(run_generated "$component" "$mode")
  grep -Fq "entries=$entries resource-created=$created resource-drops=$created" <<<"$output"
  grep -Fq 'table-empty=true' <<<"$output"
  grep -Fq "observed-list-pointer=$pointer observed-list-length-offset=$length_offset" <<<"$output"
  grep -Fq "observed-list-element-stride=$stride observed-list-ticket-offset=$ticket_offset" <<<"$output"
}

expect_ready ready-empty '[]' 0
expect_ready ready-one '[111]' 1
expect_ready ready-three '[111,222,333]' 3

build_variant() {
  local mode="$1"
  local variant="$tmp_dir/${mode}.wat"
  local variant_core="$tmp_dir/${mode}.core.wasm"
  local variant_embedded="$tmp_dir/${mode}.embedded.wasm"
  local variant_component="$tmp_dir/${mode}.component.wasm"

  case "$mode" in
    pending|completion-error)
      cp "$wat" "$variant"
      ;;
    early-drop)
      sed '/;; \[mode-after-list-consume\]/,+2 c\
      ;; [mode-after-list-consume]\
      local.get $frame\
      call $cleanup' "$wat" >"$variant"
      ;;
    malformed-len)
      sed '/;; \[mode-before-list-consume\]/,+2 c\
      ;; [mode-before-list-consume]\
      local.get $frame\
      i32.const 68\
      i32.add\
      i32.const 4\
      i32.store\
      local.get $frame\
      call $consume-list' "$wat" >"$variant"
      ;;
    duplicate-drop)
      sed '/;; \[mode-after-list-consume\]/,+2 c\
      ;; [mode-after-list-consume]\
      local.get $frame\
      call $release-list\
      local.get $frame\
      call $release-list\
      i32.const 0' "$wat" >"$variant"
      ;;
    *)
      echo "unknown variant mode: $mode" >&2
      exit 1
      ;;
  esac

  wasm-tools parse "$variant" -o "$variant_core"
  wasm-tools component embed "$wit_dir" "$variant_core" \
    --world record-resource-list-stream-probe \
    --features cm-async,cm-more-async-builtins -o "$variant_embedded"
  wasm-tools component new --skip-validation "$variant_embedded" -o "$variant_component"
  wasm-tools validate --features cm-async,cm-more-async-builtins "$variant_component"
  printf '%s\n' "$variant_component"
}

expect_mode() {
  local component_path="$1"
  local mode="$2"
  shift 2
  local output
  output=$(run_generated "$component_path" "$mode")
  for expected in "$@"; do
    grep -Fq "$expected" <<<"$output"
  done
}

expect_mode "$component" pending \
  'entries=[111,222,333] resource-created=3 resource-drops=3' \
  'stream-drops=1 future-drops=1 completion-polls=2 table-empty=true' \
  'result=Ok trap=false'

expect_mode "$component" completion-error \
  'entries=[111,222,333] resource-created=3 resource-drops=3' \
  'stream-drops=1 future-drops=1 completion-polls=1 table-empty=true' \
  'result=Err(io) trap=false'

early_drop_component=$(build_variant early-drop)
expect_mode "$early_drop_component" early-drop \
  'entries=[111,222,333] resource-created=3 resource-drops=3' \
  'stream-drops=1 future-drops=1 completion-polls=0 table-empty=true' \
  'result=Ok trap=false'

malformed_component=$(build_variant malformed-len)
expect_mode "$malformed_component" malformed-len \
  'entries=[111,222,333] resource-created=3 resource-drops=0' \
  'table-empty=false' \
  'result=none trap=true'

duplicate_component=$(build_variant duplicate-drop)
expect_mode "$duplicate_component" duplicate-drop \
  'entries=[111,222,333] resource-created=3 resource-drops=3' \
  'table-empty=true' \
  'result=none trap=true'

expect_mode "$component" repeat-ready-three \
  'mode=repeat-ready-three' \
  'resource-created=18000 resource-drops=18000' \
  'stream-drops=6000 future-drops=6000 completion-polls=6000 table-empty=true' \
  'stream-reads=6000' \
  'result=Ok trap=false'

printf 'record-resource list stream generated lowering matrix passed\n'
