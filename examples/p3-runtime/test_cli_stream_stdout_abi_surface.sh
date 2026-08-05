#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit_file="$repo_root/examples/p3-runtime/wit/cli-stream-stdout.wit"
registry="$repo_root/src/build/p3_async_registry.json"
expected_hash="03ff93468efa2d4d3e58e441b924e3ee984d4d8b8080ca45646c92a14609acc4"
actual_hash=$(sha256sum "$wit_file" | awk '{print $1}')
test "$actual_hash" = "$expected_hash"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
wat_file="$work_dir/stream-stdout.wat"
wasm_file="$work_dir/stream-stdout.wasm"

wasm-tools component embed \
    "$wit_file" \
    --world stream-stdout-probe \
    --dummy-names legacy \
    --async-callback \
    -t > "$wat_file"
wasm-tools parse "$wat_file" -o "$wasm_file" >/dev/null

module='wasi:cli/stdout@0.3.0-rc-2025-09-16'
for import_name in \
    '[async-lower]write-via-stream' \
    '[stream-new-0]write-via-stream' \
    '[stream-cancel-read-0]write-via-stream' \
    '[stream-cancel-write-0]write-via-stream' \
    '[stream-drop-readable-0]write-via-stream' \
    '[stream-drop-writable-0]write-via-stream' \
    '[async-lower][stream-read-0]write-via-stream' \
    '[async-lower][stream-write-0]write-via-stream'; do
    grep -Fq "(import \"$module\" \"$import_name\"" "$wat_file"
done

grep -Fq '"member": "write-via-stream"' "$registry"
grep -Fq '"effect": "stream-writer"' "$registry"
printf 'P3 stdout stream-writer ABI verified: %s\n' "$module"
