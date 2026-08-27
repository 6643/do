#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
zig_bin=${ZIG_BIN:-zig}
do_bin=${DO_BIN:-$repo_root/bin/do}
descriptor='demo:marshal-record-mixed-text-u32-list-lower/api.write@1.0.0/lower'
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-g5c-mixed-text-u32-list-lower-negative.XXXXXX")
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
    if "$do_bin" build "$input_do" --gc-wit-marshal "$descriptor" -o "$wat_file" >"$stdout_file" 2>"$stderr_file"; then
        printf '[FAIL] %s unexpectedly accepted\n' "$label" >&2
        return 1
    else
        status=$?
    fi
    if [[ -e "$wat_file" ]]; then
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
    "$repo_root/src/build/test/compile_err/631_gc_wit_mixed_text_u32_list_lower_async.do" \
    "$repo_root/src/build/test/compile_err/632_gc_wit_mixed_text_u32_list_lower_locator.do" \
    "$repo_root/src/build/test/compile_err/633_gc_wit_mixed_text_u32_list_lower_member.do" \
    "$repo_root/src/build/test/compile_err/634_gc_wit_mixed_text_u32_list_lower_reordered.do" \
    "$repo_root/src/build/test/compile_err/635_gc_wit_mixed_text_u32_list_lower_u8_payload.do" \
    "$repo_root/src/build/test/compile_err/636_gc_wit_mixed_text_u32_list_lower_text_payload.do" \
    "$repo_root/src/build/test/compile_err/637_gc_wit_mixed_text_u32_list_lower_extra_field.do" \
    "$repo_root/src/build/test/compile_err/638_gc_wit_mixed_text_u32_list_lower_record_name.do"; do
    run_rejection "$input_do"
done

unadmitted_wat="$tmp_dir/unadmitted.wat"
DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$repo_root/src/build/test/compile_ok/03_env_host_import_i32.do" -o "$unadmitted_wat"
if ! rg -q '__arc_' "$unadmitted_wat"; then
    printf '[FAIL] unrelated unadmitted host fixture unexpectedly lost its ARC fallback\n' >&2
    exit 1
fi
printf '[PASS] unrelated unadmitted host fixture retains ARC fallback\n'
printf 'mixed text/u32-list lower negative boundary gate passed\n'
