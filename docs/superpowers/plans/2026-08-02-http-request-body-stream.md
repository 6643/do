# HTTP Request Body Stream Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (recommended) or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one pinned, executable HTTP request body stream slice without exposing WIT ownership types or general stream producer syntax.

**Architecture:** Reuse the existing bounded CLI `StreamReader<u8>` acquisition ABI as the request body source. Extend the HTTP constructor plan to retain the reader and its independent completion future, pass the reader to `request.new`, and route all terminal paths through the existing request/send cleanup order. Keep the body source finite and host-driven; no source-level loop or writer lowering is added here.

**Tech Stack:** Zig compiler, Core Wasm WAT, pinned WASI WIT, `wasm-tools 1.254.0`, Rust/Wasmtime host runner.

## Global Constraints

- Do source does not expose `own<T>`, `borrow<T>`, `ref<T>`, pointers, or references.
- Only `Stream<u8>` from pinned `wasi:cli/stdin.read-via-stream` is admitted as a request body source.
- Body source completion and HTTP transmission futures have independent exactly-once cleanup.
- The request is transferred to `client.send` exactly once.
- Dynamic EOF loops, arbitrary body producers, trailer payload lifting, payload error-code variants, and general HTTP lowering remain rejected.
- Work in the existing dirty checkout; do not reset, clean, commit, or push without explicit authorization.

### Task 1: Freeze The Body Stream ABI

**Files:**
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/p3_http_wit_manifest.zig`
- Create: `examples/p3-runtime/wit/http-request-body-probe.wit`
- Create: `examples/p3-runtime/test_do_http_request_body_abi.sh`
- Test: `src/build/p3_async_manifest.zig`

**Interfaces:**
- Consumes the pinned `request.new` WIT operation and the existing stream-reader descriptor.
- Produces the exact indexed `stream.*` names and core signatures needed by the constructor emitter.

- [x] **Step 1: Add a red WIT/Core probe.**

  Add a minimal world that exposes `request.new` with `option<stream<u8>>` and a
  `run` async export. Assemble a hand-written Core WAT that imports the body
  stream operations with the candidate descriptor names. The probe must fail
  for an unregistered descriptor rather than silently accepting a guessed ABI.

- [x] **Step 2: Register only observed facts.**

  The pinned CLI `read-via-stream` descriptor already exists in
  `p3_async_registry.json`; no guessed HTTP-body descriptor was added. The
  probe records the separate `wasi:http/body.acquire` facts without promoting
  them to a compiler source shape.

  Add the body stream shape to the request constructor descriptor: `u8` reader,
  stream index `0`, and the exact `new`, `drop-readable`, `future-read`, and
  completion-drop operations emitted by `wasm-tools`. Preserve the existing
  trailers/transmission future indices.

- [x] **Step 3: Run the ABI gate.**

  Run `cd src && zig test build/p3_async_manifest.zig`, then
  `bash examples/p3-runtime/test_do_http_request_body_abi.sh`; require assembly,
  component validation, and exact import-name assertions.

### Task 2: Extend The Constructor Plan

**Files:**
- Modify: `src/build/codegen_component_wasi_http.zig`
- Modify: `src/build/codegen_component_async_plan.zig`
- Create: `examples/p3-runtime/http-request-body.do`
- Create: `examples/p3-runtime/test_do_http_request_body_lowering.sh`
- Test: `src/build/codegen_component_wasi_http.zig`

- [x] **Step 1: Add the failing source shape.**

  The fixture acquires `Stream<u8>` plus its completion future, calls
  `request.new(reader)`, sends the resulting request exactly once, and awaits
  the existing `Result<HttpResponse,HttpError>`. Assert that the current
  compiler rejects the body shape with `UnsupportedP3AsyncHttpService`.

- [x] **Step 2: Parse the fixed linear sequence.**

  Require one body acquisition, one `@get` reader binding, one `@get`
  completion binding, one constructor call, one send call, and one terminal
  completion operation. Reject a second reader, a second constructor, a body
  loop, or an unregistered stream type.

- [x] **Step 3: Emit body ownership transitions.**

  Add the body source import and pair extraction to the frame. Pass the reader
  half as the `option<stream<u8>>` payload, retain the source completion future,
  and release it only after send reaches terminal state. Keep the existing
  empty-fields, trailers, options, request, transmission-future, and response
  cleanup order.

- [x] **Step 4: Verify generated WAT.**

  Run the focused Zig test and lowering shell script. Assert the body stream
  import, request constructor call, one source completion cleanup, one request
  transfer, and no synchronous fallback or ARC helper.

### Task 3: Verify Rust/Wasmtime Body Ownership

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/http_request_body.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/test_rust_http_request_body.sh`
- Create: `examples/p3-runtime/test_rust_http_service_body.sh`

- [x] **Step 1: Implement the finite body source.**

  Return exactly `[65,66]` from the body reader, construct both ready and
  one-poll-pending completion modes, and record each read/drop/close event. The
  runner's unit test polls both future modes directly; the baseline admitted
  Component fixture uses the cancellation path and does not await this
  independent source completion future.

- [x] **Step 2: Exercise success and no-payload error.**

  Run two calls in one Store. Assert body bytes, independent request handles,
  one request transfer per call, one response drop on success, one request-side
  cleanup on error, and no residual `ResourceTable` entry.

- [x] **Step 3: Run focused runtime checks.**

  Require the runner markers for both calls, body bytes `[65,66]`, completion
  cleanup, and `table-empty=true`.

### Task 4: Documentation And Regression Closure

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/async-design.md`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `examples/p3-runtime/README.md`

- [x] **Step 1: Record the exact admitted body shape.**

  State that only the pinned CLI `Stream<u8>` source and finite host sequence are
  supported; retain the no-rollback cancellation rule and internal-only WIT
  ownership semantics.

- [x] **Step 2: Run all verification.**

  Run the body ABI, lowering, runtime, existing HTTP focused scripts,
  `./src/build/test/run_tests.sh`, and `git diff --check`.

  The body plan rejects non-pinned stream descriptors at the HTTP admission
  boundary, including descriptors with a spoofed canonical import under the
  same locator/member. The Rust runner executes both completion-mode
  configurations for exactly-once cancellation cleanup; its unit test drives
  ready and one-poll-pending future states directly.

### Task 5: Add Serialized Source-Completion Await

**Files:**
- Modify: `src/build/codegen_component_wasi_http.zig`
- Create: `examples/p3-runtime/http-request-body-await-completion.do`
- Create: `examples/p3-runtime/test_do_http_request_body_await_completion_lowering.sh`
- Create: `examples/p3-runtime/test_rust_http_request_body_await_completion.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/http_request_body.rs`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/async-design.md`
- Modify: `examples/p3-runtime/README.md`

- [x] **Step 1: Add the serialized source shape and emitter assertions.**

  Accept exactly one `await(source_done)` between the pinned acquisition and
  `request.new(reader)`. Require the registered
  `[async-lower][future-read-1]read-via-stream` import and reject payload/error
  handling outside the no-payload success case.

- [x] **Step 2: Emit the staged completion state machine.**

  Store the source completion, completion-result pointer, and constructed
  request in GC frame slots. Start the source future read first; on event `4`,
  construct the request and start `client.send`. Keep send/source completion
  serialized, and drop the source completion exactly once on every terminal
  task-return path.

- [x] **Step 3: Verify pending and ready Component execution.**

  Assemble and validate the generated Component. The Rust runner observes four
  total source-completion polls in pending-once mode and two in ready mode
  across two calls, with the same body, response, resource-table, and cleanup
  assertions as the cancellation fixture. With the explicit ordering guard,
  both request constructor calls are rejected unless the corresponding source
  completion has already reached `Ready`.

## Phase Exit Criteria

- Body stream ABI names are observed from the pinned toolchain and registered.
- A non-empty body reaches `client.send` in a validated Component.
- A serialized source-completion await reaches `client.send` in a validated Component.
- Two Rust/Wasmtime calls clean all body, future, request, response, and frame state exactly once.
- Unsupported dynamic and public ownership surfaces remain explicit.
