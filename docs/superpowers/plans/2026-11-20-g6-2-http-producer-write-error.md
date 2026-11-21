# G6.2 HTTP Producer Write Error Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a private HTTP body producer failure probe that returns the original `StreamClosed` after its host body consumer closes, while cancelling the pending send and cleaning up resources exactly once.

**Architecture:** Keep the successful source probe and public HTTP API unchanged. Add a distinct exact source shape and compiler route for the failure probe, then exercise that route through the pinned Component ABI and a Rust/Wasmtime host that closes the consumer after accepting byte 65. Preserve the writer's `StreamClosed` result in the exported probe error union and cancel the still-pending send before returning.

**Tech Stack:** Do fixtures, Zig compiler source and unit tests, WAT/WIT generation, shell gates, Rust/Wasmtime runtime runner.

**Spec:** `docs/superpowers/specs/2026-11-20-g6-2-http-producer-write-error-design.md`

## Global Constraints

- Keep the existing successful body producer probe and accepted source shape unchanged.
- Keep the new body source finite and fixed; add no loop, arbitrary producer expression, dynamic buffer, public ownership syntax, or public HTTP API change.
- Map Wasmtime stream `Dropped` to `StreamClosed` and `Cancelled` coarsely to `StreamWriteFailed`; do not claim WIT error-payload preservation.
- Keep the HTTP send pending until guest cancellation in the failure mode.
- Assert one accepted byte, no response, one send cancellation, exactly-once cleanup of each live Future/stream/request endpoint, and an empty `ResourceTable`.
- Preserve the existing success gate's `[65,66]` payload assertion.

## Review Focus

- Consumer closure after byte 65 must make the second writer await return `StreamClosed`, without accidentally mapping it to `HttpError` or `StreamWriteFailed`.
- The failure path must cancel send while pending; otherwise send completion can race cancellation and invalidate the cleanup assertion.
- Failure cleanup must not duplicate or omit writer, stream, request, trailers Future, transmission Future, or response cleanup.
- The existing success source and success runtime gate must retain their current behavior.
- Unrecognized source variants must remain rejected before WAT emission.

---

### Task 1: Add the bounded failure probe and runtime gate

**Files:**
- Create: `examples/p3-runtime/http-request-body-producer-write-error.do`
- Create: `examples/p3-runtime/test_do_http_request_body_producer_write_error_lowering.sh`
- Create: `examples/p3-runtime/test_rust_http_request_body_producer_write_error.sh`
- Modify: `src/build/codegen_component_wasi_http.zig`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/test/test_harness.zig`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/http_request_body_producer_write_error.rs`
- Modify: `examples/p3-runtime/test_rust_http_request_body_producer.sh`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `examples/p3-runtime/README.md`

**Interfaces:**
- Consumes: the existing request-body producer matcher, WAT emitter, pinned `request.new` and `client.send` ABI, and `StreamError` union lowering.
- Produces: a private `http-request-body-producer-write-error-probe` route whose `run` export reports `result<_, producer-error>`; `producer-error` distinguishes the existing HTTP error case and both Do `StreamError` cases.

- [x] **Step 1: Add compiler and lowering regression assertions** for the dedicated fixture. Assert it selects the failure route, exports the failure result shape, starts send before writing, branches on the second writer result, and emits send cancellation plus exactly one writer close. Also add negative matcher cases proving unrelated payloads and unlowered statements are not admitted.
- [x] **Step 2: Run focused compiler tests and confirm RED.** Run the relevant `codegen_component_wasi_http.zig` tests and `test_do_http_request_body_producer_write_error_lowering.sh`; the new fixture must fail because no failure route exists yet.
- [x] **Step 3: Implement the exact failure matcher and WAT/WIT route.** Keep it separate from the current success route. Map each registered writer control status to its bounded Do error case after cancelling pending send and closing the writer once.
- [x] **Step 4: Run focused compiler and lowering tests and confirm GREEN.** Parse the generated core module, embed it using the pinned package, assemble the Component, and validate it.
- [x] **Step 5: Add the Rust/Wasmtime host failure scenario.** Accept byte 65, drop the body consumer, keep send pending until cancellation, then assert exported `StreamClosed`, no response, one cancellation, exactly-once cleanup for all live resources/Futures, and an empty `ResourceTable`.
- [x] **Step 6: Run the failure runtime gate and the existing success runtime gate.** Both scripts pass; success still reports complete `[65,66]` bodies.
- [x] **Step 7: Update the registered package gate and docs.** Record the new source fixture in `test_harness.zig`, run the repository test harness, and update the HTTP lowering and blocker ledgers with the exact bounded contract and remaining non-goals.
- [x] **Step 8: Run final verification.** Run `bash examples/p3-runtime/test_do_http_request_body_producer_write_error_lowering.sh`, `bash examples/p3-runtime/test_rust_http_request_body_producer_write_error.sh`, `bash examples/p3-runtime/test_rust_http_request_body_producer.sh`, and `./src/build/test/run_tests.sh`.
