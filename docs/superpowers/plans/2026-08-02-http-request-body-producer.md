# HTTP Request Body Producer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (recommended) or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one executable, bounded guest-produced HTTP request body path that creates a `Stream<u8>`, transfers the readable endpoint to the pinned `request.new`/`client.send` path, writes a fixed sequence through a capacity-one writer while the host consumer is attached, and closes the writer.

**Architecture:** Reuse the existing descriptor-pinned stream ABI and writer queue semantics. Component streams are rendezvous-based rather than an implicit guest buffer, so the admitted source constructs the request and starts `client.send` before writing. This attaches the host body consumer before the first write and makes capacity-one backpressure executable. The plan accepts one linear `new_stream<u8>(1)` binding, one `request.new`, one `client.send`, at most three literal `u8` writes with one await per write, one writer close, and one terminal send await. The compiler stores the reader, writer, pending write state, request, and transmission subtask in the async frame; a host-provided source stream is not used for this shape.

**Tech Stack:** Zig compiler, Core Wasm WAT, pinned `wasi:http@0.3.0-rc-2025-09-16`, pinned `wasi:cli/stdout@0.3.0-rc-2025-09-16` stream ABI, `wasm-tools 1.254.0`, Rust/Wasmtime 47.0.2.

## Global Constraints

- Do source does not expose `own<T>`, `borrow<T>`, `ref<T>`, pointers, or references.
- The admitted source is a finite linear producer: capacity `1`, literal `u8` writes only, no loop/branch, and exactly one `close(writer)`.
- The readable endpoint is transferred to `request.new` exactly once; `client.send` starts before the first write so the host consumer is attached, and the writer endpoint is closed exactly once after the final write.
- Pending writer completion is resumed through the existing Component waitable/task callback ABI; no guest scheduler or operation-ID protocol is added.
- The request body producer is a bounded probe, not generic producer syntax, arbitrary stream element types, dynamic EOF handling, or public WIT ownership semantics.
- Ordinary `do build` continues to reject async lowering; only `--p3-async-component` admits this probe.

---

### Task 1: Freeze The Combined Stream/HTTP ABI

**Files:**
- Create: `examples/p3-runtime/wit/http-request-body-producer-probe.wit`
- Create: `examples/p3-runtime/test_do_http_request_body_producer_abi.sh`
- Test: `src/build/p3_async_manifest.zig`

- [x] Add a WIT world containing `types.request.new` with `option<stream<u8>>` and a parameterless async `probe.run`.
- [x] Assemble a hand-written Core WAT that imports the root stream constructor, stream write, writable drop, readable drop, HTTP request constructor, request resource drop, and `client.send` async imports.
- [x] Validate the component with `wasm-tools 1.254.0` and assert that replacing a root stream import with an unregistered name fails component linking.
- [x] Record the exact root stream import names derived from the registered stdout writer descriptor; do not derive names from source-local aliases.

### Task 2: Add The Bounded Producer Source Contract

**Files:**
- Create: `examples/p3-runtime/http-request-body-producer.do`
- Modify: `src/build/codegen_component_wasi_http.zig`
- Modify: `src/build/codegen_component_async.zig`
- Test: `src/build/codegen_component_wasi_http.zig`

- [x] Accept only `StreamReader<u8>, StreamWriter<u8> = new_stream<u8>(1)`, request construction with the reader, one send, up to three literal `u8` writer calls whose futures are awaited, `close(writer)`, and one terminal send await.
- [x] Reject the old write-before-request order because it deadlocks on the Component stream rendezvous semantics.
- [x] Reject capacity other than `1`, non-literal values, a second stream, loops/branches, a write after close, a request before close, or a second request/send.
- [x] Add a dedicated HTTP producer plan instead of broadening the existing CLI stdin source plan.

### Task 3: Emit Producer/HTTP Ownership Transitions

**Files:**
- Modify: `src/build/codegen_component_wasi_http.zig`
- Modify: `src/build/codegen_component_async_plan.zig`

- [x] Emit the root stream pair acquisition and retain both endpoints in frame slots.
- [x] Emit one resumable stream-write operation per literal, preserving the writer across pending callbacks and advancing only after `Ready`.
- [x] Construct the request and transfer it to `client.send` before writes, close/drop the writable endpoint exactly once after the last write, and keep the send subtask live until the terminal await.
- [x] Drop the readable endpoint, transmission future, response/error payload, waitable, and frame exactly once on every terminal path.

### Task 4: Verify Host Backpressure And Cleanup

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/http_request_body_producer.rs`
- Create: `examples/p3-runtime/test_rust_http_request_body_producer.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`

- [x] Run two calls in one Store: one with an immediately-ready write and one with a one-poll-pending write.
- [x] Require the host to observe the exact body bytes, capacity-one ordering, writer close, one request transfer per call, one success and one no-payload error result, and an empty `ResourceTable`.
- [x] Verify a pending write is woken and resumed without a second stream or writer allocation.

### Task 5: Documentation And Regression Closure

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `examples/p3-runtime/README.md`

- [x] Record the exact bounded producer shape and explicitly retain write-before-request producers, dynamic producers, arbitrary stream endpoints, trailers payload, and payload-bearing error-code variants as unsupported.
- [x] Run the focused Zig test, ABI/lowering/runtime scripts, `./src/build/test/run_tests.sh`, ReleaseSmall build, and `git diff --check`.

## Phase Exit Criteria

- The combined root-stream/HTTP ABI is assembled and linked from observed imports.
- A fixed guest-produced `[65,66]` body reaches `client.send` in a validated Component after the host consumer is attached.
- Ready and one-poll-pending writer completions both pass Rust/Wasmtime execution.
- Writer/readable/request/transmission/response resources are cleaned exactly once.
- No public ownership syntax or generic producer lowering is introduced.
