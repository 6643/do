#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
wit_snapshot="$repo_root/examples/p3-runtime/async-call-component.wit"
source="$repo_root/examples/p3-runtime/async-call-component.do"
legacy_wasm_tools=${WASM_TOOLS:-/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools}
test -x "$do_bin"
test -x "$legacy_wasm_tools"
test -f "$wit_snapshot"
test -f "$source"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-async-call-component.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/async-call.wat"
wit="$tmp_dir/async-call.wit"
core_wasm="$tmp_dir/async-call.core.wasm"
component="$tmp_dir/async-call.component.wasm"

"$do_bin" build "$source" --p3-async-call-component --p3-wit-output "$wit" -o "$core_wat"
cmp "$wit_snapshot" "$wit"
for marker in \
    '[guest-inline-helper]' \
    '[guest-inline-resume]' \
    '[guest-async-child]' \
    '[guest-async-parent-resume]' \
    '[guest-async-child-drop]' \
    '[guest-async-root-terminal]'; do
    grep -Fq "$marker" "$core_wat"
done
test "$(grep -o 'call \$host-work' "$core_wat" | wc -l)" -eq 2
if grep -Fq '[task-return]helper' "$core_wat" || grep -Fq '[async-lift]helper' "$core_wat"; then
    printf 'async-call emitted an independent helper endpoint\n' >&2
    exit 1
fi

"$legacy_wasm_tools" parse "$core_wat" -o "$core_wasm"
WASM_TOOLS="$legacy_wasm_tools" bash "$repo_root/examples/p3-runtime/assemble_wasmtime_p3_legacy.sh" \
    "$wit" "$core_wasm" probe "$component"

v1_wat="$tmp_dir/v1.wat"
v1_wit="$tmp_dir/v1.wit"
set +e
"$do_bin" build "$source" --p3-async-component --p3-wit-output "$v1_wit" -o "$v1_wat" \
    >"$tmp_dir/v1.stdout" 2>"$tmp_dir/v1.stderr"
v1_status=$?
set -e
if [[ "$v1_status" -eq 0 ]]; then
    if grep -Fq '[guest-async-child]' "$v1_wat" ||
        grep -Fq '[guest-async-parent-resume]' "$v1_wat" ||
        grep -Fq '[guest-async-child-drop]' "$v1_wat" ||
        grep -Fq '[guest-async-root-terminal]' "$v1_wat"; then
        printf 'v1 emitted async-call markers\n' >&2
        exit 1
    fi
    printf 'v1-isolation=accepted-without-async-call-markers\n'
else
    grep -Fq 'UnsupportedP3AsyncComponent' "$tmp_dir/v1.stderr"
    printf 'v1-isolation=rejected-before-wat\n'
fi
printf 'do-async-call-component gate passed\n'
