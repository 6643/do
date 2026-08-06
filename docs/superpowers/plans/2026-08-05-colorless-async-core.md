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
- `async name(...) -> T` is deprecated and must not gain new capability; normal
  compilation reports `DeprecatedAsyncFunctionDecl` and does not register the
  declaration as a function.
- A normal Do call never creates a `Future<T>` implicitly: `Future<T> = @async(call)`
  is required. The only direct `Future<T> = call` exception is a pinned WIT
  `async func` binding whose generated metadata declares the future effect.
- `Future<T>` remains the task handle; do not add public `Task<T>` in this phase.
- Direct synchronous calls to resumable functions use an implicit compiler-owned root task.
- A Future is affine and must be consumed exactly once by `@await` or `@cancel`.
- Cancellation does not roll back external side effects.
- Do not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax.
- Preserve current bounded WIT descriptors and their Rust/Wasmtime cleanup gates.
- Consume WIT async/future/stream/resource facts only from the pinned
  `do wit bind` manifest.
- Validate generated metadata explicitly with
  `do wit check <wit-input> --world <world> --manifest <manifest.json>` before
  using a generated binding; reject hash, identity, signature-effect, and
  schema mismatches.

---

### Task 1: Parser and intrinsic recognition

**Files:**
- Modify: `src/build/parser.zig`
- Modify: `src/build/sema_async.zig`
- Create: `src/build/test/check/416_colorless_async_intrinsics.do`
- Create: `src/build/test/compile_err/416_colorless_async_intrinsic_redefinition.do`
- Create: `src/build/test/compile_err/416_colorless_async_intrinsic_redefinition.expect`
- Create: `src/build/test/compile_err/416_colorless_async_intrinsic_redefinition_await.do`
- Create: `src/build/test/compile_err/416_colorless_async_intrinsic_redefinition_await.expect`
- Create: `src/build/test/compile_err/416_colorless_async_intrinsic_redefinition_cancel.do`
- Create: `src/build/test/compile_err/416_colorless_async_intrinsic_redefinition_cancel.expect`

**Interfaces:**
- Consumes: existing `@` intrinsic token handling and Future type syntax.
- Produces: parsed forms for `@async(call)`, `@await(task)`, and `@cancel(task)`;
  ordinary user declarations with those names are rejected.

- [x] **Step 1: Add positive parser fixtures.**

  The positive check fixture must contain an explicit task creation, await, and
  cancel with ordinary functions; it must not declare `async foo(...) -> T`.
  `do check` must pass, while `do build` must retain
  `AsyncLoweringUnavailable` until the frame/lowering tasks are complete.

- [x] **Step 2: Add the negative intrinsic-name fixture.**

  Declare `async`, `await`, and `cancel` as ordinary functions and assert the
  existing reserved-function-name diagnostic for each name.

- [x] **Step 3: Implement parsing without lowering.**

  Parse the three operations as intrinsic call identities in the existing
  expression node. Preserve source ranges so later affine diagnostics point at
  the operation, not its argument. Colorless bodies containing `@async` are
  admitted by the frontend; no frame or WAT lowering is added here.

- [x] **Step 4: Run the focused frontend tests.**

  ```bash
  ./bin/do check src/build/test/check/416_colorless_async_intrinsics.do
  ./bin/do check src/build/test/compile_err/416_colorless_async_intrinsic_redefinition.do
  ```

### Task 2: Resumable function analysis and Future consumption

**Files:**
- Modify: `src/build/parser.zig`
- Modify: `src/build/sema_async.zig`
- Modify: `src/build/codegen_collect_functions.zig`
- Modify: `src/build/codegen_model.zig`
- Create: `src/build/test/compile_err/417_colorless_async_future_reuse.do`
- Create: `src/build/test/compile_err/417_colorless_async_future_reuse.expect`
- Create: `src/build/test/compile_err/418_colorless_async_future_leak.do`
- Create: `src/build/test/compile_err/418_colorless_async_future_leak.expect`

**Interfaces:**
- Consumes: intrinsic AST nodes and existing Future affine checks.
- Produces: function metadata indicating `contains_await`, `resumable`, and
  direct-call capability; diagnostics for reuse, leak, and invalid context.

- [x] **Step 1: Write red ownership fixtures.**

  Cover awaiting the same Future twice, returning with an unconsumed Future,
  canceling after await, and passing an owned resource into `@async` without a
  second owner.

- [x] **Step 2: Mark resumable functions from body analysis.**

  Any reachable `@await` marks the containing function resumable. Ordinary
  declaration syntax is rejected before lowering and does not suppress this
  analysis.

- [x] **Step 3: Implement affine Future state transitions.**

  Track `live -> awaited` and `live -> canceled`; reject every other second
  transition and reject a live handle at scope exit.

- [x] **Step 4: Run focused sema tests.**

  ```bash
  cd src && zig test build/sema_function_calls.zig
  ./src/build/test/run_tests.sh
  ```

  The current regression result is `pass=1095 fail=0 skip=3`. The generic
  async lowering guard remains expected for unsupported descriptor shapes.

### Task 3: Implicit root-task bridge

**Files:**
- Create: `src/build/codegen_task_bridge.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Test: `src/build/test/compile_ok/419_colorless_async_sync_call.do`
- Test: `src/build/test/compile_ok/419_colorless_async_sync_call.expect`
- Test: `src/build/test/compile_ok/420_colorless_async_task_call.do`
- Test: `src/build/test/compile_ok/420_colorless_async_task_call.expect`
- Test: `src/build/test/compile_ok/421_colorless_async_task_context_call.do`
- Test: `src/build/test/compile_ok/421_colorless_async_task_context_call.expect`

**Interfaces:**
- Consumes: resumable function metadata and Future ownership plans.
- Produces: a direct synchronous call path that allocates a compiler-owned
  root frame, drives it to terminal completion, and returns the declared value.

- [x] **Step 1: Write the direct-call and explicit-task fixtures.**

  The first fixture calls a function containing `@await` directly from a
  synchronous root. The second calls the same function through
  `Future<T> = @async(call)` and then `@await`s it. Both must return the same
  value and cleanup counts. The accepted bounded shape is a zero-parameter
  child with one `Future<nil>` await and an `i32` literal result.

- [x] **Step 2: Implement root-frame creation and drive entry for the bounded shape.**

  `codegen_task_bridge.zig` is compiler-owned and invisible in the Do type
  system. It emits root/child frame allocation, explicit Future creation and
  consumption, terminal cleanup, and a direct call with no user-visible
  Future. Unsupported result, parameter, branch, and payload shapes continue
  to the existing async guard.

- [x] **Step 3: Reuse the task-context call path for the bounded child shape.**

  When the caller is already resumable, emit a child frame/call edge that
  suspends the current task at `@await` instead of nesting a blocking root
  driver. The bounded `task-context` fixture now emits a direct child call
  after the caller's own unit Future await. General resumable calls with
  payloads, branches, multiple await sites, and arbitrary arguments remain
  outside this slice.

- [x] **Step 4: Run the generated WAT checks.**

  ```bash
  ./bin/do build src/build/test/compile_ok/419_colorless_async_sync_call.do -o /tmp/colorless-sync.wat
  ./bin/do build src/build/test/compile_ok/420_colorless_async_task_call.do -o /tmp/colorless-task.wat
  ./bin/do build src/build/test/compile_ok/421_colorless_async_task_context_call.do -o /tmp/colorless-context.wat
  ```

  All three outputs pass `wasm-tools parse` and `wasmtime run`. The full
  regression matrix is `pass=1095 fail=0 skip=3`.

  This closes only the bounded bridge slice. Generic payloads, branches,
  multiple await sites, arbitrary arguments, and general task-context
  lowering remain outside the slice and continue to use the explicit
  unsupported-shape guard.

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

- [x] **Step 1: Add positive and negative cancellation cases.**

  Cover pending cancel, already-ready cancel, cancel-after-terminal rejection,
  duplicate cancel rejection, and empty `ResourceTable` after cleanup.

- [x] **Step 2: Lower `@cancel` through the existing component ABI.**

  Preserve `subtask.cancel -> subtask.drop -> task-return` for the registered
  shape. Do not add rollback, operation IDs, or a `Cancelled` result arm.

- [x] **Step 3: Run the generated and hand-authored runtime gates.**

  ```bash
  bash examples/p3-runtime/test_do_resource_cancellation_shape.sh
  bash examples/p3-runtime/test_rust_resource_cancellation_shape.sh
  ```

  The cancellation gates pass for pending and immediate-ready tasks, with
  exactly-once terminal cleanup and no rollback marker. The resource Result
  gate also reports `request consumed=1`, `pending future drops=1`, and
  `table-empty=true`; double-cancel, cancel-after-terminal, and implicit
  scope-drop remain negative boundaries.

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

- [x] **Step 1: Add manifest tests for async metadata.**

  Assert that the `do wit bind` manifest carries its future/stream operation
  facts, package/world/member identity, and that generated source declarations
  remain ordinary declarations. The WIT binding plan now provides a parser and
  binding-model validator; the remaining work here is compiler-side admission
  and the Component ABI gate.

- [x] **Step 2: Update host admission checks.**

  Admit only generated modules with a sibling manifest whose module hashes,
  member signatures, and async/future effects match. Reject missing manifests,
  module-content drift, and synchronous signatures that claim an async member.

- [x] **Step 3: Run the existing Component/Rust/Wasmtime result gate.**

  ```bash
  bash examples/p3-runtime/test_do_async_resource_result.sh
  bash examples/p3-runtime/test_rust_async_resource_result.sh
  ```

  The manifest and generated-binding probes pass, including module-content and
  WIT-effect drift rejection. Compiler-side sibling manifest discovery and
  host admission are covered by
  `examples/wit-bindgen-do/test_generated_async_manifest.sh`; no generated
  binding is silently admitted as synchronous.

### Task 6: Deprecate and remove async function declarations

**Files:**
- Modify: `src/build/parser.zig`
- Modify: `src/build/sema_function_signatures.zig`
- Modify: `doc/grammar.peg`
- Modify: `doc/spec_rules.md`
- Modify: `doc/async-design.md`
- Modify: `doc/start_here.md`
- Test: all existing async declaration fixtures, then new negative fixtures for
  legacy declarations and implicit ordinary-function Future creation

**Interfaces:**
- Consumes: the intrinsic-based lowering and WIT metadata from Tasks 1-5.
- Produces: a migration diagnostic for `async foo(...) -> T`, followed by
  grammar removal only after all source fixtures use `@async/@await/@cancel`.

- [x] **Step 1: Migrate fixtures and generated bindings.**

  Replace task creation/await/cancel operations with the canonical intrinsic
  forms; do not change the measured WIT ABI. For ordinary Do functions, every
  Future-producing call must be wrapped in `@async(call)`. Preserve direct calls
  only for generated WIT `async func` bindings whose manifest carries the
  future effect.

  Final audit: no production `.do` fixture uses the legacy declaration. The only
  remaining occurrences are the dedicated negative fixtures
  `compile_err/421_generic_async_function_decl.do` and
  `check/428_legacy_async_declaration.do`, which lock the diagnostic contract.
  Ordinary functions use `@async/@await/@cancel`; registered WIT async bindings
  remain the documented direct `Future<T> = call(...)` exception.

- [x] **Step 2: Add the deprecation diagnostic.**

  Legacy declarations are recognized only to report the exact replacement form;
  they are not admitted as parser functions or lowered. Normal Do calls that
  assign an ordinary function result to `Future<T>` report the explicit
  `@async(call)` replacement. A direct
  `Future<T> = call` remains accepted only when the pinned WIT manifest marks
  `call` as an async host binding. Normal builds reject the declaration after
  the migration gate is green.

- [x] **Step 3: Remove the old grammar production.**

  The grammar no longer admits `AsyncModifier`, and the hand-written parser no
  longer registers `async name(...)` as a function. The semantic diagnostic scan
  remains so users receive a targeted migration error instead of a generic parse
  failure. `async` remains reserved for the `@async(...)` intrinsic spelling.

### Task 7: Full verification and phase closeout

**Files:**
- Modify only with observed evidence: `doc/pending_blocked.md`, `doc/roadmap_status.md`, `doc/master_plan.md`, `CHANGELOG.md`
- Test: complete compiler, Component, Rust/Wasmtime, and ReleaseSmall matrix

**Interfaces:**
- Consumes: all prior task gates.
- Produces: a verified decision about the default path and a residual-risk list
  for generic WIT/Component expansion.

- [x] **Step 1: Run the complete matrix.**

  ```bash
  cd src && zig test main.zig
  cd ../
  ./src/build/test/run_tests.sh
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  git diff --check
  ```

  Refreshed on 2026-08-06: default `pass=1095 fail=0 skip=3`, Wasm
  `pass=1097 fail=0 skip=3` with wasm smoke `6/6`, and ReleaseSmall smoke
  passed.

- [x] **Step 2: Verify all existing bounded runtime gates.**

  `bash examples/p3-runtime/test_task8_step3_baseline.sh` passed all seven
  registered gates: cancel-wait-for, scalar/resource Result, stream
  reader/writer, filesystem, and TCP/UDP sockets. The variant/resource-stream,
  HTTP payload/cancellation, and nested-resource gates also remained green.

- [x] **Step 3: Update the roadmap and stop before public ownership syntax.**

  A green colorless async core does not authorize public `own<T>`, `borrow<T>`,
  `ref<T>`, arbitrary producer expressions, or a complete WASI claim.
