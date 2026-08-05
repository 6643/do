#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/variant-resource-stream-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wat="$repo_root/examples/p3-runtime/variant-resource-stream-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/variant-resource-stream-canonical.wit"
core_wasm="$tmp_dir/canonical.core.wasm"
embedded="$tmp_dir/canonical.embedded.wasm"
component="$tmp_dir/canonical.component.wasm"

test -f "$wat"
test -f "$wit"

wasm-tools parse "$wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world variant-resource-stream-canonical \
  --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

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

result_pointer=$(marker_value 'event-result-pointer')
tag_offset=$(marker_value 'event-tag-offset')
payload_offset=$(marker_value 'event-payload-offset')
event_size=$(marker_value 'event-size')
event_alignment=$(marker_value 'event-alignment')
test "$result_pointer" = 64
test "$tag_offset" = 0
test "$payload_offset" = 4
test "$event_size" = 8
test "$event_alignment" = 4

expect_mode() {
  local component_path="$1"
  local mode="$2"
  shift 2
  local output
  output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-variant-resource-stream-abi -- "$component_path" "$mode")
  for expected in "$@"; do
    grep -Fq "$expected" <<<"$output"
  done
  grep -Fq "observed-event-result-pointer=$result_pointer" <<<"$output"
  grep -Fq "observed-event-tag-offset=$tag_offset" <<<"$output"
  grep -Fq "observed-event-payload-offset=$payload_offset" <<<"$output"
  grep -Fq "observed-event-size=$event_size" <<<"$output"
  grep -Fq "observed-event-alignment=$event_alignment" <<<"$output"
}

expect_mode "$component" ticket-ready \
  'event=ticket resource-created=1 resource-drops=1 stream-drops=1 future-drops=1 completion-polls=1 table-empty=true result=Ok trap=false'
expect_mode "$component" idle-ready \
  'event=idle resource-created=0 resource-drops=0 stream-drops=1 future-drops=1 completion-polls=1 table-empty=true result=Ok trap=false'
expect_mode "$component" failed-ready \
  'event=failed(io) resource-created=0 resource-drops=0 stream-drops=1 future-drops=1 completion-polls=0 table-empty=true result=Err(io) trap=false'
expect_mode "$component" ticket-pending \
  'event=ticket resource-created=1 resource-drops=1 stream-drops=1 future-drops=1 completion-polls=2 table-empty=true result=Ok trap=false'
expect_mode "$component" completion-error \
  'event=ticket resource-created=1 resource-drops=1 stream-drops=1 future-drops=1 completion-polls=1 table-empty=true result=Err(io) trap=false'

build_variant() {
  local mode="$1"
  local variant="$tmp_dir/${mode}.wat"
  local variant_core="$tmp_dir/${mode}.core.wasm"
  local variant_embedded="$tmp_dir/${mode}.embedded.wasm"
  local variant_component="$tmp_dir/${mode}.component.wasm"

  case "$mode" in
    early-drop)
      sed '/;; \[mode-after-event-consume\]/,+3 c\
      ;; [mode-after-event-consume]\
      local.get $frame\
      call $cleanup' "$wat" >"$variant"
      ;;
    malformed-tag)
      sed '/;; \[mode-before-event-consume\]/,+3 c\
      ;; [mode-before-event-consume]\
      local.get $frame\
      i32.const 64\
      i32.add\
      i32.const 3\
      i32.store\
      local.get $frame\
      call $consume-event\
      local.set $failed' "$wat" >"$variant"
      ;;
    duplicate-release)
      sed '/;; \[mode-after-event-consume\]/,+3 c\
      ;; [mode-after-event-consume]\
      local.get $frame\
      call $release-ticket\
      local.get $frame\
      call $release-ticket\
      i32.const 0' "$wat" >"$variant"
      ;;
    *)
      echo "unknown variant mode: $mode" >&2
      exit 1
      ;;
  esac

  wasm-tools parse "$variant" -o "$variant_core"
  wasm-tools component embed "$wit" "$variant_core" \
    --world variant-resource-stream-canonical \
    --features cm-async,cm-more-async-builtins -o "$variant_embedded"
  wasm-tools component new --skip-validation "$variant_embedded" -o "$variant_component"
  wasm-tools validate --features cm-async,cm-more-async-builtins "$variant_component"
  printf '%s\n' "$variant_component"
}

early_drop_component=$(build_variant early-drop)
expect_mode "$early_drop_component" early-drop \
  'event=ticket resource-created=1 resource-drops=1 stream-drops=1 future-drops=1 completion-polls=0 table-empty=true result=Ok trap=false'

malformed_tag_component=$(build_variant malformed-tag)
expect_mode "$malformed_tag_component" malformed-tag \
  'event=ticket resource-created=1 resource-drops=0 table-empty=false result=none trap=true'

duplicate_release_component=$(build_variant duplicate-release)
expect_mode "$duplicate_release_component" duplicate-release \
  'event=ticket resource-created=1 resource-drops=1 table-empty=true result=none trap=true'
