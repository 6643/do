#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source="$repo_root/examples/p3-runtime/async-call-inline-scalar-argument.do"
wit_snapshot="$repo_root/examples/p3-runtime/async-call-component.wit"
legacy_wasm_tools=${WASM_TOOLS:-/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools}
component_output=${1:-/tmp/async-call-inline-scalar-argument.component.wasm}

test -x "$do_bin"
test -x "$legacy_wasm_tools"
test -f "$source"
test -f "$wit_snapshot"

component_dir=$(dirname -- "$component_output")
mkdir -p "$component_dir"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-async-call-inline-scalar-argument.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/async-call-inline-scalar-argument.wat"
wit="$tmp_dir/async-call-inline-scalar-argument.wit"
core_wasm="$tmp_dir/async-call-inline-scalar-argument.core.wasm"
component="$tmp_dir/async-call-inline-scalar-argument.component.wasm"

"$do_bin" build "$source" --p3-async-call-component --p3-wit-output "$wit" -o "$core_wat"
cmp "$wit_snapshot" "$wit"
for marker in \
    '[guest-inline-helper]' \
    '[guest-inline-arg-store]' \
    '[guest-inline-arg-load]' \
    '[guest-inline-resume]' \
    '[guest-async-child]' \
    '[guest-async-arg-store]' \
    '[guest-async-arg-load]' \
    '[guest-async-parent-resume]' \
    '[guest-async-child-drop]' \
    '[guest-async-root-terminal]'; do
    grep -Fq "$marker" "$core_wat"
done
test "$(grep -o 'call \$host-work' "$core_wat" | wc -l)" -eq 2
grep -Fq 'i32.const 7' "$core_wat"
grep -Fq 'i32.const 20' "$core_wat"
if grep -Fq '[task-return]helper' "$core_wat" || grep -Fq '[async-lift]helper' "$core_wat"; then
    printf 'inline scalar async-call emitted an independent helper endpoint\n' >&2
    exit 1
fi

"$legacy_wasm_tools" parse "$core_wat" -o "$core_wasm"
WASM_TOOLS="$legacy_wasm_tools" bash "$repo_root/examples/p3-runtime/assemble_wasmtime_p3_legacy.sh" \
    "$wit" "$core_wasm" probe "$component"
cp "$component" "$component_output"
test -s "$component_output"

printf 'do inline scalar async-call gate passed component=%s frame-slot=u32@12 value=7\n' \
    "$component_output"
