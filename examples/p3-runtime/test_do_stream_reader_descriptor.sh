#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
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

"$toolchain_bin" parse-core "$wat" -o "$core"
"$toolchain_bin" embed-component "$wit" "$core" stream-probe -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"

printf 'descriptor-owned stream reader lowering passed\n'
