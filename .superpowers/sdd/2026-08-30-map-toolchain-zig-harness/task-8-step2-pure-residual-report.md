# Task 8 Step 2 residual pure assembly batch report

## Files changed

- `src/build/test/test_harness.zig`
  - Added six table-driven pure assembly cases.
  - Added explicit package-output handling for the HTTP cases. The harness
    keeps the compiler output as a package directory, checks the generated
    `worlds.wit`, `types.wit`, `deps.toml`, and `deps.lock`, appends the exact
    gate world declaration, and passes the directory to the adapter.
  - Added fail-closed ordinary-build validation for the request-body await
    fixture, producer ordering validation, nested WIT SHA-256/WAT parity, and
    canonical nested-producer adapter validation.
  - All parse/embed/new/validate operations remain current-only
    `do-toolchain` operations. No runtime Cargo behavior was added.
- `.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step2-pure-residual-report.md`
  - This report.

No unrelated pre-existing dirty files were modified.

## Exact cases added

1. `examples/p3-runtime/http-request-body.do` — package-output HTTP request
   body lowering, including stdin stream, request constructor/send imports,
   body acquisition/construction/completion-drop markers, and the forbidden
   synchronous `request.new` lowering marker.
2. `examples/p3-runtime/http-request-body-await-completion.do` — package-output
   request-body completion-await lowering, staged request/completion frame
   markers, and ordinary-build `AsyncLoweringUnavailable` rejection.
3. `examples/p3-runtime/http-request-body-producer-send-first.do` —
   package-output producer lowering, stdout/request/send markers, and request
   construction before producer stream close.
4. `examples/p3-runtime/http-response-consume-body.do` — package-output HTTP
   response consume-body assembly and `call $consume-body` marker.
5. `examples/p3-runtime/variant-resource-stream.do` — canonical WIT, event
   tag/payload layout, and ticket-drop markers.
6. `examples/p3-runtime/g6-2-owned-record-nested-producer.do` — pinned WIT
   SHA-256, generated-to-canonical WAT parity, nested ownership/layout markers,
   no ARC or Wasm-GC reference boundary, generated assembly, and a second
   adapter validation of the canonical WAT/WIT pair.

## Commands and results

- Red evidence before the final assertion update:
  - `if rg -n '\[producer-input-mode\]' src/build/test/test_harness.zig; then exit 0; else printf 'RED: harness lacks required canonical marker [producer-input-mode]\n' >&2; exit 1; fi`
  - FAIL (expected red): exit `1`, reporting the missing nested-producer
    canonical marker.
- `cd src && zig test build/test/test_harness.zig`
  - PASS: 4/4 tests.
- `cd src && zig build test --summary all`
  - PARTIAL: integration output included `P3 pure lowering matrix` and
    `rust async runner`, but the long-running command did not reach a final
    exit within the verification window; no completion claim is made for the
    full integration suite here.
- Relevant shell gates:
  - PASS: `test_do_http_request_body_lowering.sh`.
  - PASS: `test_do_http_request_body_await_completion_lowering.sh`.
  - PASS: `test_do_http_request_body_producer_lowering.sh`.
  - PASS: `test_do_http_response_consume_body_assembly.sh`.
  - PASS: `test_do_variant_resource_stream_lowering.sh`.
  - PASS: `test_do_g6_2_owned_record_nested_producer.sh`.
  - PASS: `test_g6_2_owned_record_nested_canonical.sh`.
- `git diff --check`
  - PASS.

## Residual concerns

The existing pure shell matrix still contains additional assembly-only gates
outside this bounded batch, including nested producer ABI/equivalence and
other G6.2 producer variants. This change does not claim that all pure shell
scripts have been migrated. The full `zig build test --summary all` integration
run remains a separate long-running gate and is not claimed from the focused
verification below.
