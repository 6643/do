#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
do_bin=${DO_BIN:-$repo_root/bin/do}
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-c15b-call.do
wat_file=$(mktemp "${TMPDIR:-/tmp}/do-g5c-default-c15b.XXXXXX.wat")
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
    printf '[FAIL] C15-B default route still contains ARC runtime symbols\n' >&2
    exit 1
fi
rg -q '\(import "demo:marshal-record-managed-lower/api@1.0.0" "write" \(func \$__gc_canonical_call' "$wat_file"
rg -q '\(func \$write \(param \$input \(ref null \$writing\)\)' "$wat_file"
rg -q 'call \$__gc_canonical_call' "$wat_file"
rg -q 'call \$cabi_realloc' "$wat_file"

"$toolchain_bin" validate-core "$wat_file" >/dev/null
printf 'GREEN: C15-B ordinary @host_func uses the manifest-backed GC/WIT route\n'
