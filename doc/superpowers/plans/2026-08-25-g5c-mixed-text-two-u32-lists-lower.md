# G5c Mixed Text + Two `list<u32>` Record Lower Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan task-by-task with review checkpoints. Preserve unrelated dirty changes in the current `main` checkout.

**Goal:** Add one measured synchronous `Writing { code, label, first, second }` lower descriptor with a GC-safe temporary linear-memory bridge.

**Architecture:** Extend the existing fixed-shape `SyncValuePlan`/marshal operation dispatch with one named three-span variant. Reuse `LoadedRequest`, the descriptor manifest, existing span guards, cleanup masks, and canonical import emission; do not add a generic aggregate emitter or a second layout table.

**Tech Stack:** Zig 0.16.0, `wasm-tools 1.255.0`, Wasmtime 47.0.2, the repository shell gates, and the existing Rust host runner.

**Spec:** `doc/superpowers/specs/2026-08-25-g5c-mixed-text-two-u32-lists-lower-design.md`

## Global Constraints

- Admit only descriptor `demo:marshal-record-mixed-text-two-u32-lists-lower/api.write@1.0.0/lower`.
- Require root 28 bytes/alignment 4, fields at `0/4/12/20`, list capacities `3/2`, and canonical `(param i32 i32 i32 i32 i32 i32 i32)`.
- Validate every span before copying and free `second`, `first`, `label` exactly once.
- Keep unknown, async, resource, ownership, arbitrary aggregate, dynamic-list, and unsupported element shapes fail-closed.
- Keep the inventory at `complete_rows=15 pending_rows=15`; do not claim full GC cutover.

### Task 1: Lock the plan and WAT variant

**Files:**

- Modify: `src/build/codegen_component_marshal_ops.zig`
- Modify: `src/build/codegen_component_marshal_wat.zig`
- Modify: `src/build/codegen_component_marshal_module.zig`
- Test: the focused tests in those three files

**Interfaces:**

- Consumes: the measured `SyncValuePlan` for the exact four-field record.
- Produces: `ManagedTextScalarListPairLower`, a 13-operation plan, a seven-word canonical import, and a fixed emitter with three cleanup slots.

- [x] **Step 1: Add the failing plan assertion.**
- [x] **Step 2: Run it and observe the missing variant.**
- [x] **Step 3: Add the minimal plan variant and run it green.**
- [x] **Step 4: Add the failing WAT assertion and observe generic lowering rejection.**
- [x] **Step 5: Add the fixed WAT emitter and module support, then run all three focused tests.**

### Task 2: Register the descriptor and source-level boundary

**Files:**

- Modify: `doc/wit/gc_descriptor_manifest.json`
- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/codegen_component_descriptor_manifest.zig`
- Create: `examples/gc-p3-runtime/ordinary-host-record-mixed-text-two-u32-lists-lower-call.do`
- Create: positive/negative fixtures under `src/build/test/compile_ok` and `src/build/test/compile_err`

**Interfaces:**

- Consumes: the exact descriptor and host-boundary fields in the spec.
- Produces: one manifest-backed default route and fail-closed source admission.

- [x] **Step 1: Add the positive boundary fixture and a failing validator assertion.**
- [x] **Step 2: Run the focused validator test and confirm the new descriptor is not yet admitted.**
- [x] **Step 3: Add the descriptor constant, admission entry, exact four-field shape, and manifest measurement.**
- [x] **Step 4: Add negative fixtures for async, locator/member drift, reorder, `[u8]`, extra field, and record-name drift.**
- [x] **Step 5: Run validator, manifest, and compile-mode tests.**

### Task 3: Add executable host and equivalence gates

**Files:**

- Create: host/equivalence/negative scripts under `examples/gc-p3-runtime`
- Create: fixed ARC core WAT and Rust runner binaries under the existing runner project
- Modify: `src/build/test/check_gc_g5c_residual_gate.sh`

**Interfaces:**

- Consumes: the descriptor, positive fixture, assembly WIT, and canonical seven-word import.
- Produces: host, ARC/GC equivalence, Component validation, negative, and default-route evidence.

- [x] **Step 1: Write the host script assertions for values, callback count, and `3/3` allocations/frees.**
- [x] **Step 2: Run the host script before adding the runner and observe the expected missing-binary failure.**
- [x] **Step 3: Add the minimal Rust host/equivalence adapters and fixed ARC oracle.**
- [x] **Step 4: Run host and equivalence scripts with pinned `wasm-tools 1.255.0`.**
- [x] **Step 5: Add and run the negative script; require no WAT artifact after rejection.**

### Task 4: Default route and full verification

**Files:**

- Modify: default-route gate scripts and `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/start_here.md`, and `examples/gc-p3-runtime/README.md`
- Test: full repository gates

**Interfaces:**

- Consumes: all focused evidence from Tasks 1–3.
- Produces: documented bounded promotion without changing inventory semantics.

- [x] **Step 1: Add the default fixture to the residual matrix and assert no ARC marker or GC reference import.**
- [x] **Step 2: Run `./src/build/test/run_tests.sh` and `(cd src && zig test main.zig)`.**
- [x] **Step 3: Run default GC, residual, ReleaseSmall/release-smoke, and semantic-equivalence gates.**
- [x] **Step 4: Run inventory and verify `complete_rows=15 pending_rows=15` with exit `1`.**
- [x] **Step 5: Run `git diff --check`, review only touched candidate files, and record residual risks.**
