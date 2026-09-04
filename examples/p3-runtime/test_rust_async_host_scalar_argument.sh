#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
source="$repo_root/examples/p3-runtime/async-host-scalar-argument.do"
wit_snapshot="$repo_root/examples/p3-runtime/wit/async-call-arg-probe.wit"

test -x "$do_bin"
test -x "$toolchain_bin"
test -f "$source"
test -f "$wit_snapshot"
test -f "$runner_dir/src/bin/async_call_arg_probe.rs"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-rust-async-host-scalar-argument.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/probe.wat"
wit="$tmp_dir/probe.wit"
core_wasm="$tmp_dir/probe.core.wasm"
embedded="$tmp_dir/probe.embedded.wasm"
component="$tmp_dir/probe.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
    --p3-async-host-arg-component --p3-wit-output "$wit" -o "$core_wat"
cmp "$wit_snapshot" "$wit"

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" probe \
    --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"

runner_env=()
if ! command -v cc >/dev/null; then
    runner_env+=(
        CC="$runner_dir/zig-cc.sh"
        CXX="$runner_dir/zig-cc.sh"
        CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
    )
fi

run_mode() {
    local mode=$1
    env "${runner_env[@]}" cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
        --bin do-p3-async-call-arg-probe-host-runner -- "$component" "$mode"
}

ready=$(run_mode ready)
pending=$(run_mode pending)
cancel=$(run_mode cancel)

grep -Fq 'mode=ready calls=1 argument=7' <<<"$ready"
grep -Fq 'future-drops=1 pending-drops=0 guest-completed=true table-empty=true' <<<"$ready"
grep -Fq 'mode=pending calls=1 argument=7' <<<"$pending"
grep -Fq 'future-drops=1 pending-drops=0 guest-completed=true table-empty=true' <<<"$pending"
grep -Fq 'mode=cancel calls=1 argument=7' <<<"$cancel"
grep -Fq 'future-drops=1 pending-drops=1 guest-completed=false table-empty=true' <<<"$cancel"

printf '%s\n' "$ready" "$pending" "$cancel"
printf 'rust async host scalar argument promotion gate passed\n'
