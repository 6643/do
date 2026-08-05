#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
source="$repo_root/examples/p3-runtime/stream-probe-component.do"
wat=$(mktemp /tmp/do-stream-probe.XXXXXX.wat)
wit=$(mktemp /tmp/do-stream-probe.XXXXXX.wit)
core=$(mktemp /tmp/do-stream-probe.XXXXXX.wasm)
embedded=$(mktemp /tmp/do-stream-probe.XXXXXX.embedded.wasm)
component=$(mktemp /tmp/do-stream-probe.XXXXXX.component.wasm)
trap 'rm -f "$wat" "$wit" "$core" "$embedded" "$component"' EXIT

"$do_bin" build --p3-async-component --p3-wit-output "$wit" "$source" -o "$wat"
grep -Fq '"do:stream-probe/source@0.1.0" "read-via-stream"' "$wat"
grep -Fq '"[async-lower][stream-read-0]read-via-stream"' "$wat"
grep -Fq '"[future-drop-readable-1]read-via-stream"' "$wat"
if grep -Fq 'wasi:cli/stdin' "$wat"; then
    exit 1
fi
grep -Fq 'package do:stream-probe@0.1.0' "$wit"
grep -Fq 'world stream-probe' "$wit"

wasm-tools parse "$wat" -o "$core"
wasm-tools component embed "$wit" "$core" --world stream-probe -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

printf 'descriptor-owned stream reader lowering passed\n'
