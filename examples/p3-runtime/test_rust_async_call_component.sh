#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
component=${1:?usage: $0 <component.wasm>}
test -f "$component"

if ! command -v cc >/dev/null; then
    export CC="$runner_dir/zig-cc.sh"
    export CXX="$runner_dir/zig-cc.sh"
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

for mode in ready pending cancel; do
    output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
        --bin do-p3-async-call-component-host-runner -- "$component" "$mode")
    case "$mode" in
        ready)
            grep -Fq 'mode=ready child-completions=1 child-drops=1 host-future-drops=1 table-empty=true' <<<"$output"
            ;;
        pending)
            grep -Fq 'mode=pending child-completions=1 child-drops=1 host-future-drops=1 table-empty=true' <<<"$output"
            ;;
        cancel)
            grep -Fq 'mode=cancel child-cancellations=1 child-drops=1 host-future-drops=1 table-empty=true' <<<"$output"
            ;;
    esac
    grep -Fq 'async-call root-terminal=1 duplicate-drop=0' <<<"$output"
    printf '%s\n' "$output"
done
printf 'rust-async-call-component gate passed\n'
