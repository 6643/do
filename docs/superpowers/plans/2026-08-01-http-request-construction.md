# HTTP Empty Request Construction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (recommended) or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one executable, descriptor-pinned HTTP request-construction slice for an empty request, then feed that owned request into the existing fixed `client.send` Component probe.

**Architecture:** Keep WIT `own`/`borrow` internal to the resource ABI and manifest. The compiler emits a bounded constructor plan for `request.new`: create empty `fields`, pass `none` for the body and request options, create a trailers future completed with `Ok(None)`, and retain the returned request/transmission-future handles in the async frame. The existing no-payload HTTP service lowering consumes the request exactly once; all other HTTP shapes remain rejected.

**Tech Stack:** Zig compiler, Core Wasm WAT, pinned `wasi:http@0.3.0-rc-2025-09-16`, `wasm-tools 1.254.0`, Rust/Wasmtime 47.0.2, shell regression fixtures.

## Global Constraints

- Use only the vendored WIT snapshot at `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16` and its pinned hashes.
- Do not expose `own<T>`, `borrow<T>`, `ref<T>`, pointers, or references in Do source; resource ownership remains compiler/manifest metadata.
- The admitted request shape is: empty `fields`, `option<stream<u8>> = none`, `future<result<option<trailers>, error-code>> = Ok(None)`, and `option<request-options> = none`.
- `request.new` is a synchronous static resource operation; its returned transmission future must be explicitly read or dropped before frame cleanup.
- Keep the existing cancellation contract: follow Component task/subtask terminal states and never claim rollback of external effects.
- Keep payload-bearing `error-code` lowering rejected because the pinned Wasmtime task-return nested-variant probe is not valid for this repository.
- Ordinary `do build` continues to reject async lowering; only `--p3-async-component` admits this fixed probe.
- Do not add request-body stream production, trailer payload lifting, dynamic EOF loops, or general `client.send` in this phase.

### Task 1: Pin The `request.new` Future/Resource ABI

**Files:**
- Modify: `src/build/p3_http_wit_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Create: `examples/p3-runtime/wit/http-request-new-probe.wit`
- Create: `examples/p3-runtime/test_do_http_request_new_abi.sh`
- Test: `src/build/p3_http_wit_manifest.zig`

**Interfaces:**
- Consumes: `HttpResourceGraph.request_new`, the pinned WIT package, and the installed `wasm-tools` toolchain.
- Produces: descriptor records for `[static]request.new`, its result-area layout, and the exact indexed `future.*` imports used to complete and dispose the trailers/transmission futures.

- [x] **Step 1: Add the red ABI fixture.**

  Build a minimal Core WAT probe that imports the pinned `request.new` operation and references the required indexed operations for the trailers future and returned transmission future. Assemble it with:

  ```bash
  wasm-tools parse "$wat" -o "$core_wasm"
  wasm-tools component new "$core_wasm" -o "$component_wasm"
  wasm-tools validate --features cm-async,cm-more-async-builtins "$component_wasm"
  ```

  The fixture must record the generated import types instead of assuming the future write/result-area words.

- [x] **Step 2: Verify the red boundary.**

  Run:

  ```bash
  cd src && zig test build/p3_http_wit_manifest.zig
  cd .. && bash examples/p3-runtime/test_do_http_request_new_abi.sh
  ```

  Expected: the manifest test fails because the request constructor's indexed future operations are not registered yet; the failure must not be a missing WIT package or parser error.

- [x] **Step 3: Register only observed ABI facts.**

  Add the `request.new` canonical entry with the already verified seven `i32` core parameters and indirect result area containing request and transmission-future handles. Add only the indexed `future-new`, `future-write`, `future-read`/`future-drop-readable`, and `future-drop-writable` entries that the assembled fixture proves. Preserve the descriptor index order: the trailers future is the second future/stream occurrence in the function signature and the returned transmission future is the next occurrence.

- [x] **Step 4: Verify the pinned registry.**

  Re-run the Zig manifest tests and the ABI shell fixture. Require `wasm-tools validate` to pass and require the generated WAT to contain the exact canonical import names; an unverified guessed signature is a failure.

### Task 2: Emit The Minimal Empty Request Constructor

**Files:**
- Modify: `src/build/codegen_component_wasi_http.zig`
- Modify: `src/build/codegen_component_async_plan.zig`
- Modify: `src/build/p3_async_manifest.zig`
- Create: `examples/p3-runtime/http-request-empty.do`
- Create: `examples/p3-runtime/test_do_http_request_empty_lowering.sh`
- Test: `src/build/codegen_component_wasi_http.zig`

**Interfaces:**
- Consumes: Task 1's descriptor entries, the existing `@wasi_resource` shells (`HttpHeaders`, `HttpRequest`, `HttpRequestOptions`), and the current async frame/cleanup helpers.
- Produces: one bounded `HttpRequestConstructorPlan` with explicit handle slots for headers, trailers future, request, and transmission future.

- [x] **Step 1: Add the red source contract and WAT assertions.**

  Add a fixed P3 fixture that requests an empty `HttpRequest` through the compiler-owned HTTP constructor path. Assert that pre-change lowering reports `UnsupportedP3AsyncHttpService`, and require the eventual WAT to contain:

  ```text
  [constructor]fields
  [future-new-1]request.new
  [future-write-1]request.new
  [future-drop-writable-1]request.new
  [static]request.new
  [resource-drop]request
  ```

  The source fixture must not declare `own<T>`, `borrow<T>`, or a copied `{ status, body }` substitute.

- [x] **Step 2: Parse only the bounded constructor shape.**

  Accept exactly: create empty headers; use `none` for `contents`; create and complete the trailers future with `Ok(None)`; use `none` for `options`; call `request.new`; bind its request and transmission-future tuple. Reject a body stream, non-empty trailers payload, dynamic option value, second constructor, or control flow with `UnsupportedP3AsyncHttpService`.

- [x] **Step 3: Emit construction and ownership transitions.**

  Emit the empty `fields` constructor, the exact future-new/write/close sequence, the two option-none tags, and the seven-word `request.new` call with its result-area pointer. Store the returned handles in the frame before any suspension. The request handle is the only value transferred to `client.send`; the transmission future is read or dropped through the registered operation before terminal cleanup.

- [x] **Step 4: Verify the Core artifact.**

  Run the focused Zig test and the shell fixture. Assemble and validate the generated component, and assert that no ARC helper, copied HTTP record payload, or synchronous fallback is emitted.

### Task 3: Execute Constructor Ownership In A Rust/Wasmtime Host

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/http_request_new.rs` (or modify it if a constructor binary already exists)
- Create: `examples/p3-runtime/test_rust_http_request_empty.sh`
- Modify: `examples/p3-runtime/Cargo.toml` only when the new binary must be listed explicitly

**Interfaces:**
- Consumes: Task 2's component and its request/fields/future imports.
- Produces: runtime evidence for one empty request, one completed trailers future, one request handle, one transmission-future disposal, and an empty `ResourceTable` after completion.

- [x] **Step 1: Add the red runtime expectation.**

  Run the host against the pre-constructor artifact and require failure if the component does not issue the canonical fields/future/request sequence.

- [x] **Step 2: Implement host-side request state.**

  Track fields, request, and future handles in `ResourceTable`. Make the trailers future complete as `Ok(None)` and record each future write/close/drop exactly once. Do not fabricate an `own`/`borrow` value in the Core integer alone.

- [x] **Step 3: Verify lifecycle and repeatability.**

  Execute the same component twice in one Store. Assert two independent request handles, two independent future lifecycles, no residual resource, and no double drop. Run the pending and already-ready future modes if the pinned ABI exposes both paths.

### Task 4: Feed The Constructed Request Into The Existing `client.send` Slice

**Files:**
- Modify: `src/build/codegen_component_wasi_http.zig`
- Modify: `examples/p3-runtime/http-service.do`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/http_service.rs`
- Modify: `examples/p3-runtime/test_http_service_abi_surface.sh`
- Create: `examples/p3-runtime/http-service-empty-request.do`
- Create: `examples/p3-runtime/test_rust_http_service_empty_request.sh`

**Interfaces:**
- Consumes: Task 2's owned request handle and the existing no-payload `client.send` task-return path.
- Produces: an end-to-end empty request -> `client.send` -> `Result<HttpResponse, HttpError>` probe with exactly-once request/response cleanup.

- [x] **Step 1: Add the red end-to-end fixture.**

  The fixture must construct the empty request, transfer it once to `send`, await the existing completion future, and narrow only the registered `Ok(response)` or no-payload `Err(error-code)` branches. A second use of the request must remain a `do check` error.

- [x] **Step 2: Connect the constructor result to `send`.**

  Replace the current pre-existing request parameter in this fixed probe with the constructor's request slot. Preserve the existing `[async-lower]send` import, frame-based completion, no-payload error handling, response status/body ownership rules, and cancellation order.

- [x] **Step 3: Exercise both host outcomes.**

  Run one successful response and one no-payload `DNS-timeout`/equivalent error in the Rust host. Assert independent frame pointers, one request transfer per call, one request drop on failure, one response drop on success, and no resource left in the host table.

- [x] **Step 4: Run the focused HTTP gate.**

  Execute the constructor ABI, constructor lowering, response status, bounded body, trailers, and empty-request service scripts. Then run `./src/build/test/run_tests.sh` and `git diff --check`.

### Task 5: Record The Phase Boundary

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/async-design.md`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `examples/p3-runtime/README.md`

**Interfaces:**
- Consumes: only the passing evidence from Tasks 1-4.
- Produces: a source-first record of the admitted empty-request path and its remaining blockers.

- [x] **Step 1: Record exact support.**

  State that the supported constructor has empty headers, no body, an immediate `Ok(None)` trailers future, and no request options; include the exact `--p3-async-component` command and all focused scripts.

- [x] **Step 2: Keep residual blockers explicit.**

  Retain `AsyncLoweringUnavailable` for ordinary builds and unsupported source shapes. List request body producers, dynamic trailer streams, trailer payload lifting, payload-bearing error-code variants, general resource method lowering, and general `client.send` as later phases.

- [x] **Step 3: Verify documentation claims.**

  Run the complete focused matrix, `./src/build/test/run_tests.sh`, `git diff --check`, and confirm every documented command points to a checked-in fixture.

## Phase Exit Criteria

- The exact pinned `request.new` and indexed future ABI is verified by `wasm-tools`, not inferred from names alone.
- A minimal empty request is constructed with explicit future completion and all resource/future handles are disposed exactly once.
- The existing fixed `client.send` path can consume the constructed request in both success and no-payload error cases.
- Ordinary async build rejection, no-rollback cancellation, and internal-only `own`/`borrow` semantics remain unchanged.
- No claim is made for request bodies, dynamic trailers, payload error variants, or general HTTP lowering.
