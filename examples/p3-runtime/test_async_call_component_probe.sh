#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/generic-async-runtime.wit"
core_wat="$repo_root/examples/p3-runtime/async-call-component-probe.wat"
local_core_wat="$repo_root/examples/p3-runtime/async-call-component-local-frame-probe.wat"

test -f "$wit"
test -f "$core_wat"
test -f "$local_core_wat"

readonly expected_version='wasm-tools 1.254.0 (bb58fdf91 2026-07-20)'
readonly expected_sha256='cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6'
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
dummy_wat="$tmp_dir/dummy.wat"
custom_wat="$tmp_dir/probe.with-custom.wat"
custom_wasm="$tmp_dir/probe.with-custom.wasm"
component="$tmp_dir/probe.component.wasm"
local_custom_wat="$tmp_dir/local-frame.with-custom.wat"
local_custom_wasm="$tmp_dir/local-frame.with-custom.wasm"
local_component="$tmp_dir/local-frame.component.wasm"

"$wasm_tools" parse "$core_wat" -o "$core_wasm"
"$wasm_tools" parse "$local_core_wat" -o "$local_core_wasm"
"$wasm_tools" component embed "$wit" \
  --world probe --dummy-names legacy --async-callback -t > "$dummy_wat"
custom_line=$(grep '^  (@custom "component-type"' "$dummy_wat" || true)
test -n "$custom_line"
"$wasm_tools" strip -a "$core_wasm" -o "$tmp_dir/probe.stripped.wasm"
"$wasm_tools" print "$tmp_dir/probe.stripped.wasm" > "$tmp_dir/probe.stripped.wat"
sed '$d' "$tmp_dir/probe.stripped.wat" > "$custom_wat"
printf '%s\n' "$custom_line" ')' >> "$custom_wat"
"$wasm_tools" parse "$custom_wat" -o "$custom_wasm"

# The expected result of this first probe is a pinned ABI rejection: the WIT
# world has no async export named `helper`, so the synthetic task-return import
# cannot be wired to a guest child.  Keep the complete diagnostic in the test
# output instead of hiding it behind a fallback.
if "$wasm_tools" component new --skip-validation "$custom_wasm" -o "$component" >"$tmp_dir/component-new.out" 2>"$tmp_dir/component-new.err"; then
  printf 'unexpectedly accepted internal [task-return]helper import\n' >&2
  exit 1
fi
cat "$tmp_dir/component-new.err" >&2
grep -Eiq 'helper|import|task|component' "$tmp_dir/component-new.err"

# The selected route keeps helper state inside the root task.  It has the same
# root imports and WIT metadata, but no synthetic `[task-return]helper` import.
"$wasm_tools" strip -a "$local_core_wasm" -o "$tmp_dir/local-frame.stripped.wasm"
"$wasm_tools" print "$tmp_dir/local-frame.stripped.wasm" > "$tmp_dir/local-frame.stripped.wat"
sed '$d' "$tmp_dir/local-frame.stripped.wat" > "$local_custom_wat"
printf '%s\n' "$custom_line" ')' >> "$local_custom_wat"
"$wasm_tools" parse "$local_custom_wat" -o "$local_custom_wasm"
"$wasm_tools" component new --skip-validation "$local_custom_wasm" -o "$local_component"
"$wasm_tools" validate --features cm-async,cm-more-async-builtins "$local_component"
printf 'async-call Component probe: independent-child=blocked local-frame=accepted\n'
