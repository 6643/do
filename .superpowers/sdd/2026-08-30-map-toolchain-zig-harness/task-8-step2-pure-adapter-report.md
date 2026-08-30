# Task 8 Step 2 pure assembly adapter report

## Scope

Migrated the five specified pure assembly/validation gates to the typed
`bin/do-toolchain` operations and exported the repository toolchain lock path.
All existing compiler output assertions, assembly checks, cleanup traps, exit
status behavior, and the variant gate's skip-validation behavior were kept.

## Verification

All commands were run from repository root `/home/_/._/_/do` unless noted.

1. Syntax check:

   `bash -n examples/p3-runtime/test_do_http_request_body_lowering.sh examples/p3-runtime/test_do_http_request_body_await_completion_lowering.sh examples/p3-runtime/test_do_http_request_body_producer_lowering.sh examples/p3-runtime/test_do_http_response_consume_body_assembly.sh examples/p3-runtime/test_do_variant_resource_stream_lowering.sh`

   Result: passed, exit code 0.

2. Repository-root gates:

   `bash examples/p3-runtime/test_do_http_request_body_lowering.sh`

   Result: passed, exit code 0.

   `bash examples/p3-runtime/test_do_http_request_body_await_completion_lowering.sh`

   Result: passed, exit code 0.

   `bash examples/p3-runtime/test_do_http_request_body_producer_lowering.sh`

   Result: passed, exit code 0.

   `bash examples/p3-runtime/test_do_http_response_consume_body_assembly.sh`

   Result: passed, exit code 0.

   `bash examples/p3-runtime/test_do_variant_resource_stream_lowering.sh`

   Result: passed, exit code 0.

3. Unrelated temporary cwd (`/tmp/do-pure-adapter-cwd.hQc4Hh`):

   Each of the same five `bash /home/_/._/_/do/examples/p3-runtime/<gate>.sh`
   commands was run after changing into that temporary directory.

   Result: all five passed, each exit code 0.

4. Current-only toolchain guard:

   `bash examples/p3-runtime/test_wasm_tools_current_only.sh`

   Result: `wasm-tools current-only guard passed through do-toolchain adapter`,
   exit code 0.

5. Diff whitespace check:

   `git diff --check`

   Result: passed, exit code 0.

## Concerns

No concerns observed in the required verification scope. The adapter's fixed
operation semantics preserve the former feature flags and
`--skip-validation` behavior.
