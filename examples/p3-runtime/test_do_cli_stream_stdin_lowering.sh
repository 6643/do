#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
source="$repo_root/examples/p3-runtime/cli-stream-stdin-component.do"
bounded_source="$repo_root/examples/p3-runtime/cli-stream-stdin-one-read.do"
wat=$(mktemp /tmp/do-cli-stream-stdin.XXXXXX.wat)
wit=$(mktemp /tmp/do-cli-stream-stdin.XXXXXX.wit)
core=$(mktemp /tmp/do-cli-stream-stdin.XXXXXX.wasm)
embedded=$(mktemp /tmp/do-cli-stream-stdin.XXXXXX.embedded.wasm)
component=$(mktemp /tmp/do-cli-stream-stdin.XXXXXX.component.wasm)
bounded_wat=$(mktemp /tmp/do-cli-stream-stdin-bounded.XXXXXX.wat)
bounded_wit=$(mktemp /tmp/do-cli-stream-stdin-bounded.XXXXXX.wit)
bounded_core=$(mktemp /tmp/do-cli-stream-stdin-bounded.XXXXXX.wasm)
bounded_embedded=$(mktemp /tmp/do-cli-stream-stdin-bounded.XXXXXX.embedded.wasm)
bounded_component=$(mktemp /tmp/do-cli-stream-stdin-bounded.XXXXXX.component.wasm)
trap 'rm -f "$wat" "$wit" "$core" "$embedded" "$component" "$bounded_wat" "$bounded_wit" "$bounded_core" "$bounded_embedded" "$bounded_component"' EXIT

"$do_bin" build --p3-async-component --p3-wit-output "$wit" "$source" -o "$wat"

grep -Fq '[stream-acquire]read-via-stream' "$wat"
grep -Fq 'stream.read' "$wat"
if grep -Fq 'future-cancel-read' "$wat"; then
    exit 1
fi
grep -Fq '[stream-eof]Err(nil)' "$wat"
grep -Fq '[stream-drop-readable]' "$wat"
grep -Fq 'future-drop-readable' "$wat"
if grep -Fq '[async-lower][future-read-1]' "$wat"; then
    exit 1
fi
if grep -Fq '__stream_completion_global' "$wat"; then
    exit 1
fi

wasm-tools parse "$wat" -o "$core"
wasm-tools component embed "$wit" "$core" --world stream-stdin-probe \
    -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

"$do_bin" build --p3-async-component --p3-wit-output "$bounded_wit" "$bounded_source" -o "$bounded_wat"
grep -Fq '(export "[async-lift]read-once"' "$bounded_wat"
grep -Fq '(export "[callback][async-lift]read-once"' "$bounded_wat"
grep -Fq 'i32.const 1' "$bounded_wat"
if grep -Fq '[stream-read-count]' "$bounded_wat"; then
    exit 1
fi
grep -Fq 'export read-once: async func()' "$bounded_wit"
wasm-tools parse "$bounded_wat" -o "$bounded_core"
wasm-tools component embed "$bounded_wit" "$bounded_core" --world stream-stdin-probe \
    -o "$bounded_embedded"
wasm-tools component new --skip-validation "$bounded_embedded" -o "$bounded_component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$bounded_component"

printf 'CLI stdin stream lowering passed\n'
