#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-$repo_root/bin/do}
descriptor=demo:marshal-record-u32-list-lower/api.write@1.0.0/lower
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-record-u32-list-lower-negative.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

cases=(
  "602_gc_wit_record_u32_list_lower_host_boundary_async:UnknownP3AsyncHostDescriptor"
  "603_gc_wit_record_u32_list_lower_host_boundary_locator:GcWitHostLocatorMismatch"
  "604_gc_wit_record_u32_list_lower_host_boundary_member:GcWitHostMemberMismatch"
  "605_gc_wit_record_u32_list_lower_host_boundary_reordered:GcWitHostRecordMismatch"
  "606_gc_wit_record_u32_list_lower_host_boundary_u8:GcWitHostRecordMismatch"
  "607_gc_wit_record_u32_list_lower_host_boundary_extra_field:GcWitHostRecordMismatch"
)

for case in "${cases[@]}"; do
  name=${case%%:*}
  expected=${case#*:}
  wat_file="$tmp_dir/$name.wat"
  stderr_file="$tmp_dir/$name.stderr"
  status=0
  if DO_LIB_ROOT="$repo_root/lib" "$do_bin" build \
      "$repo_root/src/build/test/compile_err/$name.do" \
      --gc-wit-marshal "$descriptor" -o "$wat_file" \
      >"$tmp_dir/$name.stdout" 2>"$stderr_file"; then
    status=0
  else
    status=$?
  fi
  if [ "$status" -eq 0 ]; then
    printf '[FAIL] %s unexpectedly accepted\n' "$name" >&2
    exit 1
  fi
  if [ -e "$wat_file" ]; then
    printf '[FAIL] %s left a WAT artifact after rejection\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "error[$expected]" "$stderr_file"; then
    printf '[FAIL] %s missing diagnostic error[%s]\n' "$name" "$expected" >&2
    cat "$stderr_file" >&2
    exit 1
  fi
  printf '[PASS] %s rejected before WAT emission with error[%s]\n' "$name" "$expected"
done

printf 'u32-list record lower negative compiler gates passed\n'
