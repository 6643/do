#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
zig_bin=${ZIG_BIN:-zig}
do_bin=${DO_BIN:-$repo_root/bin/do}
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-nested-deeper-compiler-negative.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler executable: %s\n' "$do_bin" >&2
  exit 1
fi

assert_function_without_gc_struct_ops() {
  local wat_file="$1"
  local function_name="$2"
  if ! awk -v wanted="$function_name" '
      BEGIN {
        in_func = 0
        found = 0
        depth = 0
        bad = 0
      }
      {
        if (!in_func) {
          prefix = "(func $" wanted
          start = index($0, prefix)
          if (start == 0) next
          suffix = substr($0, start + length(prefix), 1)
          if (suffix != "" && suffix != " " && suffix != "\t" && suffix != "(") next
          in_func = 1
          found = 1
        }
        if (in_func) {
          line = $0
          opens = gsub(/\(/, "", line)
          closes = gsub(/\)/, "", line)
          depth += opens - closes
          if ($0 ~ /struct\.(new|get)/) bad = 1
          if (depth == 0) in_func = 0
        }
      }
      END {
        exit (!found || bad)
      }
    ' "$wat_file"; then
    printf 'function contains an unexpected GC struct operation: %s (%s)\n' "$wat_file" "$function_name" >&2
    return 1
  fi
}
(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

run_rejection() {
  local label=$1
  local input_do=$2
  local descriptor=$3
  local expected=$4
  local wat_file="$tmp_dir/$label.wat"
  local stderr_file="$tmp_dir/$label.stderr"
  local stdout_file="$tmp_dir/$label.stdout"
  local status=0

  if "$do_bin" build "$input_do" --gc-wit-marshal "$descriptor" -o "$wat_file" >"$stdout_file" 2>"$stderr_file"; then
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
  demo:marshal-record-nested-lift-deeper/api.read@1.0.0/lift \
  UnknownP3AsyncHostDescriptor
run_rejection \
  nested-shape-drift \
  "$repo_root/src/build/test/compile_err/589_gc_wit_nested_record_deeper_lift_host_boundary_shape.do" \
  demo:marshal-record-nested-lift-deeper/api.read@1.0.0/lift \
  GcWitHostRecordMismatch
run_rejection \
  member-mismatch \
  "$repo_root/src/build/test/compile_err/590_gc_wit_nested_record_deeper_lower_host_boundary_mismatch.do" \
  demo:marshal-record-nested-lower-deeper/api.write@1.0.0/lower \
  GcWitHostMemberMismatch

default_wat="$tmp_dir/default.wat"
"$do_bin" build "$repo_root/src/build/test/compile_ok/586_gc_wit_nested_record_deeper_lift_host_boundary.do" -o "$default_wat"
if ! rg -q '^  ;; gc-sync ' "$default_wat"; then
  printf '[FAIL] default C14 fixture did not use the GC synchronous route\n' >&2
  exit 1
fi
if rg -q '__arc_' "$default_wat"; then
  printf '[FAIL] default C14 fixture still contains ARC runtime symbols\n' >&2
  exit 1
fi
if ! rg -q '^  \(func \$read \(result i32 i64 i64 i64 i64\)' "$default_wat"; then
  printf '[FAIL] default C14 fixture lacks the inline scalar lift bridge\n' >&2
  exit 1
fi
if ! assert_function_without_gc_struct_ops "$default_wat" read; then
  printf '[FAIL] default C14 fixture crossed a GC struct operation\n' >&2
  exit 1
fi
printf '[PASS] default C14 fixture uses the inline scalar GC route\n'

printf 'C14 four-level nested scalar record compiler boundary negative gates passed\n'
