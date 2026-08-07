#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
fixture="$repo_root/examples/p3-runtime/variant-resource-stream.do"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/variant-resource-stream-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_file="$tmp_dir/variant-resource-stream.wit"
wat_file="$tmp_dir/variant-resource-stream.wat"
core_wasm="$tmp_dir/variant-resource-stream.core.wasm"
embedded="$tmp_dir/variant-resource-stream.embedded.wasm"
component="$tmp_dir/variant-resource-stream.component.wasm"
component_target=${DO_P3_ASYNC_COMPONENT_TARGET:---p3-async-component}

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$component_target" "$fixture" \
  --p3-wit-output "$wit_file" -o "$wat_file"
grep -Fq '[event-tag-offset]' "$wat_file"
grep -Fq '[event-payload-offset]' "$wat_file"
grep -Fq '[resource-drop]ticket' "$wat_file"

wasm-tools parse "$wat_file" -o "$core_wasm"
wasm-tools component embed "$wit_file" "$core_wasm" \
  --world variant-resource-stream-canonical \
  --features cm-async,cm-more-async-builtins -o "$embedded"
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
  output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-variant-resource-stream-abi -- "$component" "$mode")
  for expected in "$@"; do
    grep -Fq "$expected" <<<"$output"
  done
}

run_mode ticket-ready \
  'event=ticket resource-created=1 resource-drops=1 stream-drops=1 future-drops=1 completion-polls=1 table-empty=true result=Ok trap=false'
run_mode idle-ready \
  'event=idle resource-created=0 resource-drops=0 stream-drops=1 future-drops=1 completion-polls=1 table-empty=true result=Ok trap=false'
run_mode failed-ready \
  'event=failed(io) resource-created=0 resource-drops=0 stream-drops=1 future-drops=1 completion-polls=0 table-empty=true result=Err(io) trap=false'
run_mode ticket-pending \
  'event=ticket resource-created=1 resource-drops=1 stream-drops=1 future-drops=1 completion-polls=2 table-empty=true result=Ok trap=false'
run_mode completion-error \
  'event=ticket resource-created=1 resource-drops=1 stream-drops=1 future-drops=1 completion-polls=1 table-empty=true result=Err(io) trap=false'

# The canonical ABI probe remains the independent oracle for early-drop and
# malformed/duplicate ownership traps; the generated component covers the
# same admitted ready/pending/error matrix above.
bash "$repo_root/examples/p3-runtime/test_variant_resource_stream_abi.sh"

printf 'variant resource stream generated Component and canonical ABI gates passed\n'
