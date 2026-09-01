#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
zig_bin=${ZIG_BIN:-zig}
do_bin=${DO_BIN:-$repo_root/bin/do}
descriptor=demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-default-mixed-text-byte-list-lift-negative.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

run_rejection() {
  local input_do="$1"
  local label
  label=$(basename "$input_do" .do)
  local expect_file="${input_do%.do}.expect"
  local wat_file="$tmp_dir/$label.wat"
  local stderr_file="$tmp_dir/$label.stderr"
  local stdout_file="$tmp_dir/$label.stdout"
  local expected_error
  local status

  expected_error=$(awk '!/^#/ && NF { value=$0 } END { print value }' "$expect_file")
  if DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$input_do" \
      --gc-wit-marshal "$descriptor" -o "$wat_file" \
      >"$stdout_file" 2>"$stderr_file"; then
    printf '[FAIL] %s unexpectedly accepted\n' "$label" >&2
    return 1
  else
    status=$?
  fi
  if [ -e "$wat_file" ]; then
    printf '[FAIL] %s left a WAT artifact after rejection\n' "$label" >&2
    return 1
  fi
  if ! grep -Fq "error[$expected_error]" "$stderr_file"; then
    printf '[FAIL] %s missing diagnostic error[%s]\n' "$label" "$expected_error" >&2
    cat "$stderr_file" >&2
    return 1
  fi
  printf '[PASS] %s rejected before WAT emission with error[%s] (status=%s)\n' "$label" "$expected_error" "$status"
}

for input_do in \
    "$repo_root/src/build/test/compile_err/649_gc_wit_mixed_text_byte_list_lift_async.do" \
    "$repo_root/src/build/test/compile_err/650_gc_wit_mixed_text_byte_list_lift_locator.do" \
    "$repo_root/src/build/test/compile_err/651_gc_wit_mixed_text_byte_list_lift_member.do" \
    "$repo_root/src/build/test/compile_err/652_gc_wit_mixed_text_byte_list_lift_reordered.do" \
    "$repo_root/src/build/test/compile_err/653_gc_wit_mixed_text_byte_list_lift_u32_payload.do" \
    "$repo_root/src/build/test/compile_err/654_gc_wit_mixed_text_byte_list_lift_text_payload.do" \
    "$repo_root/src/build/test/compile_err/655_gc_wit_mixed_text_byte_list_lift_extra_field.do" \
    "$repo_root/src/build/test/compile_err/656_gc_wit_mixed_text_byte_list_lift_record_name.do"; do
  run_rejection "$input_do"
done

unadmitted_wat="$tmp_dir/unadmitted.wat"
DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$repo_root/src/build/test/compile_ok/03_env_host_import_i32.do" -o "$unadmitted_wat"
if ! rg -q '__arc_' "$unadmitted_wat"; then
  printf '[FAIL] unrelated unadmitted host fixture unexpectedly lost its ARC fallback\n' >&2
  exit 1
fi
printf '[PASS] unrelated unadmitted host fixture retains ARC fallback\n'
printf 'default mixed text/byte-list lift negative boundary gate passed\n'
