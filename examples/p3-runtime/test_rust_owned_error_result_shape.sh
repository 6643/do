#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
cargo_bin=${CARGO_BIN:-cargo}
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/owned-error-shape.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/owned-error-resource-probe.do" \
  --p3-async-component \
  --p3-wit-output "$tmp_dir/owned-error-result.wit" \
  -o "$tmp_dir/owned-error-result.wat"
cmp "$repo_root/src/build/p3_async_resource_owned_error_probe.wit" \
  "$tmp_dir/owned-error-result.wit"
wasm-tools parse "$tmp_dir/owned-error-result.wat" \
  -o "$tmp_dir/owned-error-result.wasm"
wasm-tools component embed \
  "$tmp_dir/owned-error-result.wit" \
  "$tmp_dir/owned-error-result.wasm" \
  --world owned-error-result-probe \
  -o "$tmp_dir/owned-error-result.embedded.wasm"
wasm-tools component new "$tmp_dir/owned-error-result.embedded.wasm" \
  -o "$tmp_dir/owned-error-result.component.wasm"
wasm-tools validate --features cm-async,cm-more-async-builtins \
  "$tmp_dir/owned-error-result.component.wasm"

if ! command -v cc >/dev/null && command -v zig >/dev/null; then
  export CC="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

run_case() {
  local label=$1
  shift
  local output
  output=$(env "$@" "$cargo_bin" run --quiet --locked \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-owned-error-result-shape-host-runner \
    -- "$tmp_dir/owned-error-result.component.wasm")
  case "$output" in
    *"Rust P3 owned-error Result $label adapter passed"*) ;;
    *)
      printf 'missing owned-error %s runtime marker\n%s\n' "$label" "$output" >&2
      exit 1
      ;;
  esac
  printf '%s\n' "$output"
}

pending_output=$(run_case pending)
case "$pending_output" in
  *"request consumed=2"*"response create=2"*"response drop=2"*"error-resource create=0"*"error-resource drop=0"*"table-empty=true"*) ;;
  *) printf 'unexpected pending owned-error counters\n%s\n' "$pending_output" >&2; exit 1 ;;
esac

immediate_output=$(run_case immediate DO_P3_OWNED_ERROR_IMMEDIATE=1)
case "$immediate_output" in
  *"request consumed=2"*"response create=2"*"response drop=2"*"error-resource create=0"*"error-resource drop=0"*"table-empty=true"*) ;;
  *) printf 'unexpected immediate owned-error counters\n%s\n' "$immediate_output" >&2; exit 1 ;;
esac

error_output=$(run_case error DO_P3_OWNED_ERROR_ERR=1)
case "$error_output" in
  *"request consumed=2"*"response create=0"*"response drop=0"*"error-resource create=2"*"error-resource drop=2"*"table-empty=true"*) ;;
  *) printf 'unexpected error owned-error counters\n%s\n' "$error_output" >&2; exit 1 ;;
esac

cancel_core="$tmp_dir/owned-error-cancel.wat"
cancel_wit="$tmp_dir/owned-error-cancel.wit"
cancel_wasm="$tmp_dir/owned-error-cancel.wasm"
cancel_embedded="$tmp_dir/owned-error-cancel.embedded.wasm"
cancel_component="$tmp_dir/owned-error-cancel.component.wasm"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/owned-error-resource-cancel-component.do" \
  --p3-async-component --p3-wit-output "$cancel_wit" -o "$cancel_core"
cmp "$repo_root/src/build/p3_async_resource_owned_error_cancel_probe.wit" "$cancel_wit"
wasm-tools parse "$cancel_core" -o "$cancel_wasm"
wasm-tools component embed "$cancel_wit" "$cancel_wasm" \
  --world owned-error-resource-cancel-probe -o "$cancel_embedded"
wasm-tools component new "$cancel_embedded" -o "$cancel_component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$cancel_component"

run_cancel_case() {
  local label=$1
  local component=$2
  local output
  output=$($cargo_bin run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-owned-error-resource-cancel-host-runner -- "$component")
  case "$output" in
    *"Rust P3 owned-error resource cancellation passed"*) ;;
    *) printf 'missing owned-error cancellation %s runtime marker\n%s\n' "$label" "$output" >&2; exit 1 ;;
  esac
  case "$output" in
    *"request consumed=1"*"pending future drops=1"*"response create=0"*"response drop=0"*"error-resource create=0"*"error-resource drop=0"*"table-empty=true"*) ;;
    *) printf 'unexpected owned-error cancellation counters for %s\n%s\n' "$label" "$output" >&2; exit 1 ;;
  esac
  printf '%s\n' "$output"
}

run_cancel_case generated "$cancel_component"

hand_wasm="$tmp_dir/owned-error-cancel-hand.wasm"
hand_embedded="$tmp_dir/owned-error-cancel-hand.embedded.wasm"
hand_component="$tmp_dir/owned-error-cancel-hand.component.wasm"
wasm-tools parse "$repo_root/examples/p3-runtime/owned-error-resource-cancel-probe.wat" -o "$hand_wasm"
wasm-tools component embed "$repo_root/examples/p3-runtime/wit/resource-probe-owned-error-cancel.wit" "$hand_wasm" \
  --world owned-error-resource-cancel-probe -o "$hand_embedded"
wasm-tools component new "$hand_embedded" -o "$hand_component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$hand_component"
run_cancel_case hand-written "$hand_component"

printf 'pinned owned-error Result Component shape and runtime matrix passed\n'
