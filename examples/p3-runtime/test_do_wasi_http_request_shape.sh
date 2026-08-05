#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
check_source="$repo_root/src/build/test/check/374_http_client_resource_shape.do"
async_check_source="$repo_root/src/build/test/check/375_http_async_host_func.do"
async_build_source="$repo_root/src/build/test/compile_err/375_http_async_send_lowering_unavailable.do"
service_source="$repo_root/examples/p3-runtime/http-service.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-http-request-shape.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

"$do_bin" check "$check_source"
"$do_bin" check "$async_check_source"

if "$do_bin" build "$async_build_source" -o "$tmp_dir/rejected.wat" >"$tmp_dir/rejected.out" 2>&1; then
    printf 'ordinary async HTTP build unexpectedly succeeded\n' >&2
    exit 1
fi
grep -Fq 'AsyncLoweringUnavailable' "$tmp_dir/rejected.out"

"$do_bin" build --p3-async-component --p3-wit-output "$tmp_dir/service.wit" \
    "$service_source" -o "$tmp_dir/service.wat"
grep -Fq '[async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle' "$tmp_dir/service.wat"
grep -Fq '[async-lower]send' "$tmp_dir/service.wat"

printf 'WASI HTTP request resource shape boundary passed\n'
