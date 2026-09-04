#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SRC_DIR="$ROOT_DIR/src"

ZIG_BIN="${ZIG_BIN:-$(command -v zig || true)}"
ZIG_BIN="${ZIG_BIN:-/home/_/_/zig/zig}"

if [[ ! -x "$ZIG_BIN" ]]; then
    printf '[FAIL] zig binary not found: %s\n' "${ZIG_BIN:-<unset>}" >&2
    exit 1
fi

# Keep temporary files under an explicitly configured worktree root when one
# is supplied. The integration harness inherits RUN_WASM and RUN_GC_CORE.
if [[ -n "${TMPDIR:-}" ]]; then
    mkdir -p "$TMPDIR"
fi

cd "$SRC_DIR"
ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-/tmp/zig-cache}" \
ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-/tmp/zig-gcache}" \
exec "$ZIG_BIN" build test --summary all
