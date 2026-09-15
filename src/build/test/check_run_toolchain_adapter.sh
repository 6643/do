#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DO_BIN="$ROOT_DIR/bin/do"
INPUT="$ROOT_DIR/src/build/test/run/01_start_scalar.do"

if [[ ! -x "$DO_BIN" ]]; then
    printf '[FAIL] missing do executable: %s\n' "$DO_BIN" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/do-run-toolchain-adapter.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT

FAKE_BIN_DIR="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN_DIR"

ADAPTER_LOG="$TMP_DIR/adapter.log"
WASM_TOOLS_LOG="$TMP_DIR/wasm-tools.log"
NODE_LOG="$TMP_DIR/node.log"

cat >"$FAKE_BIN_DIR/do-toolchain" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$DO_RUN_ADAPTER_LOG"
if [[ "$#" -ne 4 || "$1" != "parse-core" || "$3" != "-o" ]]; then
    exit 2
fi
: >"$4"
EOF
chmod +x "$FAKE_BIN_DIR/do-toolchain"

cat >"$FAKE_BIN_DIR/wasm-tools" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$DO_RUN_WASM_TOOLS_LOG"
if [[ "$#" -ne 4 || "$1" != "parse" || "$3" != "-o" ]]; then
    exit 2
fi
: >"$4"
EOF
chmod +x "$FAKE_BIN_DIR/wasm-tools"

cat >"$FAKE_BIN_DIR/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$DO_RUN_NODE_LOG"
EOF
chmod +x "$FAKE_BIN_DIR/node"

wat_path="$TMP_DIR/out.wat"
stderr_path="$TMP_DIR/run.stderr"
stdout_path="$TMP_DIR/run.stdout"

if ! DO_LIB_ROOT="$ROOT_DIR/lib" \
    DO_TOOLCHAIN_BIN="$FAKE_BIN_DIR/do-toolchain" \
    DO_RUN_ADAPTER_LOG="$ADAPTER_LOG" \
    DO_RUN_WASM_TOOLS_LOG="$WASM_TOOLS_LOG" \
    DO_RUN_NODE_LOG="$NODE_LOG" \
    NODE_BIN="$FAKE_BIN_DIR/node" \
    PATH="$FAKE_BIN_DIR:/usr/bin:/bin" \
    "$DO_BIN" run "$INPUT" >"$stdout_path" 2>"$stderr_path"; then
    printf '[FAIL] do run failed while exercising the toolchain adapter\n' >&2
    cat "$stderr_path" >&2
    exit 1
fi

if [[ ! -s "$ADAPTER_LOG" ]]; then
    printf '[FAIL] do run did not invoke DO_TOOLCHAIN_BIN parse-core\n' >&2
    cat "$stderr_path" >&2
    exit 1
fi
grep -Fq 'parse-core ' "$ADAPTER_LOG"

if [[ -s "$WASM_TOOLS_LOG" ]]; then
    printf '[FAIL] do run invoked wasm-tools directly:\n' >&2
    cat "$WASM_TOOLS_LOG" >&2
    exit 1
fi

if [[ ! -s "$NODE_LOG" ]]; then
    printf '[FAIL] do run did not invoke the configured node runtime\n' >&2
    exit 1
fi

printf 'do run toolchain adapter contract passed\n'
