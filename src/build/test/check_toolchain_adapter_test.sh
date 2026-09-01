#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GATE="$ROOT_DIR/src/build/test/check_toolchain_adapter.sh"

[[ -x "$GATE" ]] || {
    printf '[FAIL] missing executable toolchain adapter gate: %s\n' "$GATE" >&2
    exit 1
}

root_output="$($GATE)"
grep -Fq '[PASS] toolchain adapter active gate' <<<"$root_output"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/do-toolchain-adapter-test.XXXXXX")"
trap 'rm -rf -- "$tmp_dir"' EXIT
tmp_output="$(cd "$tmp_dir" && "$GATE")"
grep -Fq '[PASS] toolchain adapter active gate' <<<"$tmp_output"

printf '[PASS] toolchain adapter gate test\n'
