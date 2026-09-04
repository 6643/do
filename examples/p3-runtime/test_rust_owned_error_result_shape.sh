#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
cargo_bin=${CARGO_BIN:-cargo}
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/owned-error-shape.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

test -x "$toolchain_bin"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/owned-error-resource-probe.do" \
  --p3-async-component \
  --p3-wit-output "$tmp_dir/owned-error-result.wit" \
  -o "$tmp_dir/owned-error-result.wat"
cmp "$repo_root/src/build/p3_async_resource_owned_error_probe.wit" \
  "$tmp_dir/owned-error-result.wit"
"$toolchain_bin" parse-core "$tmp_dir/owned-error-result.wat" \
  -o "$tmp_dir/owned-error-result.wasm"
"$toolchain_bin" embed-component \
  "$tmp_dir/owned-error-result.wit" \
  "$tmp_dir/owned-error-result.wasm" \
  owned-error-result-probe --features component-async \
  -o "$tmp_dir/owned-error-result.embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/owned-error-result.embedded.wasm" \
  -o "$tmp_dir/owned-error-result.component.wasm"
"$toolchain_bin" validate-component \
  "$tmp_dir/owned-error-result.component.wasm" --features component-async

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
"$toolchain_bin" parse-core "$cancel_core" -o "$cancel_wasm"
"$toolchain_bin" embed-component "$cancel_wit" "$cancel_wasm" \
  owned-error-resource-cancel-probe --features component-async -o "$cancel_embedded"
"$toolchain_bin" new-component "$cancel_embedded" -o "$cancel_component"
"$toolchain_bin" validate-component "$cancel_component" --features component-async

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
"$toolchain_bin" parse-core "$repo_root/examples/p3-runtime/owned-error-resource-cancel-probe.wat" -o "$hand_wasm"
"$toolchain_bin" embed-component "$repo_root/examples/p3-runtime/wit/resource-probe-owned-error-cancel.wit" "$hand_wasm" \
  owned-error-resource-cancel-probe --features component-async -o "$hand_embedded"
"$toolchain_bin" new-component "$hand_embedded" -o "$hand_component"
"$toolchain_bin" validate-component "$hand_component" --features component-async
run_cancel_case hand-written "$hand_component"

printf 'pinned owned-error Result Component shape and runtime matrix passed\n'
