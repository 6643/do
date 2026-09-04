#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
toolchain_bin=${DO_TOOLCHAIN_BIN:-"$repo_root/bin/do-toolchain"}
source="$repo_root/examples/p3-runtime/async-host-scalar-argument.do"
wit_snapshot="$repo_root/examples/p3-runtime/wit/async-call-arg-probe.wit"

test -x "$do_bin"
test -x "$toolchain_bin"
test -f "$source"
test -f "$wit_snapshot"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-async-host-scalar-argument.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/probe.wat"
wit="$tmp_dir/probe.wit"
core_wasm="$tmp_dir/probe.core.wasm"
embedded="$tmp_dir/probe.embedded.wasm"
component="$tmp_dir/probe.component.wasm"

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

# Current-only toolchain adapter route.
"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" probe -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"

test -s "$component"
printf 'do async host scalar argument Component gate passed wasm-tools=%s frame=20 arg-slot=12 value=7\n' \
    "$toolchain_bin"
