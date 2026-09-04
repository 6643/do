#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-scalar-result.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

test -x "$toolchain_bin"

core_path="$tmp_dir/scalar-result.wat"
wit_path="$tmp_dir/scalar-result.wit"
core_wasm="$tmp_dir/scalar-result.wasm"
embedded="$tmp_dir/scalar-result.embedded.wasm"
component="$tmp_dir/scalar-result.component.wasm"
cancel_core_path="$tmp_dir/scalar-result-cancel.wat"
cancel_wit_path="$tmp_dir/scalar-result-cancel.wit"
cancel_core_wasm="$tmp_dir/scalar-result-cancel.wasm"
cancel_embedded="$tmp_dir/scalar-result-cancel.embedded.wasm"
cancel_component="$tmp_dir/scalar-result-cancel.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
    "$repo_root/src/build/test/compile_err/382_result_payload_lowering_unavailable.do" \
    --p3-async-component --p3-wit-output "$wit_path" -o "$core_path"
"$toolchain_bin" parse-core "$core_path" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit_path" "$core_wasm" probe \
    --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
    "$repo_root/examples/p3-runtime/scalar-result-cancel.do" \
    --p3-async-component --p3-wit-output "$cancel_wit_path" -o "$cancel_core_path"
"$toolchain_bin" parse-core "$cancel_core_path" -o "$cancel_core_wasm"
"$toolchain_bin" embed-component "$cancel_wit_path" "$cancel_core_wasm" probe \
    --features component-async -o "$cancel_embedded"
"$toolchain_bin" new-component "$cancel_embedded" -o "$cancel_component"
"$toolchain_bin" validate-component "$cancel_component" --features component-async

if ! command -v cc >/dev/null; then
    export CC="$runner_dir/zig-cc.sh"
    export CXX="$runner_dir/zig-cc.sh"
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-scalar-result-host-runner -- "$component" "$cancel_component")
case "$output" in
    *"Rust scalar Result pending adapter passed ok=43 err=-10"*) ;;
    *) printf 'missing scalar Result runtime success marker\n%s\n' "$output" >&2; exit 1 ;;
esac
case "$output" in
    *"Rust scalar Result cancellation adapter passed started=1 committed=1 rollback=0 dropped=1"*) ;;
    *) printf 'missing scalar Result cancellation marker\n%s\n' "$output" >&2; exit 1 ;;
esac
immediate_output=$(DO_P3_SCALAR_RESULT_IMMEDIATE=1 cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-scalar-result-host-runner -- "$component" "$cancel_component")
case "$immediate_output" in
    *"Rust scalar Result immediate adapter passed ok=43 err=-10"*) ;;
    *) printf 'missing immediate scalar Result runtime success marker\n%s\n' "$immediate_output" >&2; exit 1 ;;
esac
