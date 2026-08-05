#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/record-resource-list-stream-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wat="$repo_root/examples/p3-runtime/record-resource-list-stream-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/record-resource-list-stream-canonical.wit"
core_wasm="$tmp_dir/canonical.core.wasm"
embedded="$tmp_dir/canonical.embedded.wasm"
component="$tmp_dir/canonical.component.wasm"

test -f "$wat"
test -f "$wit"
test -f "$runner_dir/src/bin/record_resource_list_stream_abi.rs"

wasm-tools parse "$wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world record-resource-list-stream-canonical \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
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

pointer=$(marker_value 'list-result-pointer')
length_offset=$(marker_value 'list-result-length')
stride=$(marker_value 'list-element-stride')
ticket_offset=$(marker_value 'list-ticket-offset')
test "$pointer" = 64
test "$length_offset" = 68
test "$stride" = 4
test "$ticket_offset" = 0

expect_ready() {
  local mode="$1"
  local entries="$2"
  local created="$3"
  local output
  output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-record-resource-list-stream-abi -- "$component" "$mode")
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
  component="$tmp_dir/${mode}.component.wasm"

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
  wasm-tools component embed "$wit" "$variant_core" \
    --world record-resource-list-stream-canonical \
    --features cm-async,cm-more-async-builtins \
    -o "$variant_embedded"
  wasm-tools component new --skip-validation "$variant_embedded" -o "$component"
  wasm-tools validate --features cm-async,cm-more-async-builtins "$component"
}

expect_mode() {
  local mode="$1"
  shift
  local output
  output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-record-resource-list-stream-abi -- "$component" "$mode")
  for expected in "$@"; do
    grep -Fq "$expected" <<<"$output"
  done
}

build_variant pending
expect_mode pending \
  'mode=pending entries=[111,222,333] resource-created=3 resource-drops=3' \
  'stream-drops=1 future-drops=1 completion-polls=2 table-empty=true' \
  'result=Ok trap=false'

build_variant completion-error
expect_mode completion-error \
  'mode=completion-error entries=[111,222,333] resource-created=3 resource-drops=3' \
  'stream-drops=1 future-drops=1 completion-polls=1 table-empty=true' \
  'result=Err(io) trap=false'

build_variant early-drop
expect_mode early-drop \
  'mode=early-drop entries=[111,222,333] resource-created=3 resource-drops=3' \
  'stream-drops=1 future-drops=1 completion-polls=0 table-empty=true' \
  'result=Ok trap=false'

build_variant malformed-len
expect_mode malformed-len \
  'mode=malformed-len entries=[111,222,333] resource-created=3 resource-drops=0' \
  'table-empty=false' \
  'result=none trap=true'

build_variant duplicate-drop
expect_mode duplicate-drop \
  'mode=duplicate-drop entries=[111,222,333] resource-created=3 resource-drops=3' \
  'table-empty=true' \
  'result=none trap=true'

printf 'record-resource list stream canonical ABI matrix passed\n'
