#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GATE="$ROOT_DIR/src/build/test/check_gc_default_build_gate.sh"
FIXTURE='ordinary-host-record-mixed-text-two-u32-lists-lower-call.do'

if ! rg -q "^${FIXTURE}$" "$GATE"; then
    printf '[FAIL] default GC gate does not enumerate %s\n' "$FIXTURE" >&2
    exit 1
fi

if ! rg -q '\[\[ "\$name" == ordinary-host-record-mixed-text-two-u32-lists-lower-call \]\]' "$GATE"; then
    printf '[FAIL] default GC gate lacks dedicated mixed text/two-u32-list assertions\n' >&2
    exit 1
fi

printf '[PASS] default GC gate covers mixed text/two-u32-list lower fixture and assertions\n'
