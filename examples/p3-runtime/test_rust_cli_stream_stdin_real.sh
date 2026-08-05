#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-cli-stdin.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_path="$tmp_dir/cli-stream-stdin.wat"
wit_path="$tmp_dir/cli-stream-stdin.wit"
core_wasm="$tmp_dir/cli-stream-stdin.wasm"
embedded="$tmp_dir/cli-stream-stdin.embedded.wasm"
component="$tmp_dir/cli-stream-stdin.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
  --p3-wit-output "$wit_path" \
  "$repo_root/examples/p3-runtime/cli-stream-stdin-component.do" -o "$core_path"
sed -i '/^  export run:/i\  export byte-budget-limit: func(limit: s64) -> s32;' "$wit_path"
wasm-tools parse "$core_path" -o "$core_wasm"
wasm-tools component embed "$wit_path" "$core_wasm" --world stream-stdin-probe -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

runner_env=(
  CC="$runner_dir/zig-cc.sh"
  CXX="$runner_dir/zig-cc.sh"
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
  DO_D2_CLI_STDIN_PIPE=1
)

output=$(cd "$runner_dir" && env "${runner_env[@]}" \
  timeout 60s cargo run --quiet --bin do-p3-cli-stream-stdin-host-runner -- "$component")
ready_output=$(cd "$runner_dir" && env "${runner_env[@]}" DO_STREAM_COMPLETION_READY=1 \
  timeout 60s cargo run --quiet --bin do-p3-cli-stream-stdin-host-runner -- "$component")

for marker in \
  'Rust CLI stdin stream execution passed items=[100, 50]' \
  'eof=true completion-unread-dropped=true stream-dropped=true future-dropped=true'; do
  case "$output" in
    *"$marker"*) ;;
    *) printf 'missing CLI stdin real marker: %s\n%s\n' "$marker" "$output" >&2; exit 1 ;;
  esac
done

for marker in \
  'Rust CLI stdin stream execution passed items=[100, 50]' \
  'eof=true completion-unread-dropped=true stream-dropped=true future-dropped=true'; do
  case "$ready_output" in
    *"$marker"*) ;;
    *) printf 'missing CLI stdin real ready marker: %s\n%s\n' "$marker" "$ready_output" >&2; exit 1 ;;
  esac
done

printf 'D2 real CLI stdin pipe stream passed\n'
