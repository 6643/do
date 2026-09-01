#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
do_bin=${DO_BIN:-$repo_root/bin/do}
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-mixed-lower-call.do
wat_file=$(mktemp "${TMPDIR:-/tmp}/do-g5c-default-mixed-lower.XXXXXX.wat")
trap 'rm -f "$wat_file"' EXIT

if [[ ! -x "$do_bin" ]]; then
    printf '[FAIL] missing do compiler executable: %s\n' "$do_bin" >&2
    exit 1
fi
if [[ ! -x "$toolchain_bin" ]]; then
    printf '[FAIL] missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
    exit 1
fi

"$do_bin" build "$input_do" -o "$wat_file" >/dev/null

rg -q ';; gc-sync ' "$wat_file"
if rg -q '__arc_' "$wat_file"; then
    printf '[FAIL] mixed scalar lower default route still contains ARC runtime symbols\n' >&2
    exit 1
fi
rg -q '\(import "demo:marshal-record-mixed-lower/api@1.0.0" "write" \(func \$__gc_canonical_call' "$wat_file"
rg -q '\(type \$canonical_lower \(func \(param i32 i64 i64\)\)\)' "$wat_file"
rg -q 'call \$__gc_canonical_call' "$wat_file"

"$toolchain_bin" validate-core "$wat_file" >/dev/null
printf 'GREEN: mixed scalar record lower uses the manifest-backed GC/WIT route\n'
