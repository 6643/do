#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
zig_bin=${ZIG_BIN:-zig}
do_bin=${DO_BIN:-$repo_root/bin/do}
descriptor='demo:marshal-record-mixed-text-u32-list-lower/api.write@1.0.0/lower'
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-g5c-mixed-text-u32-list-lower-negative.XXXXXX")
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
unadmitted_stderr="$tmp_dir/unadmitted.stderr"
unadmitted_stdout="$tmp_dir/unadmitted.stdout"
unadmitted_status=0
if DO_LIB_ROOT="$repo_root/lib" "$do_bin" build \
    "$repo_root/src/build/test/compile_ok/03_env_host_import_i32.do" \
    -o "$unadmitted_wat" >"$unadmitted_stdout" 2>"$unadmitted_stderr"; then
    unadmitted_status=0
else
    unadmitted_status=$?
fi
if [ "$unadmitted_status" -eq 0 ]; then
    printf '[FAIL] unrelated unadmitted host fixture unexpectedly accepted\n' >&2
    exit 1
fi
if [ -e "$unadmitted_wat" ]; then
    printf '[FAIL] unrelated unadmitted host fixture left a WAT artifact after rejection\n' >&2
    exit 1
fi
if ! grep -Fq 'error[UnsupportedGcSyncModuleGraph]' "$unadmitted_stderr"; then
    printf '[FAIL] unrelated unadmitted host fixture missing diagnostic error[UnsupportedGcSyncModuleGraph]\n' >&2
    cat "$unadmitted_stderr" >&2
    exit 1
fi
printf '[PASS] unrelated unadmitted host fixture rejected before WAT emission with error[UnsupportedGcSyncModuleGraph] (status=%s)\n' "$unadmitted_status"
printf 'mixed text/u32-list lower negative boundary gate passed\n'
