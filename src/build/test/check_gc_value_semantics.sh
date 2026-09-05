#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DO_BIN="${DO_BIN:-$ROOT_DIR/bin/do}"
TOOLCHAIN_BIN="${DO_TOOLCHAIN_BIN:-$ROOT_DIR/bin/do-toolchain}"
WASMTIME_BIN="${WASMTIME_BIN:-$(command -v wasmtime || true)}"
ZIG_BIN="${ZIG_BIN:-$(command -v zig || true)}"
FIXTURE="$ROOT_DIR/examples/gc-p3-runtime/gc-value-copy-update.do"
EXPECTED_FILE="$ROOT_DIR/examples/gc-p3-runtime/gc-value-copy-update.expected"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/do-gc-value-semantics.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT

if [[ ! -x "$DO_BIN" ]]; then
    printf 'missing do compiler executable: %s\n' "$DO_BIN" >&2
    exit 1
fi
if [[ ! -x "$TOOLCHAIN_BIN" ]]; then
    printf 'missing do-toolchain executable: %s\n' "$TOOLCHAIN_BIN" >&2
    exit 1
fi
if [[ -z "$WASMTIME_BIN" || ! -x "$WASMTIME_BIN" ]]; then
    printf 'missing Wasmtime executable: %s\n' "${WASMTIME_BIN:-<unset>}" >&2
    exit 1
fi
if [[ -z "$ZIG_BIN" || ! -x "$ZIG_BIN" ]]; then
    printf 'missing Zig executable: %s\n' "${ZIG_BIN:-<unset>}" >&2
    exit 1
fi

wat="$TMP_DIR/gc-value-copy-update.wat"
if ! DO_LIB_ROOT="$ROOT_DIR/lib" "$DO_BIN" build "$FIXTURE" -o "$wat" >"$TMP_DIR/build.stdout" 2>"$TMP_DIR/build.stderr"; then
    printf 'GC value fixture failed to build\n' >&2
    cat "$TMP_DIR/build.stderr" >&2
    exit 1
fi
if ! rg -q '^  ;; backend=gc$' "$wat"; then
    printf 'GC value fixture lacks backend=gc marker\n' >&2
    exit 1
fi
if rg -q '__arc_|arc-runtime|arc-layout' "$wat"; then
    printf 'GC value fixture contains an ARC marker\n' >&2
    exit 1
fi
for marker in \
    ';; gc-value-replacement' \
    ';; gc-root-read' \
    ';; gc-unique-reuse'; do
    if ! rg -q "$marker" "$wat"; then
        printf 'GC value fixture lacks marker: %s\n' "$marker" >&2
        exit 1
    fi
done

probe_wat="$TMP_DIR/gc-value-copy-update.probe.wat"
if ! "$ZIG_BIN" run "$ROOT_DIR/src/build/gc_sync_probe.zig" -- "$FIXTURE" "$probe_wat" update >"$TMP_DIR/probe.stdout" 2>"$TMP_DIR/probe.stderr"; then
    printf 'GC value Core-GC probe generation failed\n' >&2
    cat "$TMP_DIR/probe.stderr" >&2
    exit 1
fi
probe_wasm="$TMP_DIR/gc-value-copy-update.probe.wasm"
"$TOOLCHAIN_BIN" parse-core "$probe_wat" -o "$probe_wasm" >/dev/null
"$WASMTIME_BIN" compile -W gc=y -o "$TMP_DIR/gc-value-copy-update.probe.compiled" "$probe_wat" >/dev/null
actual="$($WASMTIME_BIN -W gc=y --invoke probe "$probe_wat")"
expected="$(tr -d '\r\n' < "$EXPECTED_FILE")"
if [[ "$actual" != "$expected" ]]; then
    printf 'GC value Core-GC probe returned %s, expected %s\n' "$actual" "$expected" >&2
    exit 1
fi

printf 'GC value semantics gate passed: result=%s\n' "$actual"
