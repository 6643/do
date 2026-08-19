# Bounded Async-Call Internal Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a private descriptor-only frame/lifecycle facts layer for the five already admitted bounded async-call shapes without changing generated behavior, public syntax, admission boundaries, or default dispatch.

**Architecture:** `codegen_component_async_shape.zig` owns immutable layout and cleanup facts plus fail-closed validation. The existing child, inline, and host planners retain independent registry/topology admission, and the existing WAT templates retain their mode-specific control flow. Differential tests pin the current WAT/WIT bytes, marker order, frame offsets, rejection behavior, and runtime terminal cleanup before any future extraction of WAT fragments.

**Tech Stack:** Zig 0.16.0, existing `do` compiler modules, pinned `wasm-tools` 1.255.0 and legacy async assembler 1.254.0, Rust 1.97.1, Wasmtime 47.0.2, Bash gates, and `src/build/test/run_tests.sh`.

## Global Constraints

- Do not add generic `Future<T>` lowering, arbitrary producer expressions, payload/resource/list/stream support, or public `own<T>`/`borrow<T>`/`ref<T>` syntax.
- Do not change `@async`, `@await`, `@cancel`, ordinary colorless function semantics, default dispatch, CLI flags, WIT declarations, registry rows, import names, or Component target selection.
- Keep `codegen_component_async_call_plan.zig` and `codegen_component_async_host_arg_plan.zig` as separate admission authorities with their existing stable rejection errors.
- The new shape module is private, immutable, allocator-free after construction, and must not import `codegen_pipeline` or a registry/parser module.
- Preserve current generated output. A byte/hash, marker-order, frame-offset, WIT/hash, runtime terminal, or rejection change is a NO-GO unless it is proven to be reviewed non-ABI text only; leave the current templates as the rollback implementation.
- Every implementation task ends with its focused Zig or shell verification before the task commit.

---

### Task 1: Add validated bounded shape facts

**Files:**
- Create: `src/build/codegen_component_async_shape.zig`
- Create: `src/build/codegen_component_async_shape_test.zig`
- Modify: `src/main.zig:80-106` test import list

**Interfaces:**
- Consumes: no parser, registry, or emitter state.
- Produces: `BoundedAsyncMode`, `BoundedFrameLayout`, `BoundedCleanupAction`, `BoundedCleanupContract`, `BoundedAsyncShape`, `validate`, `child_shape`, `inline_shape`, and `host_scalar_shape` for planner adapters.

- [x] **Step 1: Define the immutable shape contract.**

  Add these public types and function signatures:

  ```zig
  pub const BoundedAsyncMode = enum { child, inline_call, host_scalar };

  pub const BoundedFrameLayout = struct {
      size: u32,
      alignment: u32,
      waitable_set_offset: u32,
      active_subtask_offset: u32,
      phase_offset: u32,
      u32_argument_offset: ?u32,
  };

  pub const BoundedCleanupAction = enum {
      cancel_active_subtask,
      drop_active_subtask_if_owned,
      drop_waitable_set,
      clear_root_context,
      free_root_frame,
      create_next_waitable_set,
      start_next_child,
      root_task_return,
      root_task_cancel,
  };

  pub const BoundedCleanupContract = struct {
      normal: []const BoundedCleanupAction,
      phase_transition: []const BoundedCleanupAction,
      cancelled: []const BoundedCleanupAction,
  };

  pub const BoundedAsyncShape = struct {
      mode: BoundedAsyncMode,
      frame: BoundedFrameLayout,
      cleanup: BoundedCleanupContract,

      pub fn validate(self: BoundedAsyncShape) !void;
  };

  pub fn child_shape(with_u32_argument: bool) !BoundedAsyncShape;
  pub fn inline_shape(with_u32_argument: bool) !BoundedAsyncShape;
  pub fn host_scalar_shape() !BoundedAsyncShape;
  ```

  Keep all action arrays in module-owned immutable constants. The constructor
  functions return a validated value and never allocate.

- [x] **Step 2: Implement layout validation.**

  `validate` must reject with stable errors `InvalidFrameAlignment`,
  `InvalidFrameSlot`, `InvalidFrameSize`, and `InvalidCleanupOrder` when:

  - alignment is not `4`;
  - common offsets are not `0`, `4`, and `8`, or an optional argument slot is
    outside `size`;
  - a scalar shape is not exactly 20 bytes or a unit shape is not exactly 16;
  - any offset is not 4-byte aligned;
  - normal/cancelled terminal actions are missing, duplicated, or ordered
    before frame cleanup;
  - `cancel_active_subtask` is not immediately before the permitted drop path
    in cancellation cleanup;
  - `phase_transition` contains a terminal action, a cancellation action, or a phase
    transition for a non-inline mode.

  Permit the child shape's empty `cancelled` sequence because its current
  template has no cancellation branch and planner admission must remain
  unchanged. Require exactly one `root_task_return` in each non-empty normal
  sequence and exactly one `root_task_cancel` in inline/host cancellation
  sequences.

- [x] **Step 3: Add five positive and boundary unit tests.**

  Add tests in `codegen_component_async_shape_test.zig` for child unit, child
  scalar, inline unit, inline scalar, and host scalar. Assert every offset,
  size, alignment, mode, and action sequence. Add negative tests for an
  argument at `+12` in a 16-byte frame, 8-byte alignment, a non-common offset,
    duplicate terminal action, terminal action in `phase_transition`, `start_next_child` in
  cancellation, and a non-inline resume sequence.

- [x] **Step 4: Make the module part of the standard Zig test graph.**

  Add `_ = @import("build/codegen_component_async_shape_test.zig");` to the
  existing `test {}` block in `src/main.zig`. The test module imports the
  production shape module. Do not import the shape module into production
  dispatch yet; Task 2 performs the first plan-only integration.

- [x] **Step 5: Run focused verification and commit.**

  ```bash
  cd src && zig test main.zig
  cd ..
  git diff --check
  git add src/build/codegen_component_async_shape.zig \
    src/build/codegen_component_async_shape_test.zig src/main.zig
  git commit -m "Add bounded async-call shape facts"
  ```

  Expected: shape tests pass and no compiler output changes because no emitter
  imports the new module.

### Task 2: Attach shape facts to independent planners

**Files:**
- Modify: `src/build/codegen_component_async_call_plan.zig`
- Modify: `src/build/codegen_component_async_host_arg_plan.zig`
- Modify: `src/build/codegen_component_async_call_plan_test.zig`
- Modify: `src/build/codegen_component_async_host_arg_plan_test.zig`

**Interfaces:**
- Consumes: validated constructors from `codegen_component_async_shape.zig`.
- Produces: a value field named `shape: BoundedAsyncShape` on both
  `GuestAsyncCallPlan` and `AsyncHostScalarArgPlan`; all existing source facts
  and rejection errors remain unchanged.

- [x] **Step 1: Add immutable shape fields without changing admission.**

  Import the shape module in both planners and add the value field. Do not move
  or merge `find_host_binding`, `helper_body_is_exact`, `root_body_is_exact`,
  token counting, registry checks, or rejection classification.

- [x] **Step 2: Select the exact shape after existing predicates pass.**

  In `codegen_component_async_call_plan.zig`, construct the shape only after
  the current `if (...) return error.UnsupportedP3AsyncCallComponent` guard:

  ```zig
  const shape = if (inline_helper_call)
      try bounded_shape.inline_shape(inline_argument_values != null)
  else
      try bounded_shape.child_shape(scalar_value != null);
  ```

  Store it in the returned plan. In the host planner, call
  `try bounded_shape.host_scalar_shape()` only after `inspect_source` returns
  accepted facts. A failed shape invariant must map to the same existing
  `UnsupportedP3Async...` error at the planner boundary; it must not widen
  admission or leak a new public diagnostic.

- [x] **Step 3: Extend planner tests with layout assertions.**

  Keep all current positives and negatives. Add assertions for:

  - check fixture `441_async_call_component.do`: `mode == .child`, size `16`,
    argument slot `null`;
  - compile fixture `466_async_call_scalar_argument_component.do`: `.child`,
    size `20`, argument slot `12`;
  - `examples/p3-runtime/async-call-component.do`: `.inline`, size `16`;
  - compile fixture `477_async_call_inline_scalar_argument_component.do`:
    `.inline`, size `20`, argument slot `12`;
  - compile fixture `490_async_host_scalar_argument_component.do`:
    `.host_scalar`, size `20`, argument slot `12`.

  Assert that every accepted plan's `shape.validate()` succeeds and every
  existing negative still returns its original error/rejection reason.

- [x] **Step 4: Run focused planner tests and commit.**

  ```bash
  cd src
  zig test build/codegen_component_async_call_plan_test.zig
  zig test build/codegen_component_async_host_arg_plan_test.zig
  cd ..
  git diff --check
  git add src/build/codegen_component_async_call_plan.zig \
    src/build/codegen_component_async_host_arg_plan.zig \
    src/build/codegen_component_async_call_plan_test.zig \
    src/build/codegen_component_async_host_arg_plan_test.zig
  git commit -m "Attach bounded shape facts to async planners"
  ```

  Expected: all existing planner behavior remains green; no WAT is changed in
  this task because emitters still ignore the new field.

### Task 3: Validate shape facts at emitters and pin differential output

**Files:**
- Modify: `src/build/codegen_component_async_call.zig`
- Modify: `src/build/codegen_component_async_host_arg.zig`
- Modify: `src/build/codegen_component_async_call_test.zig`
- Modify: `src/build/codegen_component_async_host_arg_test.zig`
- Create: `src/build/codegen_component_async_differential_test.zig`
- Modify: `src/main.zig:80-106` test import list

**Interfaces:**
- Consumes: the immutable `shape` fields produced by Task 2.
- Produces: emitter-side `shape.validate()` guards and byte/marker/hash
  differential tests without new WAT fragments or output markers.

- [x] **Step 1: Add emitter-side fail-closed validation.**

  At the first line of each `emit_component_wat`, call
  `try plan.shape.validate();` before template selection or allocation. Keep
  all existing substitutions and template constants byte-identical. Do not add
  shape metadata comments to generated WAT in this task.

- [x] **Step 2: Add direct emitter assertions.**

  Extend the existing emitter tests to assert the plan shape mode and frame
  facts before checking current markers. Preserve the existing checks for no
  helper `task-return`/`async-lift` endpoint and inline event-6 cancellation.

- [x] **Step 3: Add hash and marker-order differential tests.**

  Create a test module that tokenizes the five positive sources, emits WAT/WIT,
  computes SHA-256 with `std.crypto.hash.sha2.Sha256`, and compares these pinned
  values captured from the current emitter:

  | Shape | WAT SHA-256 | WIT SHA-256 |
  | --- | --- | --- |
  | child unit (`check/441`) | `bec944caece221821f43a79041e2989281f9f9b90d59547f9348ef641e1b2e03` | `ecf47e1e33b3a0d14761a1341f3b749f4ba072051c018083db2d5cda356c101f` |
  | child scalar (`compile_ok/466`) | `7402916ce09060ca63e792498dc1523923b6a1545004d91c61f1a037496f2fc1` | `ecf47e1e33b3a0d14761a1341f3b749f4ba072051c018083db2d5cda356c101f` |
  | inline unit (`examples/p3-runtime/async-call-component.do`) | `0e362d90a30c38de5e5900783b7474ddac05292f50c402a20786c0a940598dcc` | `ecf47e1e33b3a0d14761a1341f3b749f4ba072051c018083db2d5cda356c101f` |
  | inline scalar (`compile_ok/477`) | `7edf6a66095c3c24b8c5440ebcad5a7f5dfcc5fea3c943a8e4d28453bb96fe83` | `ecf47e1e33b3a0d14761a1341f3b749f4ba072051c018083db2d5cda356c101f` |
  | host scalar (`compile_ok/490`) | `e9e2330a75430b569b538d15d676d92492c952f89c5cc135a38343670da01553` | `b9f5f8355e87231317ec05cccf692ee465c6f339bd509640aedc196e58f81e61` |

  Extract only `guest-*` marker names in source order and assert these exact
  existing sequences, including repeated markers, without sorting:

  ```text
  child unit: [guest-async-parent-resume], [guest-async-child-drop],
              [guest-async-root-terminal], [guest-async-child]
  child scalar: [guest-async-parent-resume], [guest-async-arg-load],
                [guest-async-child-drop], [guest-async-root-terminal],
                [guest-async-child], [guest-async-arg-store]
  inline unit: [guest-async-parent-resume], [guest-async-child-drop],
               [guest-async-root-terminal], [guest-async-root-cancel],
               [guest-async-cancel-child], [guest-async-child],
               [guest-inline-resume], [guest-inline-helper]
  inline scalar: [guest-async-parent-resume], [guest-async-child-drop],
                 [guest-async-root-terminal], [guest-async-root-cancel],
                 [guest-async-cancel-child], [guest-async-child],
                 [guest-async-arg-store], [guest-async-arg-load],
                 [guest-inline-resume], [guest-inline-arg-load],
                 [guest-inline-helper], [guest-inline-arg-store]
  host scalar: [guest-async-child-drop], [guest-async-child-drop],
               [guest-async-waitable-drop], [guest-async-context-clear],
               [guest-async-frame-free], [guest-async-parent-resume],
               [guest-async-arg-load], [guest-async-arg-store],
               [guest-async-host-arg], [guest-async-parent-resume]
  ```

  The helper must also assert no `[task-return]helper` or
  `[async-lift]helper` occurs in any generated WAT.

- [x] **Step 4: Run focused differential tests and commit.**

  ```bash
  cd src
  zig test build/codegen_component_async_differential_test.zig
  zig test build/codegen_component_async_call_test.zig
  zig test build/codegen_component_async_host_arg_test.zig
  cd ..
  git diff --check
  git add src/build/codegen_component_async_call.zig \
    src/build/codegen_component_async_host_arg.zig \
    src/build/codegen_component_async_call_test.zig \
    src/build/codegen_component_async_host_arg_test.zig \
    src/build/codegen_component_async_differential_test.zig src/main.zig
  git commit -m "Gate bounded async emitters with shape diffs"
  ```

  Expected: all five WAT hashes, both WIT hashes, marker ordering, frame
  offsets, and helper endpoint rejection remain unchanged.

### Task 4: Run Component and Rust/Wasmtime promotion gates

**Files:**
- Modify: `doc/roadmap_status.md` only if every gate is green
- Modify: `doc/pending_blocked.md` only to record the bounded internal reuse
  result and preserve still-pending generic shapes
- Modify: `examples/p3-runtime/README.md` only if the existing bounded async
  gate list needs the new differential test named

**Interfaces:**
- Consumes: the unchanged WAT/WIT output and the existing pinned runners.
- Produces: runtime evidence for ready, pending, cancel-inline, cancel-child,
  and host scalar cleanup; no new target or public language behavior.

- [x] **Step 1: Run current and legacy Component gates.**

  ```bash
  bash examples/p3-runtime/test_do_async_call_component.sh
  bash examples/p3-runtime/test_do_async_call_scalar_argument.sh
  bash examples/p3-runtime/test_do_async_call_inline_scalar_argument.sh \
    /tmp/async-call-inline-scalar-argument.component.wasm
  bash examples/p3-runtime/test_do_async_host_scalar_argument.sh
  ```

  Expected: both pinned `wasm-tools` routes assemble and validate, the generic
  WIT snapshot remains byte-identical, frame slots remain `+0/+4/+8/+12`, and
  no helper endpoint is emitted.

- [x] **Step 2: Run Rust/Wasmtime runtime matrices.**

  ```bash
  bash examples/p3-runtime/test_rust_async_call_component.sh \
    /tmp/async-call-inline-scalar-argument.component.wasm
  bash examples/p3-runtime/test_rust_async_call_scalar_argument.sh \
    /tmp/async-call-scalar-argument.component.wasm
  bash examples/p3-runtime/test_rust_async_host_scalar_argument.sh
  ```

  Expected: ready/pending/cancel rows pass, active subtasks are cancelled or
  dropped exactly once, no helper terminal endpoint is observed, and every
  terminal row leaves an empty `ResourceTable`.

- [x] **Step 3: Keep the rejection matrix closed.**

  Run the focused compile-error rows `467-469`, `475-481`, and `490-497` plus
  the existing `check/441`, `check/477`, and `check/490` entries through the
  standard harness. Expected: all existing errors and skips remain unchanged;
  no generic payload/resource/list/stream or ownership shape becomes accepted.

- [x] **Step 4: Run the full regression and release smoke.**

  ```bash
  cd src && zig test main.zig
  cd ..
  ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  git diff --check
  ```

  Expected summary: `fail=0`, the existing skip count is unchanged, and release
  smoke passes without a new default-target artifact.

- [x] **Step 5: Update status and commit only after green gates.**

  Record the exact command output, five WAT hashes, two WIT hashes, and runtime
  cleanup observations in the current roadmap/pending-blocked documents. State
  that this is private bounded internal reuse; leave generic async-call,
  arbitrary producers, payload/resource/list/stream futures, borrowed values,
  and public ownership syntax pending. Then run:

  ```bash
  git add doc/roadmap_status.md doc/pending_blocked.md examples/p3-runtime/README.md
  git commit -m "Close bounded async-call consolidation gate"
  ```

  If any gate fails, do not update status as complete. Preserve the failure,
  remove only the new shape adapter if necessary, and retain the pre-M2
  templates as the working implementation.

## Rollback

The rollback boundary is the emitter call site. Remove the `shape.validate()`
guard and stop consuming `plan.shape`; the original templates and admission
plans remain intact. Do not revert unrelated user changes or reset the branch.
The shape module and tests may remain as documented evidence only if they do
not alter production imports; otherwise remove them in the same focused revert.
