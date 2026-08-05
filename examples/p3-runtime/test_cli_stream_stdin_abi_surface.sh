#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/wit/cli-stream-stdin.wit"

if [[ ! -f "$wit" ]]; then
    echo "missing pinned CLI stdin stream WIT: $wit" >&2
    exit 1
fi

output=$(wasm-tools component embed "$wit" --world stream-stdin-probe \
    --dummy-names legacy --async-callback -t)

grep -Fq '"wasi:cli/stdin@0.3.0-rc-2025-09-16" "read-via-stream"' <<<"$output"
grep -Fq '(param i32)' <<<"$output"
grep -Fq '"$root" "[waitable-set-new]"' <<<"$output"
grep -Fq '"[export]$root" "[task-return]run"' <<<"$output"

printf 'CLI stdin stream ABI surface passed\n'
