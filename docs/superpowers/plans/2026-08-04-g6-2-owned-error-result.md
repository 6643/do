# G6.2 Owned-Error Result Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Add one private Component resource-result shape whose `Err` arm carries an owned error resource, and prove its exactly-once cleanup without introducing public ownership or reference syntax.

**Architecture:** Register a separate private descriptor, `do:resource-probe-owned-error@0.1.0`, so the existing `do:resource-probe/http@0.1.0` contract remains unchanged. Reuse the current result frame and task-return epilogue, but add a distinct error-resource handle slot and release it exactly once on the error terminal; success, pending, cancellation, and unsupported shapes remain explicitly bounded.

**Tech Stack:** Zig 0.16 compiler/tests, Do WAT/WIT emitter, pinned `wasm-tools 1.254.0`, Rust 2024, Wasmtime `47.0.2`, Bash regression harness.

## Global Constraints

- Keep `own<T>`, `borrow<T>`, `ref<T>`, pointer, and reference syntax out of the public Do language.
- Do not widen arbitrary async-call lowering, producer expressions, producer leases, list/variant payloads, forwarding depth, or filesystem async methods.
- Cancellation never rolls back an external effect; it only performs the registered task/resource cleanup once.
- The new descriptor is private and registry-bound; unknown resource-result shapes must still fail with the existing unsupported-lowering diagnostic.
- Keep `wasm-tools 1.254.0` and Wasmtime `47.0.2` pinned.
- Preserve all unrelated dirty worktree changes. Do not reset, clean, checkout, commit, or push.

### Task 1: Freeze the descriptor and prove the pinned WIT shape

**Files:**

- Create: `docs/superpowers/specs/2026-08-04-g6-2-owned-error-result-design.md`
- Create: `examples/p3-runtime/wit/resource-probe-owned-error.wit`
- Create: `examples/p3-runtime/test_rust_owned_error_result_shape.sh`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/owned_error_result_shape.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` (add the explicit `do-p3-owned-error-result-shape-host-runner` bin entry)

**Interfaces:**

- WIT package: `do:resource-probe-owned-error@0.1.0`.
- Interface `http` declares `request`, `response`, and `error-resource` resources.
- `send: async func(request: request) -> result<response, error-resource>`.
- The probe exposes pending, immediate success, and ready error-resource modes.

- [x] **Step 1: Write the WIT fixture and design contract.**

  Record that `Ok(response)` transfers the response handle to the guest, while `Err(error-resource)` transfers the error handle to the guest error terminal. The host must observe one drop for the request and one drop for exactly the selected result resource.

- [x] **Step 2: Add the Rust/Wasmtime probe before compiler changes.**

  Implement host counters for request, response, and error-resource create/drop. Run pending and immediate `Ok`, plus ready `Err`, and assert the component `ResourceTable` is empty after the guest releases the selected result.

- [x] **Step 3: Run the pinned assembly gate.**

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_rust_owned_error_result_shape.sh
  ```

  Expected: the hand-written Component and Rust/Wasmtime harness either pass the ownership matrix or produce an exact pinned-tool rejection. A rejection stops this plan at Task 1 and is recorded as no-go; no emitter workaround is allowed.

### Task 2: Add red Do lowering and registry boundaries

**Files:**

- Create: `src/build/p3_async_resource_owned_error_probe.wit`
- Create: `examples/p3-runtime/owned-error-resource-probe.do`
- Create: `examples/p3-runtime/test_do_owned_error_result_lowering.sh`
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/codegen_component_resource_probe.zig`

**Interfaces:**

- The Do fixture uses an internal binding equivalent to `Result<HttpResponse, HttpErrorResource>` and a named `@cancel(completion)` path.
- Async registry selection is exact on package, interface, member, and version; the private `@host_func` fixture intentionally bypasses the general resource ABI registry so this slice does not widen public ownership validation.

- [x] **Step 1: Write failing assertions.**

  Require a distinct `[resource-owned-error-result]` marker, an error-resource handle slot, and a drop import on the `Err` path. Assert that the existing descriptor remains byte-for-byte compatible at its current markers.

- [x] **Step 2: Add negative fixtures.**

  Reject an unregistered `Result<Response, OtherResource>`, a second use of the transferred error resource, a double drop, and an implicit scope-drop cleanup path. Keep `borrow<T>` and arbitrary resource-result signatures rejected.

- [x] **Step 3: Run the red gate.**

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_do_owned_error_result_lowering.sh
  ```

  Expected: the new positive fixture fails only at the missing emitter branch; all negative fixtures continue to fail for their intended diagnostics.

### Task 3: Implement the minimal owned-error terminal

**Files:**

- Modify: `src/build/codegen_component_resource_async.zig`
- Modify: `src/build/codegen_component_resource_probe.zig`
- Modify: `src/build/p3_async_resource_owned_error_probe.wit`

**Interfaces:**

- On ready `Err(error-resource)`, store the error handle in the result payload slot, store the error tag, call the existing task-return path, and release the request/frame/canonical buffer exactly once.
- On ready `Ok(response)`, preserve the existing response ownership path and do not drop the response in the producer.
- On explicit cancellation, drop the pending child and any registered request/error state exactly once; never synthesize rollback.

- [x] **Step 1: Implement only the registered branch.**

  Guard by the exact descriptor identity and result shape. Return `UnsupportedP3AsyncComponent` for every other resource-result layout.

- [x] **Step 2: Run focused green checks.**

  ```bash
  cd src && zig test build/codegen_component_resource_async.zig
  cd src && zig test build/codegen_component_async.zig
  TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_do_owned_error_result_lowering.sh
  ```

  Acceptance: pending/immediate success and ready owned-error lowering pass; request and exactly one selected result resource are released on every terminal path.

### Task 4: Close the generated and hand-written runtime matrix

**Files:**

- Modify: `examples/p3-runtime/test_rust_owned_error_result_shape.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/owned_error_result_shape.rs`
- Create or modify: generated Component/WAT fixture under `examples/p3-runtime/`

**Interfaces:**

- Generated Component and hand-written Component must expose the same world and resource identities.
- Runtime modes: pending `Ok`, immediate `Ok`, ready `Err(error-resource)`, and explicit cancellation of a pending completion.

- [x] **Step 1: Assert ownership counters per mode.**

  `Ok` creates/drops one response and zero error resources; `Err` creates/drops one error resource and zero responses; cancellation creates/drops neither result payload and leaves `table-empty=true`.

- [x] **Step 2: Run Rust/Wasmtime.**

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_rust_owned_error_result_shape.sh
  ```

  Acceptance: generated and hand-written components agree on all counters, terminal statuses, and empty-table cleanup.

### Task 5: Re-run the repository matrix and update status

**Files:**

- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/master_plan.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/async-design.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [x] **Step 1: Run focused formatting and build checks.**

  ```bash
  (cd src && zig fmt --check build/codegen_component_resource_async.zig build/codegen_component_resource_probe.zig)
  rustfmt --edition 2024 --check examples/p3-runtime/rust-host-runner/src/bin/owned_error_result_shape.rs
  CC="$PWD/examples/p3-runtime/rust-host-runner/zig-cc.sh" \
  CXX="$PWD/examples/p3-runtime/rust-host-runner/zig-cc.sh" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/examples/p3-runtime/rust-host-runner/zig-cc.sh" \
    cargo check --locked --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml
  git diff --check
  ```

- [x] **Step 2: Run the standard regression matrix.**

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp/owned-error-default" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/owned-error-zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/owned-error-zig-gcache" \
    ./src/build/test/run_tests.sh
  TMPDIR="$PWD/.tmp/do-tmp/owned-error-wasm" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/owned-error-zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/owned-error-zig-gcache" \
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  cd src && zig test main.zig
  ./src/build/test/run_release_smoke.sh
  ```

- [x] **Step 3: Record the exact boundary.**

  Mark only the new private owned-error descriptor as verified. Keep general producer leases, arbitrary producer expressions, `borrow<T>`, list/variant resource fields, wider forwarding/nesting, public ownership syntax, and D2 real host I/O pending or deferred.

## Exit Criteria

The phase is complete only when the pinned probe, Do red/green gate, generated and hand-written Rust/Wasmtime matrix, negative boundaries, full regression, and status documents all agree. If Task 1 cannot assemble on the pinned toolchain, the phase ends with a recorded no-go and no compiler-lowering change.
