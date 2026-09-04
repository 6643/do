#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
wit="$repo_root/examples/p3-runtime/async-call-component.wit"
core_wat="$repo_root/examples/p3-runtime/async-call-scalar-argument-probe.wat"
test -x "$toolchain_bin"
test -f "$wit"
test -f "$core_wat"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-async-call-scalar-probe.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT
core_wasm="$tmp_dir/core.wasm"
dummy_wat="$tmp_dir/dummy.wat"
custom_wat="$tmp_dir/core-with-custom.wat"
custom_wasm="$tmp_dir/core-with-custom.wasm"
component="$tmp_dir/component.wasm"

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component-template "$wit" probe > "$dummy_wat"
custom_line=$(grep '^  (@custom "component-type"' "$dummy_wat" || true)
test -n "$custom_line"
"$toolchain_bin" strip-core "$core_wasm" -o "$tmp_dir/stripped.wasm"
"$toolchain_bin" print-component "$tmp_dir/stripped.wasm" > "$tmp_dir/stripped.wat"
sed '$d' "$tmp_dir/stripped.wat" > "$custom_wat"
printf '%s\n' "$custom_line" ')' >> "$custom_wat"
"$toolchain_bin" parse-core "$custom_wat" -o "$custom_wasm"
grep -q '\[guest-async-arg-store\]' "$core_wat"
grep -q '\[guest-async-arg-load\]' "$core_wat"
grep -q '\[guest-async-parent-resume\]' "$core_wat"
! grep -q '\[task-return\]helper' "$core_wat"
"$toolchain_bin" new-component "$custom_wasm" -o "$component"
"$toolchain_bin" validate-component "$component"

printf 'async-call scalar argument probe: toolchain=adapter frame-slot=u32@12 component=accepted\n'
