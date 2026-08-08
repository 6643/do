#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/async-call-component.wit"
core_wat="$repo_root/examples/p3-runtime/async-call-scalar-argument-probe.wat"
test -f "$wit"
test -f "$core_wat"

wasm_tools=${WASM_TOOLS:-wasm-tools}
if [[ "$wasm_tools" == */* ]]; then
  test -x "$wasm_tools"
else
  wasm_tools=$(command -v "$wasm_tools")
fi

expected=${WASM_TOOLS_EXPECT_VERSION:-1.254.0}
case "$expected" in
  1.255.0)
    expected_version='wasm-tools 1.255.0 (76e20611d 2026-07-30)'
    expected_sha256='6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013'
    ;;
  1.254.0)
    expected_version='wasm-tools 1.254.0 (bb58fdf91 2026-07-20)'
    expected_sha256='cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6'
    ;;
  *)
    printf 'unsupported probe version selector: %s\n' "$expected" >&2
    exit 2
    ;;
esac

actual_version=$($wasm_tools --version)
test "$actual_version" = "$expected_version"
actual_sha256=$(sha256sum "$wasm_tools" | awk '{print $1}')
test "$actual_sha256" = "$expected_sha256"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-async-call-scalar-probe.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT
core_wasm="$tmp_dir/core.wasm"
dummy_wat="$tmp_dir/dummy.wat"
custom_wat="$tmp_dir/core-with-custom.wat"
custom_wasm="$tmp_dir/core-with-custom.wasm"
component="$tmp_dir/component.wasm"

"$wasm_tools" parse "$core_wat" -o "$core_wasm"
"$wasm_tools" component embed "$wit" \
  --world probe --dummy-names legacy --async-callback -t > "$dummy_wat"
custom_line=$(grep '^  (@custom "component-type"' "$dummy_wat" || true)
test -n "$custom_line"
"$wasm_tools" strip -a "$core_wasm" -o "$tmp_dir/stripped.wasm"
"$wasm_tools" print "$tmp_dir/stripped.wasm" > "$tmp_dir/stripped.wat"
sed '$d' "$tmp_dir/stripped.wat" > "$custom_wat"
printf '%s\n' "$custom_line" ')' >> "$custom_wat"
"$wasm_tools" parse "$custom_wat" -o "$custom_wasm"
grep -q '\[guest-async-arg-store\]' "$core_wat"
grep -q '\[guest-async-arg-load\]' "$core_wat"
grep -q '\[guest-async-parent-resume\]' "$core_wat"
! grep -q '\[task-return\]helper' "$core_wat"
"$wasm_tools" component new --skip-validation "$custom_wasm" -o "$component"
"$wasm_tools" validate --features cm-async,cm-more-async-builtins "$component"

printf 'async-call scalar argument probe: version=%s sha256=%s frame-slot=u32@12 component=accepted\n' \
  "$actual_version" "$actual_sha256"
