#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
component=${1:?usage: $0 <component.wasm>}
test -f "$component"

runner_source="$runner_dir/src/bin/async_call_scalar_argument.rs"
test -f "$runner_source"

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
        --bin do-p3-async-call-scalar-argument-host-runner -- "$component" "$mode"
}

ready=$(run_mode ready)
pending=$(run_mode pending)
cancel=$(run_mode cancel)

grep -Fq 'mode=ready child-completions=1 child-drops=1 host-future-drops=1 table-empty=true' <<<"$ready"
grep -Fq 'mode=pending child-completions=1 child-drops=1 host-future-drops=1 table-empty=true' <<<"$pending"
grep -Fq 'mode=cancel child-cancellations=1 child-drops=1 host-future-drops=1 table-empty=true' <<<"$cancel"
for output in "$ready" "$pending" "$cancel"; do
    grep -Fq 'async-call root-terminal=1 duplicate-drop=0' <<<"$output"
done

printf '%s\n' "$ready" "$pending" "$cancel"
printf 'rust async-call scalar argument gate passed\n'
