#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
do_bin="${DO_BIN:-$repo_root/bin/do}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"

fixture="$repo_root/src/build/test/compile_ok/821_wasi_filesystem_write_via_stream_component.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-write-via-stream-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wat="$tmp_dir/generated.wat"
wit="$tmp_dir/generated.wit"
core="$tmp_dir/generated.core.wasm"
embedded="$tmp_dir/generated.embedded.wasm"
component="$tmp_dir/generated.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
  --p3-async-component --p3-wit-output "$wit" -o "$wat" >/dev/null
"$toolchain_bin" parse-core "$wat" -o "$core"
"$toolchain_bin" embed-component "$wit" "$core" write-via-stream-probe \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

runner_source="$runner_dir/src/bin/wasi_filesystem_write_via_stream.rs"
rustfmt --edition 2024 --check "$runner_source"

run_mode() {
  local mode="$1"
  shift
  local output
  output=$(
    cd "$runner_dir"
    DO_WRITE_VIA_STREAM_MODE="$mode" timeout 90s \
      cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
      --bin wasi-filesystem-write-via-stream -- "$component"
  )
  for expected in "$@"; do
    rg -Fq -- "$expected" <<<"$output"
  done
  printf '%s\n' "$output"
}

run_mode ready \
  'mode=ready offsets=[1234] bytes=[65] method-calls=1 stream-polls=1 wakes=0 stream-drops=1 method-completions=1 method-errors=0 descriptor-drops=1 table-empty=true'
run_mode pending \
  'mode=pending offsets=[1234] bytes=[65] method-calls=1 stream-polls=2 wakes=1 stream-drops=1 method-completions=1 method-errors=0 descriptor-drops=1 table-empty=true'
run_mode method-error \
  'mode=method-error offsets=[1234] bytes=[65] method-calls=1 stream-polls=1 wakes=0 stream-drops=1 method-completions=0 method-errors=1 descriptor-drops=1 table-empty=true'
run_mode sink-error \
  'mode=sink-error result=trap offsets=[1234] bytes=[65] method-calls=1 stream-polls=1 wakes=0 stream-drops=1 method-completions=0 method-errors=0 descriptor-drops=0 table-empty=not-applicable'
run_mode cancel-before-completion \
  'mode=cancel-before-completion offsets=[1234] bytes=[] method-calls=1 stream-polls=3 wakes=1 stream-drops=1 method-completions=0 method-errors=0 descriptor-drops=1 table-empty=true'
run_mode cancel-after-close \
  'mode=cancel-after-close offsets=[1234] bytes=[65] method-calls=1 stream-polls=1 wakes=0 stream-drops=1 method-completions=1 method-errors=0 descriptor-drops=1 table-empty=true'
run_mode repeat \
  'mode=repeat offsets=[1234, 1234] bytes=[65, 65] method-calls=2 stream-polls=2 wakes=0 stream-drops=2 method-completions=2 method-errors=0 descriptor-drops=2 table-empty=true'

early_drop=$(
  cd "$runner_dir"
  DO_WRITE_VIA_STREAM_MODE=early-drop timeout 90s \
    cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin wasi-filesystem-write-via-stream -- "$component"
)
rg -Fq -- 'mode=early-drop result=store-discarded' <<<"$early_drop"
rg -Fq -- 'offsets=[1234] bytes=[] method-calls=1 stream-polls=2 wakes=1 stream-drops=1 method-completions=0 method-errors=0 descriptor-drops=0 table-empty=false' <<<"$early_drop"
printf '%s\n' "$early_drop"

printf 'D2 filesystem descriptor.write-via-stream Rust/Wasmtime runtime gate passed\n'
