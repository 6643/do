#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/generic-async-runtime.wit"
core_wat="$repo_root/examples/p3-runtime/async-call-component-probe.wat"
local_core_wat="$repo_root/examples/p3-runtime/async-call-component-local-frame-probe.wat"

test -f "$wit"
test -f "$core_wat"
test -f "$local_core_wat"

readonly expected_version='wasm-tools 1.255.0 (76e20611d 2026-07-30)'
readonly expected_sha256='6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013'
wasm_tools=${WASM_TOOLS:-wasm-tools}
if [[ "$wasm_tools" == */* ]]; then
  test -x "$wasm_tools"
else
  wasm_tools=$(command -v "$wasm_tools")
fi
actual_version=$($wasm_tools --version)
test "$actual_version" = "$expected_version"
actual_sha256=$(sha256sum "$wasm_tools" | awk '{print $1}')
test "$actual_sha256" = "$expected_sha256"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-async-call-component-probe.XXXXXX")
core_wasm="$tmp_dir/probe.core.wasm"
local_core_wasm="$tmp_dir/local-frame.core.wasm"
embedded="$tmp_dir/probe.embedded.wasm"
component="$tmp_dir/probe.component.wasm"
local_embedded="$tmp_dir/local-frame.embedded.wasm"
local_component="$tmp_dir/local-frame.component.wasm"

"$wasm_tools" parse "$core_wat" -o "$core_wasm"
"$wasm_tools" parse "$local_core_wat" -o "$local_core_wasm"
"$wasm_tools" component embed "$wit" \
  "$core_wasm" --world probe --features cm-async,cm-more-async-builtins \
  -o "$embedded"

# The expected result of this first probe is a pinned ABI rejection: the WIT
# world has no async export named `helper`, so the synthetic task-return import
# cannot be wired to a guest child.  Keep the complete diagnostic in the test
# output instead of hiding it behind a fallback.
if "$wasm_tools" component new --skip-validation "$embedded" -o "$component" >"$tmp_dir/component-new.out" 2>"$tmp_dir/component-new.err"; then
  printf 'unexpectedly accepted internal [task-return]helper import\n' >&2
  exit 1
fi
cat "$tmp_dir/component-new.err" >&2
grep -Eiq 'helper|import|task|component' "$tmp_dir/component-new.err"

# The selected route keeps helper state inside the root task.  It has the same
# root imports and WIT metadata, but no synthetic `[task-return]helper` import.
"$wasm_tools" component embed "$wit" \
  "$local_core_wasm" --world probe \
  --features cm-async,cm-more-async-builtins -o "$local_embedded"
"$wasm_tools" component new --skip-validation "$local_embedded" -o "$local_component"
"$wasm_tools" validate --features cm-async,cm-more-async-builtins "$local_component"
printf 'async-call Component probe: independent-child=blocked local-frame=accepted\n'
