#!/usr/bin/env bash
set -euo pipefail
# Verification Status: verified

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
zig_bin=${ZIG_BIN:-zig}
do_bin=$repo_root/bin/do
descriptor=demo:marshal-record-managed-lower/api.write@1.0.0/lower
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-record-managed-lower-negative.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler executable: %s\n' "$do_bin" >&2
  exit 1
fi
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
  "$repo_root/src/build/test/compile_err/577_gc_wit_managed_record_host_boundary_async.do" \
  UnknownP3AsyncHostDescriptor
run_rejection \
  locator-mismatch \
  "$repo_root/src/build/test/compile_err/578_gc_wit_managed_record_host_boundary_mismatch.do" \
  GcWitHostLocatorMismatch

default_wat="$tmp_dir/default.wat"
"$do_bin" build \
  "$repo_root/src/build/test/compile_ok/565_gc_wit_managed_record_host_boundary.do" \
  -o "$default_wat"
if ! rg -q ';; gc-sync ' "$default_wat"; then
  printf '[FAIL] default C15-B fixture lost its GC route marker\n' >&2
  exit 1
fi
if rg -q '__arc_' "$default_wat"; then
  printf '[FAIL] default C15-B fixture still contains ARC runtime symbols\n' >&2
  exit 1
fi
if ! rg -q '\(import "demo:marshal-record-managed-lower/api@1.0.0" "write"' "$default_wat"; then
  printf '[FAIL] default C15-B fixture is missing its canonical host import\n' >&2
  exit 1
fi
printf '[PASS] default C15-B fixture uses the manifest-backed GC route\n'

printf 'C16-B C15-B negative/default compiler boundary gates passed\n'
