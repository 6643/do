#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-request-body-await-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wat="$tmp_dir/body.wat"
core_wasm="$tmp_dir/body.wasm"
embedded="$tmp_dir/body.embedded.wasm"
component="$tmp_dir/body.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/http-request-body-await-completion.do" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"

wasm-tools parse "$core_wat" -o "$core_wasm"
cat >>"$wit_dir/worlds.wit" <<'WIT'

interface probe {
  use types.{response, error-code};
  run: async func() -> result<response, error-code>;
}

world http-request-body-probe {
  import types;
  import client;
  import wasi:cli/stdin@0.3.0-rc-2025-09-16;
  export probe;
}
WIT
wasm-tools component embed "$wit_dir" "$core_wasm" \
  --world http-request-body-probe --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

runner_env=(
  CC="$runner_dir/zig-cc.sh"
  CXX="$runner_dir/zig-cc.sh"
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
)

(cd "$runner_dir" && env "${runner_env[@]}" cargo test --quiet --bin do-p3-http-request-body-host-runner)

pending_output=$(cd "$runner_dir" && env "${runner_env[@]}" \
  DO_HTTP_BODY_COMPLETION_REQUIRE_READY=1 \
  DO_HTTP_BODY_COMPLETION_EXPECTED_POLLS=4 \
  timeout 60s cargo run --quiet --bin do-p3-http-request-body-host-runner -- "$component")
ready_output=$(cd "$runner_dir" && env "${runner_env[@]}" \
  DO_HTTP_BODY_COMPLETION_READY=1 \
  DO_HTTP_BODY_COMPLETION_REQUIRE_READY=1 \
  DO_HTTP_BODY_COMPLETION_EXPECTED_POLLS=2 \
  timeout 60s cargo run --quiet --bin do-p3-http-request-body-host-runner -- "$component")

for marker in \
  'Rust P3 HTTP request body adapter passed' \
  'body-payloads=[[65, 66], [65, 66]]' \
  'body-completion-mode=pending-once' \
  'body-completion-polls=4' \
  'expected-body-completion-polls=4' \
  'body-completion-ready-before-request=true' \
  'body-future-drops=2' \
  'body-stream-drops=2' \
  'responses=1' \
  'table-empty=true'; do
  case "$pending_output" in
    *"$marker"*) ;;
    *)
      printf 'missing pending marker: %s\n%s\n' "$marker" "$pending_output" >&2
      exit 1
      ;;
  esac
done

for marker in \
  'Rust P3 HTTP request body adapter passed' \
  'body-completion-mode=ready' \
  'body-completion-polls=2' \
  'expected-body-completion-polls=2' \
  'body-completion-ready-before-request=true' \
  'body-future-drops=2' \
  'body-stream-drops=2' \
  'responses=1' \
  'table-empty=true'; do
  case "$ready_output" in
    *"$marker"*) ;;
    *)
      printf 'missing ready marker: %s\n%s\n' "$marker" "$ready_output" >&2
      exit 1
      ;;
  esac
done

printf 'WASI HTTP request body completion await runtime passed\n'
