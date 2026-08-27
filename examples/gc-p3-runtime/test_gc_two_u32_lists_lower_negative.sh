#!/usr/bin/env bash
# Verification Status: pending
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
zig_bin=${ZIG_BIN:-zig}
do_bin=${DO_BIN:-$repo_root/bin/do}
descriptor=demo:marshal-record-two-u32-lists-lower/api.write@1.0.0/lower
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-two-u32-lists-lower-negative.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

tool_version=$($wasm_tools_bin --version)
case "$tool_version" in
  "wasm-tools 1.255.0 (76e20611d"*) ;;
  *) printf 'unexpected wasm-tools version: %s\n' "$tool_version" >&2; exit 1 ;;
esac

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

run_rejection() {
  local label=$1
  local input_do=$2
  local expected=$3
  local wat_file="$tmp_dir/$label.wat"
  local stderr_file="$tmp_dir/$label.stderr"
  local stdout_file="$tmp_dir/$label.stdout"
  local status=0

  if "$do_bin" build "$input_do" --gc-wit-marshal "$descriptor" -o "$wat_file" >"$stdout_file" 2>"$stderr_file"; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -eq 0 ]]; then
    printf '[FAIL] %s unexpectedly accepted\n' "$label" >&2
    return 1
  fi
  if [[ -e "$wat_file" ]]; then
    printf '[FAIL] %s left a WAT artifact after rejection\n' "$label" >&2
    return 1
  fi
  if ! grep -Fq "error[$expected]" "$stderr_file"; then
    printf '[FAIL] %s missing diagnostic error[%s]\n' "$label" "$expected" >&2
    cat "$stderr_file" >&2
    return 1
  fi
  printf '[PASS] %s rejected before WAT emission with error[%s]\n' "$label" "$expected"
}

run_rejection async \
  "$repo_root/src/build/test/compile_err/658_gc_wit_two_u32_lists_lower_host_boundary_async.do" \
  UnknownP3AsyncHostDescriptor
run_rejection locator \
  "$repo_root/src/build/test/compile_err/659_gc_wit_two_u32_lists_lower_host_boundary_locator.do" \
  GcWitHostLocatorMismatch
run_rejection member \
  "$repo_root/src/build/test/compile_err/660_gc_wit_two_u32_lists_lower_host_boundary_member.do" \
  GcWitHostMemberMismatch
run_rejection reordered \
  "$repo_root/src/build/test/compile_err/661_gc_wit_two_u32_lists_lower_host_boundary_reordered.do" \
  GcWitHostRecordMismatch
run_rejection first-byte-list \
  "$repo_root/src/build/test/compile_err/662_gc_wit_two_u32_lists_lower_host_boundary_first_byte_list.do" \
  GcWitHostRecordMismatch
run_rejection second-byte-list \
  "$repo_root/src/build/test/compile_err/663_gc_wit_two_u32_lists_lower_host_boundary_second_byte_list.do" \
  GcWitHostRecordMismatch
run_rejection extra-field \
  "$repo_root/src/build/test/compile_err/664_gc_wit_two_u32_lists_lower_host_boundary_extra_field.do" \
  GcWitHostRecordMismatch

printf 'two-u32-list lower negative boundary gate passed: 7 fail-closed cases\n'
