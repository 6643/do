#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wat=$(mktemp /tmp/do-cli-stream-stdout.XXXXXX.wat)
wit=$(mktemp /tmp/do-cli-stream-stdout.XXXXXX.wit)
core=$(mktemp /tmp/do-cli-stream-stdout.XXXXXX.wasm)
component=$(mktemp /tmp/do-cli-stream-stdout.XXXXXX.component.wasm)
trap 'rm -f "$wat" "$wit" "$core" "$component"' EXIT

"$repo_root/bin/do" build --p3-async-component --p3-wit-output "$wit" \
    "$repo_root/examples/p3-runtime/cli-stream-stdout-component.do" -o "$wat"

grep -Fq '[async-lower]write-via-stream' "$wat"
grep -Fq '[stream-new-0]write-via-stream' "$wat"
grep -Fq '[async-lower][stream-write-0]write-via-stream' "$wat"
grep -Fq '[stream-drop-writable-0]write-via-stream' "$wat"
grep -Fq '(export "[async-lift]write"' "$wat"

wasm-tools parse "$wat" -o "$core"
bash "$repo_root/examples/p3-runtime/assemble_async_component.sh" \
    "$wit" "$core" stream-stdout-probe "$component"

printf 'CLI stdout stream lowering passed\n'
