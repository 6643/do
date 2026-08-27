#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
zig_bin=${ZIG_BIN:-zig}
do_bin=${DO_BIN:-$repo_root/bin/do}
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-g5c-default-mixed-lower-negative.XXXXXX")
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
  "$repo_root/src/build/test/compile_err/592_gc_wit_mixed_record_lower_host_boundary_async.do" \
  UnknownP3AsyncHostDescriptor
run_rejection \
  shape-drift \
  "$repo_root/src/build/test/compile_err/593_gc_wit_mixed_record_lower_host_boundary_shape.do" \
  GcWitHostRecordMismatch
run_rejection \
  member-drift \
  "$repo_root/src/build/test/compile_err/594_gc_wit_mixed_record_lower_host_boundary_member.do" \
  GcWitHostMemberMismatch

unadmitted_wat="$tmp_dir/unadmitted.wat"
"$do_bin" build "$repo_root/src/build/test/compile_ok/03_env_host_import_i32.do" -o "$unadmitted_wat"
if ! rg -q '__arc_' "$unadmitted_wat"; then
  printf '[FAIL] unadmitted env host fixture unexpectedly lost its ARC route\n' >&2
  exit 1
fi
printf '[PASS] unadmitted host fixture retains its existing ARC route\n'

printf 'default mixed scalar record lower negative gates passed\n'
