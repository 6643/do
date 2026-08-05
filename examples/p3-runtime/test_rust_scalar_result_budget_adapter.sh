#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-scalar-result-budget.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_path="$tmp_dir/scalar-result.wat"
wit_path="$tmp_dir/scalar-result.wit"
core_wasm="$tmp_dir/scalar-result.wasm"
embedded="$tmp_dir/scalar-result.embedded.wasm"
component="$tmp_dir/scalar-result.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
    "$repo_root/src/build/test/compile_err/382_result_payload_lowering_unavailable.do" \
    --p3-async-component --p3-wit-output "$wit_path" -o "$core_path"

if ! rg -q '\(export "byte-budget-limit"\)' "$core_path"; then
    printf 'generated Core module is missing the private budget adapter export\n' >&2
    exit 1
fi

sed -i '/^  export run:/i\\  export byte-budget-limit: func(limit: s64) -> s32;' "$wit_path"
wasm-tools parse "$core_path" -o "$core_wasm"
wasm-tools component embed "$wit_path" "$core_wasm" --world probe -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

if ! command -v cc >/dev/null; then
    export CC="$runner_dir/zig-cc.sh"
    export CXX="$runner_dir/zig-cc.sh"
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

output=$(DO_P3_SCALAR_RESULT_BUDGET_LIMIT=20 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-scalar-result-host-runner -- "$component")
case "$output" in
    *"Rust scalar Result budget adapter passed limit=20 configured=1 frame=20"*) ;;
    *) printf 'missing scalar Result budget success marker\n%s\n' "$output" >&2; exit 1 ;;
esac

rejected=$(DO_P3_SCALAR_RESULT_BUDGET_LIMIT=19 \
    DO_P3_SCALAR_RESULT_BUDGET_EXPECT_REJECT=1 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-scalar-result-host-runner -- "$component")
case "$rejected" in
    *"Rust scalar Result budget adapter rejected limit=19 frame=20"*) ;;
    *) printf 'missing scalar Result budget rejection marker\n%s\n' "$rejected" >&2; exit 1 ;;
esac

scheduler=$(DO_P3_SCALAR_RESULT_SCHEDULER_LIMIT=20 cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-scalar-result-host-runner -- "$component")
case "$scheduler" in
    *"Rust scalar Result scheduler admission passed limit=20 rejected=1 released=1"*) ;;
    *) printf 'missing scalar Result scheduler admission marker\n%s\n' "$scheduler" >&2; exit 1 ;;
esac

printf '%s\n' 'Rust scalar Result private budget adapter passed'
