# Task 8 Step 2 pure assembly adapter batch 2 report

## Scope

Migrated the eight specified non-Rust assembly/validation gates to the current-only `bin/do-toolchain` typed operations. Each script defines `toolchain_bin="$repo_root/bin/do-toolchain"` and exports `DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"`. Existing compiler, WIT/WAT, marker, negative, cleanup, exit-code, nested gate, and runner behavior was preserved.

## Verification

All commands were run from `/home/_/._/_/do` unless stated otherwise.

1. Syntax and static checks:

   `files=(examples/p3-runtime/test_do_async_resource_result.sh examples/p3-runtime/test_do_http_payload_error_boundary.sh examples/p3-runtime/test_do_record_stream_probe_lowering.sh examples/p3-runtime/test_do_cli_stream_stdout_lowering.sh examples/p3-runtime/test_do_http_request_empty_lowering.sh examples/p3-runtime/test_do_resource_probe_lowering.sh examples/p3-runtime/test_do_stream_reader_descriptor.sh examples/p3-runtime/test_do_stream_writer_descriptor.sh); for f in "${files[@]}"; do bash -n "$f" || exit; done; if rg -n 'wasm-tools' "${files[@]}"; then exit 1; fi; git diff --check`

   Result: `rc=0`; all eight scripts passed `bash -n`, no direct `wasm-tools` command remained, and `git diff --check` passed.

2. Root-cwd gates:

   `bash examples/p3-runtime/test_do_async_resource_result.sh` -> `rc=0`

   `bash examples/p3-runtime/test_do_http_payload_error_boundary.sh` -> `rc=0`

   `bash examples/p3-runtime/test_do_record_stream_probe_lowering.sh` -> `rc=0`

   `bash examples/p3-runtime/test_do_cli_stream_stdout_lowering.sh` -> `rc=0`

   `bash examples/p3-runtime/test_do_http_request_empty_lowering.sh` -> `rc=0`

   `bash examples/p3-runtime/test_do_resource_probe_lowering.sh` -> `rc=0`

   `bash examples/p3-runtime/test_do_stream_reader_descriptor.sh` -> `rc=0`

   `bash examples/p3-runtime/test_do_stream_writer_descriptor.sh` -> `rc=0`

   Result: all eight gates passed.

3. Unrelated-cwd gates:

   `run_cwd=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-adapter-batch2-cwd.XXXXXX"); for f in examples/p3-runtime/test_do_async_resource_result.sh examples/p3-runtime/test_do_http_payload_error_boundary.sh examples/p3-runtime/test_do_record_stream_probe_lowering.sh examples/p3-runtime/test_do_cli_stream_stdout_lowering.sh examples/p3-runtime/test_do_http_request_empty_lowering.sh examples/p3-runtime/test_do_resource_probe_lowering.sh examples/p3-runtime/test_do_stream_reader_descriptor.sh examples/p3-runtime/test_do_stream_writer_descriptor.sh; do (cd "$run_cwd" && bash "/home/_/._/_/do/$f") || exit; done; rmdir "$run_cwd"`

   Result: all eight gates passed with `rc=0` from temporary cwd `/tmp/do-p3-adapter-batch2-cwd.hmGUEw`.

4. Current-only guard and final diff check:

   `bash examples/p3-runtime/test_wasm_tools_current_only.sh; guard_rc=$?; git diff --check; diff_rc=$?; printf 'GUARD_RC=%s\\nDIFF_CHECK_RC=%s\\n' "$guard_rc" "$diff_rc"; exit $((guard_rc || diff_rc))`

   Result: current-only guard passed, `GUARD_RC=0`, `DIFF_CHECK_RC=0`.

## Concerns

No concerns or unverified findings. The adapter intentionally has no `--features` or `--skip-validation` arguments; those legacy CLI flags were removed while the explicit later `validate-component` gates remain.
