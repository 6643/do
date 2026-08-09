#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
current_wasm_tools=${WASM_TOOLS:-wasm-tools}
legacy_wasm_tools=${LEGACY_WASM_TOOLS:-/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools}
source="$repo_root/examples/p3-runtime/async-host-scalar-argument.do"
wit_snapshot="$repo_root/examples/p3-runtime/wit/async-call-arg-probe.wit"

test -x "$do_bin"
test -f "$source"
test -f "$wit_snapshot"

resolve_tool() {
    local requested=$1
    if [[ "$requested" == */* ]]; then
        test -x "$requested"
        printf '%s\n' "$requested"
    else
        command -v "$requested"
    fi
}

current_wasm_tools=$(resolve_tool "$current_wasm_tools")
legacy_wasm_tools=$(resolve_tool "$legacy_wasm_tools")
test "$("$current_wasm_tools" --version)" = "wasm-tools 1.255.0 (76e20611d 2026-07-30)"
test "$("$legacy_wasm_tools" --version)" = "wasm-tools 1.254.0 (bb58fdf91 2026-07-20)"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-async-host-scalar-argument.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/probe.wat"
wit="$tmp_dir/probe.wit"
core_wasm="$tmp_dir/probe.core.wasm"
embedded="$tmp_dir/probe.embedded.wasm"
component="$tmp_dir/probe.component.wasm"
legacy_core_wasm="$tmp_dir/probe.legacy.core.wasm"
legacy_component="$tmp_dir/probe.legacy.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
    --p3-async-host-arg-component --p3-wit-output "$wit" -o "$core_wat"
cmp "$wit_snapshot" "$wit"

for marker in \
    '[async-lower]work' \
    '[guest-async-arg-store]' \
    '[guest-async-arg-load]' \
    '[guest-async-child-drop]' \
    '[guest-async-waitable-drop]' \
    '[guest-async-context-clear]' \
    '[guest-async-frame-free]' \
    '[task-cancel]'; do
    grep -Fq "$marker" "$core_wat"
done
grep -Fq 'i32.const 20' "$core_wat"
grep -Fq 'i32.const 12' "$core_wat"
grep -Fq '[export]$root" "[task-return]run' "$core_wat"
if grep -Fq '[task-return]helper' "$core_wat" || grep -Fq '[async-lift]helper' "$core_wat"; then
    printf 'async host scalar argument emitted an independent helper endpoint\n' >&2
    exit 1
fi

# Current wasm-tools route.
"$current_wasm_tools" parse "$core_wat" -o "$core_wasm"
"$current_wasm_tools" component embed "$wit" "$core_wasm" \
    --world probe --features cm-async,cm-more-async-builtins -o "$embedded"
"$current_wasm_tools" component new --skip-validation "$embedded" -o "$component"
"$current_wasm_tools" validate --features cm-async,cm-more-async-builtins "$component"

# Pinned legacy route uses the compatibility custom-section assembler.
"$legacy_wasm_tools" parse "$core_wat" -o "$legacy_core_wasm"
WASM_TOOLS="$legacy_wasm_tools" bash "$repo_root/examples/p3-runtime/assemble_wasmtime_p3_legacy.sh" \
    "$wit" "$legacy_core_wasm" probe "$legacy_component"

test -s "$component"
test -s "$legacy_component"
printf 'do async host scalar argument Component gate passed current=%s legacy=%s frame=20 arg-slot=12 value=7\n' \
    "$current_wasm_tools" "$legacy_wasm_tools"
