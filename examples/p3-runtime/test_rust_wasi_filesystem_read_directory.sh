#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-read-directory-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/read-directory.wat"
core_wasm="$tmp_dir/read-directory.wasm"
wit="$tmp_dir/read-directory.wit"
embedded="$tmp_dir/read-directory.embedded.wasm"
component="$tmp_dir/read-directory.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/wasi-filesystem-read-directory.do" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"
wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world read-directory-probe --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

runner_env=(
  CC="$runner_dir/zig-cc.sh"
  CXX="$runner_dir/zig-cc.sh"
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
)

output=$(cd "$runner_dir" && env "${runner_env[@]}" \
  timeout 60s cargo run --quiet --bin do-p3-wasi-filesystem-read-directory-host-runner -- "$component")
ready_output=$(cd "$runner_dir" && env "${runner_env[@]}" DO_READ_DIRECTORY_COMPLETION_READY=1 \
  timeout 60s cargo run --quiet --bin do-p3-wasi-filesystem-read-directory-host-runner -- "$component")

for marker in \
  'Rust WASI read-directory adapter passed' \
  'entry-name=alpha' \
  'completion-mode=pending-once' \
  'descriptor-drops=1 stream-drops=1 future-drops=1 table-empty=true'; do
  case "$output" in
    *"$marker"*) ;;
    *) printf 'missing marker: %s\n%s\n' "$marker" "$output" >&2; exit 1 ;;
  esac
done

for marker in \
  'Rust WASI read-directory adapter passed' \
  'entry-name=alpha' \
  'completion-mode=ready' \
  'descriptor-drops=1 stream-drops=1 future-drops=1 table-empty=true'; do
  case "$ready_output" in
    *"$marker"*) ;;
    *) printf 'missing ready marker: %s\n%s\n' "$marker" "$ready_output" >&2; exit 1 ;;
  esac
done

printf 'WASI G6.2 read-directory runtime passed\n'
