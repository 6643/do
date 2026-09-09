#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
zig_bin=${ZIG_BIN:-zig}
do_bin=${DO_BIN:-$repo_root/bin/do}
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-default-nested-deeper-negative.XXXXXX")
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

  if "$do_bin" build "$input_do" -o "$wat_file" >"$stdout_file" 2>"$stderr_file"; then
    status=0
  else
    status=$?
  fi
  if [ "$status" -eq 0 ]; then
    printf '[FAIL] %s unexpectedly accepted\n' "$label" >&2
    return 1
  fi
  if [ -e "$wat_file" ]; then
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

run_rejection \
  async-marker \
  "$repo_root/src/build/test/compile_err/588_gc_wit_nested_record_deeper_lift_host_boundary_async.do" \
  UnknownP3AsyncHostDescriptor
run_rejection \
  nested-shape-drift \
  "$repo_root/src/build/test/compile_err/589_gc_wit_nested_record_deeper_lift_host_boundary_shape.do" \
  GcWitHostRecordMismatch
run_rejection \
  member-mismatch \
  "$repo_root/src/build/test/compile_err/590_gc_wit_nested_record_deeper_lower_host_boundary_mismatch.do" \
  GcWitHostMemberMismatch

unadmitted_wat="$tmp_dir/unadmitted.wat"
unadmitted_stderr="$tmp_dir/unadmitted.stderr"
unadmitted_stdout="$tmp_dir/unadmitted.stdout"
unadmitted_status=0
if "$do_bin" build "$repo_root/src/build/test/compile_ok/03_env_host_import_i32.do" \
    -o "$unadmitted_wat" >"$unadmitted_stdout" 2>"$unadmitted_stderr"; then
  unadmitted_status=0
else
  unadmitted_status=$?
fi
if [ "$unadmitted_status" -eq 0 ]; then
  printf '[FAIL] unadmitted env host fixture unexpectedly accepted\n' >&2
  exit 1
fi
if [ -e "$unadmitted_wat" ]; then
  printf '[FAIL] unadmitted env host fixture left a WAT artifact after rejection\n' >&2
  exit 1
fi
if ! grep -Fq 'error[UnsupportedGcSyncModuleGraph]' "$unadmitted_stderr"; then
  printf '[FAIL] unadmitted env host fixture missing diagnostic error[UnsupportedGcSyncModuleGraph]\n' >&2
  cat "$unadmitted_stderr" >&2
  exit 1
fi
printf '[PASS] unadmitted host fixture rejected before WAT emission with error[UnsupportedGcSyncModuleGraph] (status=%s)\n' "$unadmitted_status"

printf 'default C14 four-level nested scalar record negative gates passed\n'
