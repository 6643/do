#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
wit="$repo_root/examples/p3-runtime/generic-async-runtime.wit"
core_wat="$repo_root/examples/p3-runtime/async-call-component-probe.wat"
local_core_wat="$repo_root/examples/p3-runtime/async-call-component-local-frame-probe.wat"

test -f "$wit"
test -f "$core_wat"
test -f "$local_core_wat"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-async-call-component-probe.XXXXXX")
core_wasm="$tmp_dir/probe.core.wasm"
local_core_wasm="$tmp_dir/local-frame.core.wasm"
embedded="$tmp_dir/probe.embedded.wasm"
component="$tmp_dir/probe.component.wasm"
local_embedded="$tmp_dir/local-frame.embedded.wasm"
local_component="$tmp_dir/local-frame.component.wasm"

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" parse-core "$local_core_wat" -o "$local_core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" probe \
  --features component-async -o "$embedded"

# The expected result of this first probe is a pinned ABI rejection: the WIT
# world has no async export named `helper`, so the synthetic task-return import
# cannot be wired to a guest child.  Keep the complete diagnostic in the test
# output instead of hiding it behind a fallback.
if "$toolchain_bin" new-component "$embedded" -o "$component" >"$tmp_dir/component-new.out" 2>"$tmp_dir/component-new.err"; then
  printf 'unexpectedly accepted internal [task-return]helper import\n' >&2
  exit 1
fi
cat "$tmp_dir/component-new.err" >&2
grep -Eiq 'helper|import|task|component' "$tmp_dir/component-new.err"

# The selected route keeps helper state inside the root task.  It has the same
# root imports and WIT metadata, but no synthetic `[task-return]helper` import.
"$toolchain_bin" embed-component "$wit" "$local_core_wasm" probe \
  --features component-async -o "$local_embedded"
"$toolchain_bin" new-component "$local_embedded" -o "$local_component"
"$toolchain_bin" validate-component "$local_component" --features component-async
printf 'async-call Component probe: independent-child=blocked local-frame=accepted\n'
