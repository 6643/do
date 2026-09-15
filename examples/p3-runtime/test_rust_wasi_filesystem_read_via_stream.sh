#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-read-via-stream-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if ! command -v cc >/dev/null; then
  if ! command -v zig >/dev/null; then
    printf 'missing C linker: install cc or make zig available\n' >&2
    exit 1
  fi
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

core_wat="$tmp_dir/read.wat"
core_wasm="$tmp_dir/read.wasm"
embedded="$tmp_dir/read.embedded.wasm"
component="$tmp_dir/read.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/wasi-filesystem-read-via-stream.do" \
  --p3-async-component --p3-wit-output "$tmp_dir/read.wit" -o "$core_wat"
"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$tmp_dir/read.wit" "$core_wasm" read-via-stream-probe --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

for mode in ready pending error cancel-before-eof cancel-after-eof early-drop repeat; do
  output=$(cd "$runner_dir" && DO_READ_VIA_STREAM_MODE="$mode" timeout 60s cargo run --quiet \
    --bin do-p3-wasi-filesystem-read-via-stream-host-runner -- "$component")
  case "$mode" in
    ready)
      expected='result=Ok method-calls=1 stream-reads=1 completion-polls=1 wakes=0 completions=1 completion-errors=0 stream-drops=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true'
      ;;
    pending)
      expected='result=Ok method-calls=1 stream-reads=2 completion-polls=2 wakes=2 completions=1 completion-errors=0 stream-drops=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true'
      ;;
    error)
      expected='result=Err(io) method-calls=1 stream-reads=1 completion-polls=1 wakes=0 completions=1 completion-errors=1 stream-drops=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true'
      ;;
    cancel-before-eof)
      expected='result=cancelled method-calls=1 stream-reads=1 completion-polls=0 wakes=0 completions=0 completion-errors=0 stream-drops=1 future-drops=1 pending-future-drops=1 descriptor-drops=1 table-empty=true'
      ;;
    cancel-after-eof)
      expected='result=cancelled method-calls=1 stream-reads=1 completion-polls=2 wakes=0 completions=0 completion-errors=0 stream-drops=1 future-drops=1 pending-future-drops=1 descriptor-drops=1 table-empty=true'
      ;;
    repeat)
      expected='result=Ok,Ok method-calls=2 stream-reads=2 completion-polls=2 wakes=0 completions=2 completion-errors=0 stream-drops=2 future-drops=2 pending-future-drops=0 descriptor-drops=2 table-empty=true'
      ;;
    early-drop)
      expected='result=store-disposed method-calls=1 stream-reads=1 completion-polls=2 wakes=0 completions=0 completion-errors=0 stream-drops=1 future-drops=1 pending-future-drops=1 descriptor-drops=0 table-empty=not-applicable'
      ;;
  esac
  if ! grep -Fq -- "$expected" <<<"$output"; then
    printf 'missing runtime counter assertion: %s\nexpected: %s\nactual: %s\n' "$mode" "$expected" "$output" >&2
    exit 1
  fi
done

printf '%s\n' 'WASI D2 read-via-stream runtime passed'
