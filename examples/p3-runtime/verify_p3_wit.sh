#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit_file="$repo_root/examples/p3-runtime/wit/wasi-clocks-0.3.0.wit"
manifest="$repo_root/examples/p3-runtime/p3-clocks-manifest.json"

test -f "$wit_file"
test -f "$manifest"

expected_hash=$(sed -n 's/.*"wit_sha256":[[:space:]]*"\([0-9a-f]*\)".*/\1/p' "$manifest")
actual_hash=$(sha256sum "$wit_file" | awk '{print $1}')
if [[ "$expected_hash" != "$actual_hash" ]]; then
    printf 'P3 WIT hash mismatch: expected=%s actual=%s\n' "$expected_hash" "$actual_hash" >&2
    exit 1
fi

grep -Fq '"wasmtime_commit": "90fed3c6adf53f112c4dea56851728557bb73799"' "$manifest"
grep -Fq '"package": "wasi:clocks@0.3.0"' "$manifest"
grep -Fq '"interface": "monotonic-clock"' "$manifest"
grep -Fq '"member": "wait-for"' "$manifest"
grep -Fq '"effect": "async"' "$manifest"

wasm-tools component wit "$wit_file" >/dev/null
printf 'P3 WIT snapshot verified: wasi:clocks/monotonic-clock.wait-for\n'
