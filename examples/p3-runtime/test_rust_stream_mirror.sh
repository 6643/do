#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/stream-mirror-rust.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

fixture="$repo_root/examples/p3-runtime/stream-probe-stream-mirror.do"
wit_path="$tmp_dir/stream-mirror.wit"
core_wat="$tmp_dir/stream-mirror.wat"
core_wasm="$tmp_dir/stream-mirror.wasm"
component_path="$tmp_dir/stream-mirror.component.wasm"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
cargo_target_dir=${CARGO_TARGET_DIR:-"$repo_root/.tmp/do-tmp/cargo-target"}

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
  --p3-wit-output "$wit_path" "$fixture" -o "$core_wat"
wasm-tools parse "$core_wat" -o "$core_wasm"
TMPDIR="$tmp_root" bash "$repo_root/examples/p3-runtime/assemble_async_component.sh" \
  "$wit_path" "$core_wasm" stream-mirror-probe "$component_path"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component_path"

if (($# == 0)); then
  modes=(pending ready source-eof error cancel early-drop)
elif (($# == 1)); then
  case "$1" in
    pending|ready|source-eof|error|cancel|early-drop) modes=("$1") ;;
    *) printf 'unknown stream mirror mode: %s\n' "$1" >&2; exit 2 ;;
  esac
else
  printf 'usage: %s [pending|ready|source-eof|error|cancel|early-drop]\n' "$0" >&2
  exit 2
fi

for mode in "${modes[@]}"; do
  printf 'stream-mirror mode=%s\n' "$mode"
  timeout 30s env \
  CC="$runner_dir/zig-cc.sh" \
  CXX="$runner_dir/zig-cc.sh" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh" \
  CARGO_TARGET_DIR="$cargo_target_dir" \
  cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-stream-mirror-host-runner -- "$component_path" "$mode"
done

if (($# == 0)); then
  printf 'stream mirror Rust/Wasmtime matrix passed modes=pending,ready,source-eof,error,cancel,early-drop\n'
fi
