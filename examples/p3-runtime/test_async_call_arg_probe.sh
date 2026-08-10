#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/wit/async-call-arg-probe.wit"
core_wat="$repo_root/examples/p3-runtime/async-call-arg-probe-canonical.wat"

test -f "$wit"
test -f "$core_wat"

wasm_tools=${WASM_TOOLS:-wasm-tools}
if [[ "$wasm_tools" == */* ]]; then
  test -x "$wasm_tools"
else
  wasm_tools=$(command -v "$wasm_tools")
fi

expected_version='wasm-tools 1.255.0 (76e20611d 2026-07-30)'
expected_sha256='6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013'

actual_version=$($wasm_tools --version)
test "$actual_version" = "$expected_version"
actual_sha256=$(sha256sum "$wasm_tools" | awk '{print $1}')
test "$actual_sha256" = "$expected_sha256"

grep -Fq 'package do:async-call-arg-probe@0.1.0;' "$wit"
grep -Fq 'work: async func(value: u32);' "$wit"
grep -Fq 'export run: async func();' "$wit"
wit_sha256=$(sha256sum "$wit" | awk '{print $1}')

for marker in \
  '[guest-async-arg-store]' \
  '[guest-async-host-arg]' \
  '[guest-async-arg-load]' \
  '[guest-async-parent-resume]' \
  '[guest-async-child-drop]' \
  '[guest-async-waitable-drop]' \
  '[guest-async-context-clear]' \
  '[guest-async-frame-free]'; do
  grep -Fq "$marker" "$core_wat"
done
for forbidden in '[task-return]helper' '[resource-drop]' 'stream-' 'list-'; do
  if grep -Fq "$forbidden" "$core_wat"; then
    printf 'forbidden canonical marker: %s\n' "$forbidden" >&2
    exit 1
  fi
done

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-async-call-arg-probe.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
core_wasm="$tmp_dir/core.wasm"
stripped_wasm="$tmp_dir/stripped.wasm"
stripped_wat="$tmp_dir/stripped.wat"
custom_wat="$tmp_dir/custom.wat"
custom_wasm="$tmp_dir/custom.wasm"
component="$tmp_dir/component.wasm"

"$wasm_tools" parse "$core_wat" -o "$core_wasm"
"$wasm_tools" component embed "$wit" \
  --world probe --dummy-names legacy --async-callback -t > "$tmp_dir/dummy.wat"
custom_line=$(grep '^  (@custom "component-type"' "$tmp_dir/dummy.wat" || true)
test -n "$custom_line"
"$wasm_tools" strip -a "$core_wasm" -o "$stripped_wasm"
"$wasm_tools" print "$stripped_wasm" > "$stripped_wat"
sed '$d' "$stripped_wat" > "$custom_wat"
printf '%s\n' "$custom_line" ')' >> "$custom_wat"
"$wasm_tools" parse "$custom_wat" -o "$custom_wasm"
"$wasm_tools" component new --skip-validation "$custom_wasm" -o "$component"
"$wasm_tools" validate --features cm-async,cm-more-async-builtins "$component"

# A changed scalar width or parameter arity must fail before Component
# assembly. The canonical Core import remains the measured one-u32 shape.
for shape in u64 two-params; do
  mutated_wit="$tmp_dir/$shape.wit"
  cp "$wit" "$mutated_wit"
  if [[ "$shape" == u64 ]]; then
    sed -i 's/value: u32/value: u64/' "$mutated_wit"
  else
    sed -i 's/value: u32/value: u32, extra: u32/' "$mutated_wit"
  fi
  "$wasm_tools" component embed "$mutated_wit" \
    --world probe --dummy-names legacy --async-callback -t > "$tmp_dir/$shape.dummy.wat"
  mutated_line=$(grep '^  (@custom "component-type"' "$tmp_dir/$shape.dummy.wat" || true)
  test -n "$mutated_line"
  mutated_wat="$tmp_dir/$shape.custom.wat"
  mutated_wasm="$tmp_dir/$shape.custom.wasm"
  sed '$d' "$stripped_wat" > "$mutated_wat"
  printf '%s\n' "$mutated_line" ')' >> "$mutated_wat"
  "$wasm_tools" parse "$mutated_wat" -o "$mutated_wasm"
  if "$wasm_tools" component new --skip-validation "$mutated_wasm" \
      -o "$tmp_dir/$shape.component.wasm" >"$tmp_dir/$shape.out" 2>"$tmp_dir/$shape.err"; then
    printf 'negative shape unexpectedly assembled: %s\n' "$shape" >&2
    exit 1
  fi
done

for boundary in \
  non-literal-root-argument \
  missing-call-argument \
  extra-call-argument \
  helper-payload-return \
  second-await \
  multiple-live-children \
  resource-payload \
  list-payload \
  stream-payload \
  borrowed-payload \
  future-payload \
  independent-helper-task \
  legacy-async-declaration; do
  printf 'boundary=%s status=reserved\n' "$boundary"
done

component_path="$component"
if [[ -n "${PROBE_COMPONENT_OUT:-}" ]]; then
  cp "$component" "$PROBE_COMPONENT_OUT"
  component_path=$PROBE_COMPONENT_OUT
fi

printf 'async-call arg probe: version=%s sha256=%s wit-sha256=%s frame-size=20 argument-offset=12 component=%s\n' \
  "$actual_version" "$actual_sha256" "$wit_sha256" "$component_path"
