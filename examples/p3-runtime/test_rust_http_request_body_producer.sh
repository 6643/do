#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-request-body-producer-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
core_wat="$tmp_dir/producer.wat"
core_wasm="$tmp_dir/producer.wasm"
wit_dir="$tmp_dir/wit-package"
embedded="$tmp_dir/producer.embedded.wasm"
component="$tmp_dir/producer.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/http-request-body-producer-send-first.do" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"
wasm-tools parse "$core_wat" -o "$core_wasm"
cat >>"$wit_dir/worlds.wit" <<'WIT'

interface probe {
  use types.{response, error-code};
  run: async func() -> result<response, error-code>;
}

world http-request-body-producer-probe {
  import types;
  import client;
  import wasi:cli/stdout@0.3.0-rc-2025-09-16;
  export probe;
}
WIT
wasm-tools component embed "$wit_dir" "$core_wasm" \
  --world http-request-body-producer-probe \
  --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

runner_env=(
  CC="$runner_dir/zig-cc.sh"
  CXX="$runner_dir/zig-cc.sh"
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
)

output=$(cd "$runner_dir" && env "${runner_env[@]}" \
  timeout 90s cargo run --quiet \
    --bin do-p3-http-request-body-producer-host-runner -- "$component")

for marker in \
  'Rust P3 HTTP request body producer passed' \
  'body-payloads=[[65, 66], [65, 66]]' \
  'write-completions=4' \
  'pending-writes=1' \
  'writer-close-observed=true' \
  'responses=1' \
  'body-stream-drops=2' \
  'transmission-future-drops=2' \
  'trailers-future-drops=2' \
  'table-empty=true'; do
  case "$output" in
    *"$marker"*) ;;
    *)
      printf 'missing marker: %s\n%s\n' "$marker" "$output" >&2
      exit 1
      ;;
  esac
done

printf '%s\n' "$output"
printf 'WASI HTTP request body producer runtime passed\n'
