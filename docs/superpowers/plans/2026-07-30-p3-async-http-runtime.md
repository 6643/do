# P3 Async HTTP Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing async syntax, frame metadata, pinned P3 facts, and
resource ownership checks into an executable, descriptor-driven Component
runtime, then lower the pinned WASI HTTP resource graph without changing Do's
source type system.

**Architecture:** Do source continues to use nominal `@wasi_resource` shells,
`Future<T>`, `Stream<T>`, and `Result<T, E>`. WIT `own` and `borrow` remain in
the pinned registry and canonical ABI layer. General async lowering begins with
a scalar/unit selected P3 operation, binds `codegen_async_model` frames to
actual function bodies, and only then admits HTTP resources, whose body and
trailers require the same future/stream runtime.

**Tech Stack:** Zig compiler, Core Wasm/WAT, Component Model async ABI,
`wasm-tools`, Rust Wasmtime Component host runner, pinned `wasi-http` WIT.

## Global Constraints

- Do exposes no pointer, reference, `own<T>`, or `borrow<T>` source syntax.
- `@cancel(Future<T>)` follows the pinned Component task/subtask ABI and makes
  no rollback, compensation, or external-effect acknowledgement promise.
- A host adapter is replaceable: Rust is a test/runtime implementation, not a
  compiler dependency or ABI requirement.
- No async source may silently lower to synchronous Core WAT. Preserve
  `AsyncLoweringUnavailable` until each admitted descriptor has executable
  lowering and host execution evidence.
- `wasi:http/client.send` remains unavailable until request/response resource
  ownership, async Result lift/lower, response streams, trailers, cancellation,
  and destructors are covered by real component execution tests.
- Work in the existing dirty checkout. Do not reset, clean, overwrite unrelated
  work, stage, commit, or push without an explicit request.

---

### Task 1: Bind Async Frame Metadata To Parsed Functions

**Files:**
- Create: `src/build/codegen_emit_async.zig`
- Modify: `src/build/codegen_async_model.zig`
- Modify: `src/build/codegen_collect_functions.zig`
- Modify: `src/build/codegen_model.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Create: `src/build/test/compile_ok/370_async_frame_model.do`
- Create: `src/build/test/compile_ok/370_async_frame_model.expect`

**Consumes:** `parser.FuncSig.is_async`, `codegen_async_model.FrameModel`, and
the fixed header layout: state at offset 0, waitable set at 4, cleanup flags at
8, completion value at 12, source live slots from 16.

**Produces:** An internal `AsyncFunctionPlan` for every parsed async function.
It owns the source name, frame layout, await-site state IDs, and cleanup state;
the normal synchronous function emitter does not emit a body for those plans.

- [ ] **Step 1: Write the failing model test.**

  Add an async function with two awaits and live `i32`/`i64` locals. Assert the
  generated test WAT contains state IDs 1 and 2, cleanup state 3, and frame
  offsets 16 and 24. The expected values must be literals, not derived from the
  collector.

- [ ] **Step 2: Verify red.**

  Run `cd src && zig test build/codegen_async_model.zig`.

  Expected: the new program cannot yet reach a collected async function plan.

- [ ] **Step 3: Add `AsyncFunctionPlan`.**

  Keep parsing and live-slot collection in `codegen_async_model.zig`. Add a
  collector called by `codegen_collect_functions.zig` that receives the parsed
  signature/body token span and returns one plan only for `sig.is_async`.
  Reject unsupported captured storage with the existing
  `UnsupportedAsyncFrameSlot` error; do not silently omit a slot.

- [ ] **Step 4: Verify green.**

  Run `cd src && zig test build/codegen_async_model.zig` and the single
  compile fixture through `./bin/do test` after rebuilding.

### Task 2: Emit One Descriptor-Driven Scalar Async Operation

**Files:**
- Modify: `src/build/codegen_emit_async.zig`
- Modify: `src/build/codegen_p3_wait_for.zig`
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Create: `src/build/test/compile_ok/371_async_wait_for_component.do`
- Create: `src/build/test/compile_ok/371_async_wait_for_component.expect`
- Create: `examples/p3-runtime/test_do_generic_wait_for_lowering.sh`

**Consumes:** `AsyncFunctionPlan` and the existing pinned
`wasi:clocks/monotonic-clock.wait-for` descriptor.

**Produces:** A generic emitter path for a unit/scalar async imported operation:
frame allocation, state dispatch, suspend, wake/resume, terminal cleanup, and
`task.return`. The existing fixed probe remains as a characterization test
until this path produces equivalent component artifacts.

- [ ] **Step 1: Write the failing WAT/component test.**

  The fixture must use `async run() -> nil`, bind one future, await it, and
  assert the component WAT has a per-call frame allocation, state store before
  suspension, `[async-lower]wait-for`, and one `task.return` path. It must not
  contain a global completion slot at memory offset zero.

- [ ] **Step 2: Verify red.**

  Run `cd src && zig test build/codegen_emit_async.zig` and
  `bash examples/p3-runtime/test_do_generic_wait_for_lowering.sh`.

  Expected: `AsyncLoweringUnavailable` or absent generic frame WAT.

- [ ] **Step 3: Implement only the admitted descriptor shape.**

  Accept descriptors whose canonical result is unit or one scalar. Emit a
  state-machine entry that writes the resume state to the frame, invokes the
  descriptor's exact pinned async import name, and resumes only through the
  frame pointer passed by the runtime. Reuse the frame header constants; do
  not add an operation ID, host broker, or global completion storage.

- [ ] **Step 4: Verify host execution.**

  Run the new shell test, `wasm-tools component validate`, and the Rust host
  runner. Assert two simultaneous calls complete independently in one Store.

### Task 3: Make Cancellation And Defers Use The Generic Frame Exit

**Files:**
- Modify: `src/build/codegen_emit_async.zig`
- Modify: `src/build/codegen_p3_wait_for.zig`
- Modify: `src/build/codegen_ownership.zig`
- Create: `src/build/test/compile_ok/372_async_cancel_cleanup.do`
- Create: `src/build/test/compile_ok/372_async_cancel_cleanup.expect`
- Create: `examples/p3-runtime/test_do_generic_cancel_cleanup.sh`

**Consumes:** Task 2 generic frame dispatch and the pinned direct
`[subtask-cancel]` ABI.

**Produces:** Await completion, cancellation, failure, and return converge at
one LIFO cleanup path. Cancellation marks the future consumed, waits for the
ABI terminal transition required by the selected runtime, executes defers and
resource cleanup once, then invalidates/releases the frame.

- [ ] **Step 1: Write the failing cleanup ordering test.**

  Use an async function with a `defer`, a pending future, and `@cancel`.
  Assert WAT orders `[subtask-cancel]` before the cleanup label and emits the
  defer release once. Assert no rollback, `operation_id`, or acknowledgement
  import occurs.

- [ ] **Step 2: Verify red.**

  Run `cd src && zig test build/codegen_emit_async.zig`.

- [ ] **Step 3: Route all terminal paths through one emitter helper.**

  Define `emit_async_terminal_cleanup(frame, reason)` in
  `codegen_emit_async.zig`; it emits active defers in reverse source order,
  releases owned frame slots, clears runtime context, and frees the frame.
  Make cancellation call the descriptor-pinned subtask instruction before
  this helper.

- [ ] **Step 4: Verify green.**

  Run the focused Zig tests, the cancellation shell test, and the Rust runner.

### Task 4: Admit Resource Descriptors To The Canonical ABI Layer

**Files:**
- Modify: `src/build/resource_abi_registry.zig`
- Modify: `src/build/codegen_emit_wasi.zig`
- Modify: `src/build/codegen_component_resource_probe.zig`
- Create: `src/build/codegen_component_resource_async.zig`
- Create: `src/build/test/compile_ok/373_async_resource_result.do`
- Create: `src/build/test/compile_ok/373_async_resource_result.expect`
- Create: `examples/p3-runtime/test_do_async_resource_result.sh`

**Consumes:** Task 2 scalar generic frame path and the existing internal
`request -> Result<response, error-code>` descriptor shape.

**Produces:** Canonical lift/lower of one owned resource input and one owned
Result payload. The emitter consumes the request handle at call start, records
the response handle only on the Ok completion path, and routes all terminal
paths through Task 3 cleanup.

- [ ] **Step 1: Write the failing resource-result fixture.**

  Use the private resource probe, transfer request into one async operation,
  await its Result, narrow with `@is(result, Ok)`, then transfer the response
  into a registered consumer. Assert request reuse fails in `do check` and
  WAT carries a resource handle, not a copied struct payload.

- [ ] **Step 2: Verify red.**

  Run the focused `do check`, `cd src && zig test build/codegen_emit_wasi.zig`,
  and the resource-result shell test.

- [ ] **Step 3: Implement canonical resource ownership crossing.**

  Add a descriptor-only resource argument/result adapter. It may accept only
  a single `own` input and `result<own<resource>,error-code>` result. Reject
  multiple resources, borrowed resources across suspension, resource lists,
  and copied resource structs with explicit unsupported diagnostics.

- [ ] **Step 4: Verify green.**

  Run the focused tests plus component assembly and ResourceTable host
  execution. Verify the response is dropped exactly once after transfer.

### Task 5: Lower The HTTP Request/Response Construction Graph

**Files:**
- Modify: `src/build/resource_abi_registry.json`
- Modify: `src/build/p3_http_wit_manifest.zig`
- Create: `src/build/codegen_component_wasi_http.zig`
- Create: `src/build/test/check/374_http_request_resource_shape.do`
- Create: `src/build/test/compile_err/374_http_client_send_lowering_unavailable.do`
- Create: `src/build/test/compile_err/374_http_client_send_lowering_unavailable.expect`
- Create: `examples/p3-runtime/test_do_wasi_http_request_shape.sh`

**Consumes:** Task 4's generic resource result adapter and the vendored
`wasi:http@0.3.0-rc-2025-09-16` snapshot.

**Produces:** Checked nominal Do bindings for `headers`, `request-options`,
`request`, and `response`; no copied `HttpRequest`/`HttpResponse` record is
used as the WIT ABI. `client.send` stays build-rejected until Task 6, while
the declared resource graph is checked against the pinned WIT source.

- [ ] **Step 1: Write failing registry/shape tests.**

  Assert `request.new` requires headers, optional body stream, trailers future,
  and request options. Assert a copied `{ status, body }` record cannot satisfy
  `response` resource binding.

- [ ] **Step 2: Verify red.**

  Run `cd src && zig test build/p3_http_wit_manifest.zig` and the new check
  fixture.

- [ ] **Step 3: Add descriptor facts only.**

  Record the WIT operations and ownership facts without exposing `own` or
  `borrow` in Do source. Keep compile-mode rejection explicit while stream and
  trailers are unavailable.

- [ ] **Step 4: Verify green boundary.**

  Run focused tests and prove a `do build` HTTP send fixture fails with the
  designated unsupported-lowering diagnostic.

**Current checkpoint (2026-08-01):** Task 5's resource-graph boundary is now
implemented and verified. `p3_http_wit_manifest.zig` validates the pinned
`fields`/headers alias, `request-options`, `request`, `response`, `request.new`,
both `consume-body` signatures, and the `client.send` world signature. The HTTP
plan requires matching nominal Do shells and the unified Component target emits
a service WIT sidecar without copying response records. Focused Zig tests,
`test_do_wasi_http_request_shape.sh`, `test_http_service_abi_surface.sh`, and
the full regression pass. Task 6 remains intentionally open: request
construction, body/trailer stream execution, payload-bearing error-code
lowering, and general `client.send` runtime execution still require their own
Component/Rust matrix.

**Task 6 prerequisite checkpoint (2026-08-01):** the pinned manifest now
exposes structured operation facts for `request.new` and both `consume-body`
operations, including receiver movement and independent stream/trailers
results. This is metadata only; no source-level constructor or body consumer is
admitted until the canonical emitter and host execution matrix exist.

**Task 6 ABI-shape checkpoint (2026-08-01):** the real `client.send` descriptor
is now represented by an internal `http_resource_result` lowering shape instead
of being treated as an unclassifiable special case. Its pinned task-return
completion layout is recorded as `i32 i32 i32 i64 i32 i32 i32 i32`, matching the
WIT/toolchain-generated handler ABI. The generic async target still rejects this
shape; only the existing fixed HTTP service plan consumes it, so this change
does not admit general `client.send`, request construction, body streams, or
trailers. The fixed emitter now renders both the task-return type and its zero
payload tail from those descriptor words, so a registry layout change cannot be
silently masked by a stale WAT template.

**Response status probe checkpoint (2026-08-01):** the unified Component target
now admits one synchronous resource operation slice for
`response.get-status-code`: it accepts a nominal `HttpResponse` shell, calls
the canonical borrowed method, explicitly drops the owned response, and
returns the `u16` status. The emitter is covered by focused Zig tests and
`examples/p3-runtime/test_do_http_response_status_lowering.sh`, including
`wasm-tools` parse/embed/new/validate. This is a resource ABI probe only; it
does not admit response body streams, trailers, request construction, or
general `client.send` execution.

The same fixture now runs through
`examples/p3-runtime/rust-host-runner/src/bin/http_response_status.rs`:
Wasmtime supplies one host response with status `27815`, the canonical method
is called once, and the explicit resource drop leaves the host resource table
empty. The shell test therefore covers codegen, component assembly, and host
execution rather than validation alone.

**Response body stream checkpoint (2026-08-01):** a separate fixed probe now
executes one, two, or three bounded linear successful `@next(reader)`
operations after `response.consume-body`, or accepts a terminal `Err(nil)`
EOF result. The frame carries a read index and restarts the stream read after
each `Ok(u8)` callback; terminal cleanup cancels
the trailers future and drops the stream, future, waitable, and frame exactly
once. The verified scripts are
`examples/p3-runtime/test_rust_http_response_consume_body_read.sh` and
`examples/p3-runtime/test_rust_http_response_consume_body_two_read.sh` and
`examples/p3-runtime/test_rust_http_response_consume_body_three_read.sh` and
`examples/p3-runtime/test_rust_http_response_consume_body_eof.sh`.
Conditional/dynamic EOF loops, trailer payload lifting, request construction, and general
`client.send` execution remain outside this checkpoint.

**Trailers future read checkpoint (2026-08-01):** the same fixed probe now also
accepts one linear `await(completion)` after body termination, followed by a
discard of `Result<option<trailers>, HttpError>`. The manifest records
`[async-lower][future-read-2]response.consume-body`; the frame uses event code
`4` for a pending `future.read` and the normal callback wait code `2`. Both an
already-ready host future and a one-poll-pending future pass component assembly
and Wasmtime execution. This checkpoint deliberately discards the lifted
trailers payload; conditional reads, payload inspection, request construction,
and general `client.send` execution remain open.

### Task 6: Add Stream, Trailer, And HTTP Client Send Execution

**Files:**
- Modify: `src/build/codegen_emit_async.zig`
- Modify: `src/build/codegen_component_wasi_http.zig`
- Modify: `src/build/codegen_emit_wasi.zig`
- Modify: `src/build/sema_async.zig`
- Create: `src/build/test/compile_ok/375_http_client_send_component.do`
- Create: `src/build/test/compile_ok/375_http_client_send_component.expect`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/http_client_send.rs`
- Create: `examples/p3-runtime/test_do_wasi_http_client_send.sh`

**Consumes:** Tasks 2-5.

**Produces:** Executable `client.send` lowering returning
`Future<Result<HttpResponse, HttpError>>`, response-body consumption into
`Stream<u8>`, trailers future handling, cancellation, and exact resource drop
ordering under a Rust host runner.

- [ ] **Step 1: Write failing two-call host test.**

  Run two concurrent client sends in one Store. The host must produce one Ok
  response and one Err result, record independent frame pointers, and count
  pending/wake/completion transitions. The test fails if any completion state
  is shared globally.

- [ ] **Step 2: Verify red.**

  Run `bash examples/p3-runtime/test_do_wasi_http_client_send.sh`.

- [ ] **Step 3: Implement descriptor-driven HTTP lowering.**

  Lift request handles, invoke the pinned async import, lower the Result on
  completion, preserve response ownership only in the Ok branch, and use the
  Task 3 terminal cleanup for all other paths. Bind `consume-body` only after
  `Stream<u8>` and trailer future runtime operations are emitted.

- [ ] **Step 4: Verify component execution.**

  Run the shell test, `wasm-tools component embed/new/validate`, the Rust host
  runner, `./src/build/test/run_tests.sh`, and `git diff --check`.

### Task 7: Documentation And Compatibility Closure

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `doc/spec_rules.md`
- Modify: `doc/grammar.peg`
- Modify: `lib/http.client.do`
- Modify: `README.md`

**Consumes:** Only independently verified behavior from Tasks 1-6.

**Produces:** Documentation and standard library declarations that distinguish
the resource ABI from an optional copied convenience API, list exact supported
HTTP operations, and remove each obsolete `AsyncLoweringUnavailable` guard
only for descriptors with execution coverage.

- [ ] **Step 1: Write a documentation consistency checklist.**

  List every admitted descriptor, its Do source shell, WIT ownership, supported
  build target, component assembly test, and host execution test. Include an
  explicit unsupported list for all remaining HTTP methods.

- [ ] **Step 2: Update only verified claims.**

  Keep `own/borrow` internal, state cancellation's no-rollback boundary, and
  retain copied `HttpRequest`/`HttpResponse` records only as a convenience
  layer that cannot bind directly to WIT resources.

- [ ] **Step 3: Run final verification.**

  Run every focused Zig/Rust/shell test introduced above, then:

  ```bash
  ./src/build/test/run_tests.sh
  git diff --check
  ```

  Record command exits and the exact unsupported residual surface.
