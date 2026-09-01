#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
zig_bin=${ZIG_BIN:-zig}
do_bin=${DO_BIN:-$repo_root/bin/do}
descriptor=demo:marshal-record-mixed-scalar-list-lower/api.write@1.0.0/lower
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-g5c-default-mixed-scalar-list-lower-negative.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

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
  "$repo_root/src/build/test/compile_err/623_gc_wit_mixed_scalar_list_lower_host_boundary_async.do" \
  UnknownP3AsyncHostDescriptor
run_rejection locator \
  "$repo_root/src/build/test/compile_err/624_gc_wit_mixed_scalar_list_lower_host_boundary_locator.do" \
  GcWitHostLocatorMismatch
run_rejection member \
  "$repo_root/src/build/test/compile_err/625_gc_wit_mixed_scalar_list_lower_host_boundary_member.do" \
  GcWitHostMemberMismatch
run_rejection reordered \
  "$repo_root/src/build/test/compile_err/626_gc_wit_mixed_scalar_list_lower_host_boundary_reordered.do" \
  GcWitHostRecordMismatch
run_rejection u32-payload \
  "$repo_root/src/build/test/compile_err/627_gc_wit_mixed_scalar_list_lower_host_boundary_u32_payload.do" \
  GcWitHostRecordMismatch
run_rejection text-payload \
  "$repo_root/src/build/test/compile_err/628_gc_wit_mixed_scalar_list_lower_host_boundary_text_payload.do" \
  GcWitHostRecordMismatch
run_rejection extra-field \
  "$repo_root/src/build/test/compile_err/629_gc_wit_mixed_scalar_list_lower_host_boundary_extra_field.do" \
  GcWitHostRecordMismatch

printf 'mixed scalar-list lower negative boundary gate passed: 7 fail-closed cases\n'
