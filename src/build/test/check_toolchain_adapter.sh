#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TOOLCHAIN_BIN="$ROOT_DIR/bin/do-toolchain"
LOCK_FILE="$ROOT_DIR/toolchain/toolchain.lock.json"

if [[ ! -f "$LOCK_FILE" ]]; then
    printf '[FAIL] missing toolchain lock: %s\n' "$LOCK_FILE" >&2
    exit 1
fi
if [[ ! -x "$TOOLCHAIN_BIN" ]]; then
    printf '[FAIL] missing do-toolchain executable: %s\n' "$TOOLCHAIN_BIN" >&2
    exit 1
fi

probe_output="$(
    cd "$ROOT_DIR"
    DO_TOOLCHAIN_LOCK="$LOCK_FILE" "$TOOLCHAIN_BIN" probe
)" || {
    printf '[FAIL] do-toolchain probe failed\n' >&2
    exit 1
}

for marker in '"schema":1' '"wasm_tools":' '"wasmtime":' '"rust_wasmtime":'; do
    if [[ "$probe_output" != *"$marker"* ]]; then
        printf '[FAIL] toolchain probe missing marker: %s\n' "$marker" >&2
        exit 1
    fi
done

scan_args=(
    --glob '*.sh'
    --glob '!**/tmp/**'
    --glob '!test_wasm_tools_current_only.sh'
    --glob '!check_toolchain_adapter.sh'
    --glob '!check_toolchain_adapter_test.sh'
)

run_rg_no_match() {
    local output
    local status

    if output="$(rg "$@")"; then
        printf '%s' "$output"
        return 0
    else
        status=$?
    fi

    if [[ "$status" -eq 1 ]]; then
        return 0
    fi

    printf '[FAIL] raw command scan failed (rg exit %d)\n' "$status" >&2
    return "$status"
}

wasm_tools_command='(?:[^[:space:];|()=]*wasm-tools|\$(?:\{)?(?:WASM_TOOLS_BIN|WASM_TOOLS|wasm_tools_bin|wasm_tools)(?:\})?)'

if ! direct_tool_refs="$(run_rg_no_match -n --pcre2 \
    "^[[:space:]]*(?:(?:if|then|elif|while|until|do|!|command|env)[[:space:]]+)*(?:(?:[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+)[[:space:]]+)*\"?${wasm_tools_command}\"?(?:[[:space:]]+[^[:space:]]+|[[:space:]]*$)" \
    "${scan_args[@]}" "$ROOT_DIR/examples" "$ROOT_DIR/src/build/test")"; then
    exit 1
fi
if [[ -n "$direct_tool_refs" ]]; then
    printf '[FAIL] active shell invokes wasm-tools directly:\n%s\n' "$direct_tool_refs" >&2
    exit 1
fi

scan_wasm_tools_aliases() {
    local file
    local alias_refs

    while IFS= read -r -d '' file; do
        case "$file" in
            */check_toolchain_adapter.sh|*/check_toolchain_adapter_test.sh|*/test_wasm_tools_current_only.sh)
                continue
                ;;
        esac

        if ! alias_refs="$(awk '
            function alias_invocation(line, name, prefix) {
                prefix = "^[[:space:]]*((if|then|elif|while|until|do|!|command|env)[[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)*"
                return line ~ (prefix "\\\"?\\$" name "\\\"?[[:space:]]+[^[:space:]]+") ||
                    line ~ (prefix "\\\"?\\$\\{" name "\\}\\\"?[[:space:]]+[^[:space:]]+")
            }

            {
                if (index($0, "wasm-tools") > 0) {
                    rest = $0
                    while (match(rest, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/)) {
                        token = substr(rest, RSTART, RLENGTH)
                        name = token
                        sub(/[[:space:]]*=.*/, "", name)
                        rhs = substr(rest, RSTART + RLENGTH)
                        if (match(rhs, /[[:space:]][A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/)) {
                            segment = substr(rhs, 1, RSTART - 1)
                            rest = substr(rhs, RSTART + 1)
                        } else {
                            segment = rhs
                            rest = ""
                        }
                        if (segment ~ /wasm-tools/) {
                            aliases[name] = 1
                        } else {
                            for (source in aliases) {
                                if (segment ~ ("\\$\\{?" source "\\}?") ) {
                                    aliases[name] = 1
                                }
                            }
                        }
                    }
                }

                for (name in aliases) {
                    if (alias_invocation($0, name)) {
                        print FILENAME ":" FNR ":" $0
                        exit 0
                    }
                }
            }
        ' "$file")"; then
            printf '[FAIL] wasm-tools alias scan failed: %s\n' "$file" >&2
            return 1
        fi
        if [[ -n "$alias_refs" ]]; then
            printf '%s\n' "$alias_refs"
        fi
    done < <(find "$ROOT_DIR/examples" "$ROOT_DIR/src/build/test" -type f -name '*.sh' ! -path '*/tmp/*' -print0)
}

if ! alias_tool_refs="$(scan_wasm_tools_aliases)"; then
    exit 1
fi
if [[ -n "$alias_tool_refs" ]]; then
    printf '[FAIL] active shell invokes wasm-tools through an alias:\n%s\n' "$alias_tool_refs" >&2
    exit 1
fi

if ! legacy_refs="$(run_rg_no_match -n \
    -e '1\.254\.0' \
    -e '1\.255\.0' \
    -e 'legacy_wasm_tools' \
    -e 'LEGACY_WASM_TOOLS' \
    -e 'assemble_wasmtime_p3_legacy\.sh' \
    --glob '*.sh' \
    --glob '!**/tmp/**' \
    --glob '!test_wasm_tools_current_only.sh' \
    --glob '!check_toolchain_adapter.sh' \
    --glob '!check_toolchain_adapter_test.sh' \
    "$ROOT_DIR/examples" "$ROOT_DIR/src/build/test")"; then
    exit 1
fi
if [[ -n "$legacy_refs" ]]; then
    printf '[FAIL] active shell contains legacy toolchain references:\n%s\n' "$legacy_refs" >&2
    exit 1
fi

printf '[PASS] toolchain adapter active gate\n'
