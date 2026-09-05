#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DO_BIN="${DO_BIN:-$ROOT_DIR/bin/do}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/do-gc-backend-firewall.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT

if [[ ! -x "$DO_BIN" ]]; then
    printf 'missing do compiler executable: %s\n' "$DO_BIN" >&2
    exit 1
fi

managed_wat="$TMP_DIR/managed-struct-set.wat"
if ! DO_LIB_ROOT="$ROOT_DIR/lib" "$DO_BIN" build "$ROOT_DIR/examples/gc-p3-runtime/managed-struct-set.do" -o "$managed_wat"; then
    printf 'managed GC fixture failed to build\n' >&2
    exit 1
fi
if ! rg -q '^  ;; backend=gc$' "$managed_wat"; then
    printf 'normal managed route lacks backend=gc marker\n' >&2
    exit 1
fi
if rg -q '__arc_|arc-runtime|arc-layout' "$managed_wat"; then
    printf 'normal managed route contains an ARC marker\n' >&2
    exit 1
fi

async_wat="$TMP_DIR/async-call-component.wat"
async_stderr="$TMP_DIR/async-call-component.stderr"
if DO_LIB_ROOT="$ROOT_DIR/lib" "$DO_BIN" build "$ROOT_DIR/examples/p3-runtime/async-call-component.do" -o "$async_wat" >"$TMP_DIR/async-call-component.stdout" 2>"$async_stderr"; then
    printf 'unsupported async source unexpectedly built\n' >&2
    exit 1
fi
if ! rg -q 'AsyncLoweringUnavailable' "$async_stderr"; then
    printf 'unsupported async source failed without AsyncLoweringUnavailable\n' >&2
    cat "$async_stderr" >&2
    exit 1
fi

printf 'GC backend firewall red/green checks passed\n'
