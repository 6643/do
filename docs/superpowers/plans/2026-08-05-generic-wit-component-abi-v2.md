# Generic WIT/Component ABI v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** introduce the internal generic WIT/Component ABI planning layer while preserving the current v1 compiler and all admitted bounded runtime gates.

**Architecture:** Keep current descriptor-specific emitters as the v1 compatibility path. Add pure ABI, layout, ownership, and async plan modules; migrate one existing private descriptor only after the new plan reproduces its measured WAT and cleanup behavior.

**Tech Stack:** Zig `0.16.0`, Do compiler, WIT/Core WAT, pinned `wasm-tools 1.254.0`, Rust `1.97.1`, Wasmtime `47.0.2`, existing Bash regression harness.

## Global Constraints

- Preserve the current v1 default lowering and regression baseline (`pass=1070 fail=0 skip=3`, WASM `pass=1072 fail=0 skip=3`, `zig test main.zig` `243/243`).
- Do not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax.
- Do not silently convert `borrow<T>` to `own<T>` or accept a WIT shape rejected by pinned `wasm-tools`.
- Keep all registry entries descriptor-driven until a generic plan reproduces their measured facts.
- Cancellation ends tasks and releases resources; it never rolls back external side effects.
- Use local deterministic fixtures only; do not add external-network tests.
- Preserve unrelated dirty worktree changes; do not stage, commit, reset, clean, or push during task execution.

---

### Task 1: Freeze the capability and baseline matrix

**Files:**
- Create: `docs/superpowers/specs/2026-08-05-generic-wit-component-abi-v2-capability-matrix.md`
- Create: `examples/p3-runtime/test_borrow_capability_matrix.sh`
- Modify: `doc/pending_blocked.md`
- Test: existing `examples/p3-runtime/test_do_borrowed_resource_rejection.sh`, `examples/p3-runtime/test_do_resource_probe_lowering.sh`, and the current full regression commands

**Interfaces:**
- Consumes: the pinned WIT probes and current v1 baseline.
- Produces: a machine-checked matrix separating direct borrow, borrowed record,
  borrowed variant, borrowed list, borrowed stream, and borrowed future shapes.

- [ ] **Step 1: Add the matrix probe definitions.**

  Define one minimal WIT world per shape. The direct case must contain
  `borrow-value: func(ticket: borrow<ticket>) -> u32`; the stream case must
  contain `stream<record { ticket: borrow<ticket> }>` and preserve the current
  expected rejection string. Do not add compiler registry entries.

- [ ] **Step 2: Write the failing/negative assertions first.**

  The script must assert that the direct function case assembles and that the
  nested stream-record case fails with:

  ```text
  contains a `borrow<T>` which is not supported
  ```

  It must print the installed `wasm-tools --version` and fail if it is not
  `1.254.0`.

- [ ] **Step 3: Run the probe and record the result.**

  ```bash
  bash examples/p3-runtime/test_borrow_capability_matrix.sh
  bash examples/p3-runtime/test_do_borrowed_resource_rejection.sh
  bash examples/p3-runtime/test_do_resource_probe_lowering.sh
  ```

  Expected: direct borrow is green, nested borrowed stream is explicitly
  rejected, and no existing descriptor changes.

- [ ] **Step 4: Record the stop condition.**

  Update `doc/pending_blocked.md` only with observed tool output and the exact
  recovery condition: a toolchain upgrade or a new canonical WIT shape must be
  probed before nested borrowed values can enter the registry.

- [ ] **Step 5: Verify the unchanged baseline.**

  ```bash
  cd src && zig test main.zig
  cd ../
  ./src/build/test/run_tests.sh
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  ```

  Expected: `243/243`, `pass=1070 fail=0 skip=3`, and `pass=1072 fail=0 skip=3`.

### Task 2: Add the pure ABI type model

**Files:**
- Create: `src/build/wit_abi_types.zig`
- Test: `src/build/wit_abi_types.zig`
- Modify: `src/build/codegen_api.zig` only if the test import is required by the existing Zig test root

**Interfaces:**
- Consumes: no codegen or registry modules.
- Produces: immutable `AbiType`, `AbiTypeKind`, `ResourceMode`, and validated
  recursive shape equality used by later layout and ownership plans.

- [ ] **Step 1: Write unit tests for each logical kind.**

  Cover scalar, tuple, record, option, result, variant, list, text, and
  resource values. Include recursive equality, duplicate variant tag rejection,
  and invalid empty result/variant cases.

- [ ] **Step 2: Implement the smallest pure data model.**

  Keep the module independent of `codegen_pipeline`, WAT emitters, sema state,
  and registry descriptors. Use explicit tagged unions and owned slices with
  validation at construction boundaries.

- [ ] **Step 3: Run the focused test.**

  ```bash
  cd src && zig test build/wit_abi_types.zig
  ```

  Expected: all new tests pass; no existing compiler test is changed.

### Task 3: Add measured canonical layout plans

**Files:**
- Create: `src/build/wit_abi_layout.zig`
- Test: `src/build/wit_abi_layout.zig`
- Inspect: `src/build/p3_async_manifest.zig`, `src/build/codegen_union_layout.zig`, `src/build/type_name.zig`

**Interfaces:**
- Consumes: `AbiType` and explicit measured descriptor facts.
- Produces: immutable `LayoutPlan` with tag/payload offsets, size,
  alignment, indirect allocation/free actions, and validation errors.

- [ ] **Step 1: Write tests from existing measured fixtures.**

  Reproduce the current `variant-resource-stream` facts (`tag=0`, payload `4`,
  size `8`, alignment `4`) and the registered HTTP payload string facts.
  Add negative tests for duplicate tags, misalignment, offset overflow, and
  missing payload metadata.

- [ ] **Step 2: Implement layout validation without emitting WAT.**

  The plan must reject unmeasured layouts instead of deriving a layout from
  coincidental field sizes. It must preserve nested type boundaries.

- [ ] **Step 3: Run focused and existing layout tests.**

  ```bash
  cd src && zig test build/wit_abi_layout.zig
  cd src && zig test build/p3_async_manifest.zig
  ```

### Task 4: Add ownership plans for own/direct borrow

**Files:**
- Create: `src/build/wit_abi_ownership.zig`
- Test: `src/build/wit_abi_ownership.zig`
- Inspect: `src/build/codegen_ownership.zig`, `src/build/codegen_model.zig`, `doc/memory.md`

**Interfaces:**
- Consumes: `AbiType`, `LayoutPlan`, and a validated call/scope graph.
- Produces: `OwnershipPlan` actions for move, direct-call borrow, clear,
  release, and early-drop; rejects duplicate release and resource escape.

- [ ] **Step 1: Write move/borrow/drop tests.**

  Cover own transfer, direct borrow retaining the owner, branch join agreement,
  early cleanup, duplicate release, and a borrowed value escaping the call.

- [ ] **Step 2: Implement explicit ownership actions.**

  Each owned resource must have exactly one release authority. A borrow action
  may read an owner only during the call region and must not create a second
  drop. Nested borrowed record/stream shapes remain rejected by capability,
  not silently rewritten.

- [ ] **Step 3: Run focused ownership tests and v1 resource gates.**

  ```bash
  cd src && zig test build/wit_abi_ownership.zig
  bash examples/p3-runtime/test_do_resource_probe_lowering.sh
  bash examples/p3-runtime/test_rust_resource_probe.sh
  ```

### Task 5: Add async endpoint plans

**Files:**
- Create: `src/build/wit_abi_async.zig`
- Test: `src/build/wit_abi_async.zig`
- Inspect: `src/build/codegen_component_async_plan.zig`, `src/build/codegen_component_stream_writer.zig`

**Interfaces:**
- Consumes: `AbiType`, `LayoutPlan`, and `OwnershipPlan`.
- Produces: `AsyncPlan` for poll, pending, ready, error, cancellation,
  endpoint drop, and terminal cleanup transitions.

- [ ] **Step 1: Write the existing terminal matrix as plan tests.**

  Cover pending-to-ready, immediate ready, completion error, explicit cancel,
  early drop, and exactly-once stream/future/resource cleanup.

- [ ] **Step 2: Implement transition validation.**

  Reject polling after terminal consumption, double cancellation, dropping a
  child before its parent dependency, and an async path with an unclosed owner.

- [ ] **Step 3: Run focused tests and current async gates.**

  ```bash
  cd src && zig test build/wit_abi_async.zig
  cd src && zig test build/codegen_component_async_plan.zig
  bash examples/p3-runtime/test_do_variant_resource_stream_lowering.sh
  ```

### Task 6: Migrate one private descriptor behind a differential gate

**Files:**
- Modify: `src/build/codegen_component_async.zig`
- Create: `src/build/codegen_component_async_v2_adapter.zig`
- Modify: `examples/p3-runtime/test_do_variant_resource_stream_lowering.sh`
- Test: existing variant Component/Rust/Wasmtime matrix

**Interfaces:**
- Consumes: `LayoutPlan`, `OwnershipPlan`, and `AsyncPlan`.
- Produces: the same private `variant-resource-stream` Component imports,
  layout markers, result tags, and cleanup counts as the v1 emitter.

- [ ] **Step 1: Add a differential test before dispatching v2.**

  Emit both paths for the private descriptor and compare the required import
  names, frame offsets, tag mapping, and cleanup markers. Do not compare
  incidental WAT formatting.

- [ ] **Step 2: Add opt-in v2 dispatch.**

  Add an internal test-only switch or direct unit entrypoint; keep default
  `do build` on the existing emitter until the differential gate is green.

- [ ] **Step 3: Run the complete migrated gate.**

  ```bash
  bash examples/p3-runtime/test_do_variant_resource_stream_lowering.sh
  bash examples/p3-runtime/test_variant_resource_stream_abi.sh
  ```

  Expected: ticket, idle, failed, pending, completion-error, malformed-tag,
  duplicate-release, and early-drop behavior remains unchanged.

### Task 7: Phase review and default-path decision

**Files:**
- Modify only with verified evidence: `doc/pending_blocked.md`, `doc/roadmap_status.md`, `doc/master_plan.md`, `CHANGELOG.md`
- Test: complete v1 and migrated descriptor matrix

**Interfaces:**
- Consumes: all prior task gates.
- Produces: a documented decision to keep v2 opt-in, promote the migrated
  descriptor, or stop with an explicit residual boundary.

- [ ] **Step 1: Run the full verification set.**

  ```bash
  cd src && zig test main.zig
  cd ../
  ./src/build/test/run_tests.sh
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  git diff --check
  ```

- [ ] **Step 2: Update status only from observed results.**

  Record whether the generic plan reproduces the migrated descriptor. Keep
  unsupported borrowed stream fields, arbitrary producer expressions, and
  unmeasured layouts in the pending list.

- [ ] **Step 3: Stop before public syntax or broad WASI expansion.**

  A green migrated descriptor is not permission to add public ownership syntax
  or claim complete WASI support. Those require separate designs and gates.
