#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
zig_bin=${ZIG_BIN:-zig}
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
do_bin=$repo_root/bin/do
descriptor=demo:marshal-record-managed-lift-multi/api.read@1.0.0/lift
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-record-managed-lift-multi-negative.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler executable: %s\n' "$do_bin" >&2
  exit 1
fi
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

  if "$do_bin" build "$input_do" \
      --gc-wit-marshal "$descriptor" \
      -o "$wat_file" >"$stdout_file" 2>"$stderr_file"; then
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
  "$repo_root/src/build/test/compile_err/582_gc_wit_managed_record_lift_multi_host_boundary_async.do" \
  UnknownP3AsyncHostDescriptor
run_rejection \
  locator-mismatch \
  "$repo_root/src/build/test/compile_err/583_gc_wit_managed_record_lift_multi_host_boundary_mismatch.do" \
  GcWitHostLocatorMismatch
run_rejection \
  member-mismatch \
  "$repo_root/src/build/test/compile_err/585_gc_wit_managed_lift_multi_host_boundary_member_mismatch.do" \
  GcWitHostMemberMismatch

default_wat="$tmp_dir/default.wat"
"$do_bin" build \
  "$repo_root/examples/gc-p3-runtime/ordinary-host-c16d-call.do" \
  -o "$default_wat"
if ! rg -q ';; gc-sync ' "$default_wat"; then
  printf '[FAIL] default C16-D fixture lost its GC route marker\n' >&2
  exit 1
fi
if rg -q '__arc_' "$default_wat"; then
  printf '[FAIL] default C16-D fixture still contains ARC runtime symbols\n' >&2
  exit 1
fi
if ! rg -q '\(import "demo:marshal-record-managed-lift-multi/api@1.0.0" "read"' "$default_wat"; then
  printf '[FAIL] default C16-D fixture is missing its canonical host import\n' >&2
  exit 1
fi
printf '[PASS] default C16-D fixture uses the manifest-backed GC route\n'

run_existing_gate() {
  local label=$1
  shift
  local script=$1
  shift
  local output="$tmp_dir/$label.output"
  if ! bash "$repo_root/examples/gc-p3-runtime/$script" "$@" >"$output" 2>&1; then
    cat "$output" >&2
    printf '[FAIL] %s\n' "$label" >&2
    return 1
  fi
  tail -n 1 "$output"
  printf '[PASS] %s\n' "$label"
}

run_existing_gate c16d-compiler-host test_gc_marshal_record_managed_lift_multi_compiler_host.sh
run_existing_gate c16d-compiler-equivalence test_gc_marshal_record_managed_lift_multi_compiler_equivalence.sh
run_existing_gate c16d-default-host test_gc_default_host_route_multi.sh
run_existing_gate c16d-default-equivalence test_gc_default_host_route_multi_equivalence.sh

printf 'C16-D negative/default compiler boundary gates passed\n'
