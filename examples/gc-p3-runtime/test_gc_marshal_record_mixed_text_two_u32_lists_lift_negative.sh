#!/usr/bin/env bash
set -euo pipefail
# Verification Status: verified

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
zig_bin=${ZIG_BIN:-zig}
do_bin=${DO_BIN:-$repo_root/bin/do}
descriptor=demo:marshal-record-mixed-text-two-u32-lists-lift/api.read@1.0.0/lift
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-record-mixed-text-two-u32-lists-lift-negative.XXXXXX")
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
  printf '[PASS] %s rejected before WAT emission with error[%s] (status=%s)\n' \
    "$label" "$expected_error" "$status"
}

for input_do in \
    "$repo_root/src/build/test/compile_err/674_gc_wit_mixed_text_two_u32_lists_lift_async.do" \
    "$repo_root/src/build/test/compile_err/675_gc_wit_mixed_text_two_u32_lists_lift_locator.do" \
    "$repo_root/src/build/test/compile_err/676_gc_wit_mixed_text_two_u32_lists_lift_member.do" \
    "$repo_root/src/build/test/compile_err/677_gc_wit_mixed_text_two_u32_lists_lift_reordered.do" \
    "$repo_root/src/build/test/compile_err/678_gc_wit_mixed_text_two_u32_lists_lift_u8_field.do" \
    "$repo_root/src/build/test/compile_err/679_gc_wit_mixed_text_two_u32_lists_lift_text_field.do" \
    "$repo_root/src/build/test/compile_err/680_gc_wit_mixed_text_two_u32_lists_lift_extra_field.do" \
    "$repo_root/src/build/test/compile_err/681_gc_wit_mixed_text_two_u32_lists_lift_record_name.do"; do
  run_rejection "$input_do"
done

printf 'manifest-backed mixed text/two-u32-lists record lift negative boundary gate passed\n'
