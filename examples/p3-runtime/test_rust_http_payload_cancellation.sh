#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
fixture="$repo_root/examples/p3-runtime/http-payload-cancel.do"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/http-payload-cancel-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wat="$tmp_dir/http-payload-cancel.wat"
core_wasm="$tmp_dir/http-payload-cancel.wasm"
embedded="$tmp_dir/http-payload-cancel.embedded.wasm"
component="$tmp_dir/http-payload-cancel.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"

grep -Fq '"wasi:http/client@0.3.0-rc-2025-09-16" "[async-lower]send"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]request"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]response"' "$core_wat"
grep -Fq ';; [http-payload-cancel] immediate terminal' "$core_wat"
grep -Fq ';; [http-payload-cancel] pending terminal' "$core_wat"
grep -Fq 'call $subtask-cancel' "$core_wat"
grep -Fq 'call $subtask-drop' "$core_wat"

# The compiler emits the private cancel shape against the pinned HTTP package.
# Keep the extra world in a temporary copy so the checked-in package remains
# an immutable toolchain input.
cp "$repo_root/examples/p3-runtime/wit/http-payload-cancel-service-world.wit" \
  "$wit_dir/http-payload-cancel-service-world.wit"

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit_dir" "$core_wasm" \
  --world http-payload-cancel \
  --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new "$embedded" --skip-validation -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

CC="$runner_dir/zig-cc.sh" \
CXX="$runner_dir/zig-cc.sh" \
CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh" \
  cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin http_payload_cancel

run_case() {
  local mode=$1
  local expected_pending_drops=$2
  local expected_ready_polls=$3
  local expected_ready_drops=$4
  local expected_response_create=$5
  local expected_response_drop=$6
  local expected_trap=$7
  local output
  case "$mode:$expected_trap" in
    ready-dns-error:false|ready-dns-error-long:false)
      output=$("$runner_dir/target/debug/http_payload_cancel" \
        "$component" "$mode" --expect-dns-error-discard)
      ;;
    ready-internal-error:false)
      output=$("$runner_dir/target/debug/http_payload_cancel" \
        "$component" "$mode" --expect-internal-error-discard)
      ;;
    ready-dns-error-none:false)
      output=$("$runner_dir/target/debug/http_payload_cancel" \
        "$component" "$mode" --expect-dns-error-discard)
      ;;
    ready-internal-error-none:false)
      output=$("$runner_dir/target/debug/http_payload_cancel" \
        "$component" "$mode" --expect-internal-error-discard)
      ;;
    *)
      output=$("$runner_dir/target/debug/http_payload_cancel" "$component" "$mode")
      ;;
  esac
  for marker in \
    'Rust P3 HTTP payload cancellation probe passed' \
    "mode=$mode" \
    'request consumed=1' \
    "pending future drops=$expected_pending_drops" \
    "ready future polls=$expected_ready_polls" \
    "ready future drops=$expected_ready_drops" \
    "response create=$expected_response_create" \
    "response drop=$expected_response_drop" \
    "expected trap=$expected_trap" \
    'table-empty=true'; do
    case "$output" in
      *"$marker"*) ;;
      *)
        printf 'missing HTTP payload cancellation marker: %s\n%s\n' "$marker" "$output" >&2
        exit 1
        ;;
    esac
  done
  printf '%s\n' "$output"
}

run_case pending 1 0 0 0 0 false
run_case ready-ok 0 1 1 1 1 false
run_case ready-dns-timeout 0 1 1 0 0 false
run_case ready-dns-error 0 1 1 0 0 false
run_case ready-dns-error-long 0 1 1 0 0 false
run_case ready-internal-error 0 1 1 0 0 false
run_case ready-dns-error-none 0 1 1 0 0 false
run_case ready-internal-error-none 0 1 1 0 0 false

output=$("$runner_dir/target/debug/http_payload_cancel" \
  "$component" ready-dns-error --expect-dns-error-discard --twice)
for marker in \
  'Rust P3 HTTP payload cancellation probe passed' \
  'mode=ready-dns-error' \
  'request consumed=2' \
  'pending future drops=0' \
  'ready future polls=2' \
  'ready future drops=2' \
  'response create=0' \
  'response drop=0' \
  'table-empty=true'; do
  case "$output" in
    *"$marker"*) ;;
    *)
      printf 'missing repeated HTTP payload cancellation marker: %s\n%s\n' "$marker" "$output" >&2
      exit 1
      ;;
  esac
done

printf 'WASI HTTP payload cancellation runtime passed\n'
