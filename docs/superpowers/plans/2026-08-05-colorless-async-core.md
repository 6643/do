# Colorless Async Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** implement `@async`, `@await`, and `@cancel` as the canonical Do task operations and remove semantic async color through an implicit root-task bridge.

**Architecture:** Ordinary functions remain the only source declaration form. Semantic analysis marks functions containing `@await` as resumable. Direct synchronous calls use a compiler-owned root task driver; explicit `@async(call)` creates an affine Future. Existing descriptor-specific Component emitters remain the oracle until the generic path is green.

The WIT binding prerequisite is the separate
`docs/superpowers/plans/2026-08-05-wit-bindgen-do.md` plan. Its generated
`wit/*.do` modules and `manifest.json` are consumed here; this plan does not
implement a second WIT parser or infer async effects from source names.

**Tech Stack:** Zig `0.16.0`, Do lexer/parser/sema/codegen, WAT/WIT, pinned `wasm-tools 1.254.0`, Rust `1.97.1`, Wasmtime `47.0.2`.

## Global Constraints

- Canonical source operations are `@async`, `@await`, and `@cancel`.
- `async name(...) -> T` is migration-only and must not gain new capability.
- `Future<T>` remains the task handle; do not add public `Task<T>` in this phase.
- Direct synchronous calls to resumable functions use an implicit compiler-owned root task.
- A Future is affine and must be consumed exactly once by `@await` or `@cancel`.
- Cancellation does not roll back external side effects.
- Do not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax.
- Preserve current bounded WIT descriptors and their Rust/Wasmtime cleanup gates.
- Consume WIT async/future/stream/resource facts only from the pinned
  `do wit bind` manifest.

---

### Task 1: Parser and intrinsic recognition

**Files:**
- Modify: `src/build/lexer.zig`
- Modify: `src/build/parser.zig`
- Modify: `src/build/sema_tokens.zig`
- Create: `src/build/test/compile_ok/416_colorless_async_intrinsics.do`
- Create: `src/build/test/compile_err/416_colorless_async_intrinsic_redefinition.do`
- Create: `src/build/test/compile_err/416_colorless_async_intrinsic_redefinition.expect`

**Interfaces:**
- Consumes: existing `@` intrinsic token handling and Future type syntax.
- Produces: parsed forms for `@async(call)`, `@await(task)`, and `@cancel(task)`;
  ordinary user declarations with those names are rejected.

- [ ] **Step 1: Add positive parser fixtures.**

  The positive fixture must contain an explicit task creation, await, and
  cancel with ordinary functions; it must not declare `async foo(...) -> T`.

- [ ] **Step 2: Add the negative intrinsic-name fixture.**

  Declare or import `async`, `await`, or `cancel` as ordinary functions and
  assert the reserved-intrinsic diagnostic for each name.

- [ ] **Step 3: Implement parsing without lowering.**

  Parse the three operations as distinct intrinsic nodes. Preserve source
  ranges so later affine diagnostics point at the operation, not its argument.

- [ ] **Step 4: Run the focused frontend tests.**

  ```bash
  ./bin/do check src/build/test/compile_ok/416_colorless_async_intrinsics.do
  ./bin/do check src/build/test/compile_err/416_colorless_async_intrinsic_redefinition.do
  ```

### Task 2: Resumable function analysis and Future consumption

**Files:**
- Modify: `src/build/sema_function_signatures.zig`
- Modify: `src/build/sema_function_calls.zig`
- Modify: `src/build/sema_control.zig`
- Modify: `src/build/codegen_model.zig`
- Create: `src/build/test/compile_err/417_colorless_async_future_reuse.do`
- Create: `src/build/test/compile_err/417_colorless_async_future_reuse.expect`
- Create: `src/build/test/compile_err/418_colorless_async_future_leak.do`
- Create: `src/build/test/compile_err/418_colorless_async_future_leak.expect`

**Interfaces:**
- Consumes: intrinsic AST nodes and existing Future affine checks.
- Produces: function metadata indicating `contains_await`, `resumable`, and
  direct-call capability; diagnostics for reuse, leak, and invalid context.

- [ ] **Step 1: Write red ownership fixtures.**

  Cover awaiting the same Future twice, returning with an unconsumed Future,
  canceling after await, and passing an owned resource into `@async` without a
  second owner.

- [ ] **Step 2: Mark resumable functions from body analysis.**

  Any reachable `@await` marks the containing function resumable. Ordinary
  declaration syntax remains valid during migration but does not suppress this
  analysis.

- [ ] **Step 3: Implement affine Future state transitions.**

  Track `live -> awaited` and `live -> canceled`; reject every other second
  transition and reject a live handle at scope exit.

- [ ] **Step 4: Run focused sema tests.**

  ```bash
  cd src && zig test build/sema_function_calls.zig
  ./src/build/test/run_tests.sh
  ```

### Task 3: Implicit root-task bridge

**Files:**
- Create: `src/build/codegen_task_bridge.zig`
- Modify: `src/build/codegen_emit_call.zig`
- Modify: `src/build/codegen_body.zig`
- Modify: `src/build/codegen_emit_control.zig`
- Test: `src/build/test/compile_ok/419_colorless_async_sync_call.do`
- Test: `src/build/test/compile_ok/420_colorless_async_task_call.do`

**Interfaces:**
- Consumes: resumable function metadata and Future ownership plans.
- Produces: a direct synchronous call path that allocates a compiler-owned
  root frame, drives it to terminal completion, and returns the declared value.

- [ ] **Step 1: Write the direct-call and explicit-task fixtures.**

  The first fixture calls a function containing `@await` directly from a
  synchronous root. The second calls the same function through
  `Future<T> = @async(call)` and then `@await`s it. Both must return the same
  value and cleanup counts.

- [ ] **Step 2: Implement root-frame creation and drive entry.**

  The bridge must be compiler-owned, invisible in the Do type system, and
  release the root frame on success, error, and cancellation. A direct call
  must not leak a user-visible Future.

- [ ] **Step 3: Reuse the task-context call path.**

  When the caller is already resumable, emit a child frame/call edge that
  suspends the current task at `@await` instead of nesting a blocking root
  driver.

- [ ] **Step 4: Run the two generated WAT checks.**

  ```bash
  ./bin/do build src/build/test/compile_ok/419_colorless_async_sync_call.do -o /tmp/colorless-sync.wat
  ./bin/do build src/build/test/compile_ok/420_colorless_async_task_call.do -o /tmp/colorless-task.wat
  ```

### Task 4: Canonical cancellation lowering

**Files:**
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/codegen_component_async_plan.zig`
- Modify: `src/build/codegen_ownership.zig`
- Test: `examples/p3-runtime/test_do_resource_cancellation_shape.sh`
- Test: `examples/p3-runtime/test_rust_resource_cancellation_shape.sh`

**Interfaces:**
- Consumes: `@cancel` affine state and root/task frame plans.
- Produces: exactly-once cancel request, terminal wait, frame/resource drop,
  and `task-return` behavior for the existing registered descriptors.

- [ ] **Step 1: Add positive and negative cancellation cases.**

  Cover pending cancel, already-ready cancel, cancel-after-terminal rejection,
  duplicate cancel rejection, and empty `ResourceTable` after cleanup.

- [ ] **Step 2: Lower `@cancel` through the existing component ABI.**

  Preserve `subtask.cancel -> subtask.drop -> task-return` for the registered
  shape. Do not add rollback, operation IDs, or a `Cancelled` result arm.

- [ ] **Step 3: Run the generated and hand-authored runtime gates.**

  ```bash
  bash examples/p3-runtime/test_do_resource_cancellation_shape.sh
  bash examples/p3-runtime/test_rust_resource_cancellation_shape.sh
  ```

### Task 5: WIT async metadata without source async declarations

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/codegen_host_imports.zig`
- Modify: `src/build/sema_imports.zig`
- Modify: `src/build/codegen_wasi_registry.zig`
- Test: existing private async WIT fixtures and `examples/p3-runtime/test_do_async_resource_result.sh`

**Interfaces:**
- Consumes: WIT `async func` descriptors and generated binding metadata from
  `do wit bind`, including the resolved package/world/member identity.
- Produces: async boundary metadata independent of `async foo(...) -> T` source
  declarations, with the same Future/result ABI and explicit rejection of
  mismatched synchronous signatures.

- [ ] **Step 1: Add manifest tests for async metadata.**

  Assert that the `do wit bind` manifest carries its future/stream operation
  facts, package/world/member identity, and that generated source declarations
  remain ordinary declarations.

- [ ] **Step 2: Update host admission checks.**

  Admit only the pinned async descriptor and reject a synchronous source shape
  that claims the same WIT member without the required Future boundary.

- [ ] **Step 3: Run the existing Component/Rust/Wasmtime result gate.**

  ```bash
  bash examples/p3-runtime/test_do_async_resource_result.sh
  bash examples/p3-runtime/test_rust_async_resource_result.sh
  ```

### Task 6: Deprecate and remove async function declarations

**Files:**
- Modify: `src/build/parser.zig`
- Modify: `src/build/sema_function_signatures.zig`
- Modify: `doc/grammar.peg`
- Modify: `doc/spec_rules.md`
- Modify: `doc/async-design.md`
- Modify: `doc/start_here.md`
- Test: all existing async declaration fixtures, then new negative fixtures

**Interfaces:**
- Consumes: the intrinsic-based lowering and WIT metadata from Tasks 1-5.
- Produces: a migration diagnostic for `async foo(...) -> T`, followed by
  grammar removal only after all source fixtures use `@async/@await/@cancel`.

- [ ] **Step 1: Migrate fixtures and generated bindings.**

  Replace task creation/await/cancel operations with the canonical intrinsic
  forms; do not change the measured WIT ABI.

- [ ] **Step 2: Add the deprecation diagnostic.**

  Existing declarations compile only in migration mode and report the exact
  replacement form. Normal builds reject the declaration after the migration
  gate is green.

- [ ] **Step 3: Remove the old grammar production.**

  Delete only the declaration production and its compatibility path; preserve
  ordinary `async` as a non-keyword identifier only if the final reserved-name
  policy permits it.

### Task 7: Full verification and phase closeout

**Files:**
- Modify only with observed evidence: `doc/pending_blocked.md`, `doc/roadmap_status.md`, `doc/master_plan.md`, `CHANGELOG.md`
- Test: complete compiler, Component, Rust/Wasmtime, and ReleaseSmall matrix

**Interfaces:**
- Consumes: all prior task gates.
- Produces: a verified decision about the default path and a residual-risk list
  for generic WIT/Component expansion.

- [ ] **Step 1: Run the complete matrix.**

  ```bash
  cd src && zig test main.zig
  cd ../
  ./src/build/test/run_tests.sh
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  git diff --check
  ```

- [ ] **Step 2: Verify all existing bounded runtime gates.**

  The variant, resource Result, HTTP payload, stream, filesystem, and socket
  gates must retain their exact poll/drop/resource-table results.

- [ ] **Step 3: Update the roadmap and stop before public ownership syntax.**

  A green colorless async core does not authorize public `own<T>`, `borrow<T>`,
  `ref<T>`, arbitrary producer expressions, or a complete WASI claim.
