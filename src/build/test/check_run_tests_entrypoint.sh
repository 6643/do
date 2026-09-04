#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_ZIG="$TMP_DIR/zig"
LOG_FILE="$TMP_DIR/invocation.log"
cat >"$FAKE_ZIG" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

{
    printf 'cwd=%s\n' "$PWD"
    printf 'args='
    for arg in "$@"; do
        printf '%s|' "$arg"
    done
    printf '\n'
    printf 'local=%s\n' "${ZIG_LOCAL_CACHE_DIR:-}"
    printf 'global=%s\n' "${ZIG_GLOBAL_CACHE_DIR:-}"
    printf 'run_wasm=%s\n' "${RUN_WASM:-}"
    printf 'run_gc_core=%s\n' "${RUN_GC_CORE:-}"
} >"$FAKE_LOG"

if [[ "$*" != "build test --summary all" ]]; then
    exit 7
fi
EOF
chmod +x "$FAKE_ZIG"

status=0
FAKE_LOG="$LOG_FILE" \
ZIG_BIN="$FAKE_ZIG" \
ZIG_LOCAL_CACHE_DIR="$TMP_DIR/zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$TMP_DIR/zig-global-cache" \
RUN_WASM=1 \
RUN_GC_CORE=1 \
"$ROOT_DIR/src/build/test/run_tests.sh" || status=$?

if [[ "$status" -ne 0 ]]; then
    echo "run_tests.sh did not delegate successfully (exit=$status)"
    cat "$LOG_FILE" 2>/dev/null || true
    exit 1
fi

grep -Fqx "cwd=$ROOT_DIR/src" "$LOG_FILE"
grep -Fqx "args=build|test|--summary|all|" "$LOG_FILE"
grep -Fqx "local=$TMP_DIR/zig-cache" "$LOG_FILE"
grep -Fqx "global=$TMP_DIR/zig-global-cache" "$LOG_FILE"
grep -Fqx "run_wasm=1" "$LOG_FILE"
grep -Fqx "run_gc_core=1" "$LOG_FILE"

echo "run_tests.sh entrypoint contract passed"
