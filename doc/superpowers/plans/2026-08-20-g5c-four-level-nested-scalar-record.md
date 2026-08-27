# G5c C14 Four-Level Nested Scalar Record Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Execute this plan inline with test-first gates. Steps use checkbox syntax and each completed step must leave fresh verification evidence.

**Goal:** Close one private manifest-backed G5c slice for four-level nested scalar-record `lift` and `lower` without widening the default host/WIT route.

**Architecture:** Reuse the existing parser-backed descriptor loader, measured recursive marshal plan, and GC record emitter. Add one exact WIT/source descriptor for a four-level record tree and two probe entry points; keep canonical Component boundaries linear-memory-only and reject descriptor, signature, hash, layout, and unsupported-shape drift before WAT emission.

**Tech Stack:** Zig compiler/probe code, WIT source fragments, WAT/Core Component assembly, `wasm-tools 1.255.0`, Wasmtime `47.0.2`, Rust host runner, shell gates.

**Spec:** `doc/superpowers/specs/2026-08-20-g5c-four-level-nested-scalar-record-design.md` (C14 extends the same bounded manifest/provenance contract; no default-route admission).

## Global Constraints

- Use only `wasm-tools 1.255.0 (76e20611d 2026-07-30)` and Wasmtime `47.0.2`.
- The four-level source shape is private and descriptor-id gated; ordinary `do build` host/WIT lowering remains ARC-backed.
- No `own<T>`, `borrow<T>`, `ref<T>`, async, stream, resource, or arbitrary aggregate admission is added.
- No GC reference may cross a canonical Component import; lower uses scalar canonical words and lift uses one result-area pointer.
- Mutated source, descriptor identity, signature, measured layout, direction, and canonical import must fail closed before Component assembly.
- The host and ARC/GC equivalence rows must observe the same semantic result (`42`) and exactly one callback per path.

---

### Task 1: Write the C14 design and lock the measured shape

**Files:**
- Create: `doc/superpowers/specs/2026-08-20-g5c-four-level-nested-scalar-record-design.md`
- Create: `doc/superpowers/plans/2026-08-20-g5c-four-level-nested-scalar-record.md`

- [x] **Step 1: Record the exact WIT and expected measurements.**

  The source tree is `reading { detail: detail, tail: s64 }`, `detail { header: header, marker: s64 }`, `header { leaf: leaf, status: s64 }`, and `leaf { code: u32, count: u64 }`. The measured record sizes are `leaf=16`, `header=24`, `detail=32`, `reading=40`, alignment `8`; leaf offsets in the root result area are `code@0`, `count@8`, `status@16`, `marker@24`, `tail@32`.

### Task 2: Add RED route and shape tests

**Files:**
- Modify: `src/build/codegen_component_manifest_route_test.zig`
- Modify: `src/build/codegen_component_marshal_ops.zig` only if the RED test reaches a missing guard

- [ ] **Step 1: Add a four-level measurement and descriptor-id test.**

  Assert that the new descriptor is not accepted until its manifest entry and source fragments exist, and that a mismatched depth/layout returns `error.UnsupportedMarshalShape` or the existing measured-shape error before WAT emission.

- [ ] **Step 2: Run the focused Zig test and verify RED.**

  Run: `cd src && zig test main.zig`

  Expected: the new test fails because the descriptor and four-level fixture are not yet registered; do not weaken the test to make it pass.

### Task 3: Implement the private four-level manifest-backed probes

**Files:**
- Create: `doc/wit/gc_marshal_record_nested_lift_deeper_imports.wit`
- Create: `examples/gc-p3-runtime/marshal-record-nested-lift-deeper-manifest-source.wit`
- Create: `examples/gc-p3-runtime/marshal-record-nested-lift-deeper-assembly.wit`
- Create: `examples/gc-p3-runtime/marshal-record-nested-lower-deeper-manifest-source.wit`
- Create: `examples/gc-p3-runtime/marshal-record-nested-lower-deeper-assembly.wit`
- Modify: `doc/wit/gc_descriptor_manifest.json`
- Create: `src/build/gc_marshal_record_nested_lift_deeper_probe.zig`
- Create: `src/build/gc_marshal_record_nested_lower_deeper_probe.zig`
- Create: `src/gc_marshal_record_nested_lift_deeper_probe_main.zig`
- Create: `src/gc_marshal_record_nested_lower_deeper_probe_main.zig`
- Modify: `src/build/codegen_component_manifest_route_test.zig`

- [ ] **Step 1: Register both exact descriptors.**

  Pin each source fragment hash, package/world/member/signature, direction, and canonical import. The lower import is `(i32, i64, i64, i64, i64) -> nil` in the measured order; the lift import is `(i32) -> nil`, with the sole parameter being the result-area pointer according to the existing descriptor conventions.

- [ ] **Step 2: Emit recursive four-level GC values.**

  Build the measured tree with `reading=40`, `detail=32`, `header=24`, `leaf=16`; lower the leaves `7, 35, -5, 11, -6` to produce `42`, and lift the host result area into nested GC records and sum the same leaves to `42`.

- [ ] **Step 3: Run focused Zig tests and verify GREEN.**

  Run: `cd src && zig test main.zig`

  Expected: all existing tests plus the C14 route/probe tests pass, including canonical-import no-GC-reference assertions and source-hash/shape rejection.

### Task 4: Add Component host and ARC/GC equivalence gates

**Files:**
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deeper_manifest_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deeper_manifest_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deeper_manifest_equivalence.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deeper_manifest_equivalence.sh`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_nested_lift_deeper.rs`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_nested_lift_deeper_host_equivalence.rs`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_nested_lower_deeper.rs`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_nested_lower_deeper_host_equivalence.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Modify: `src/build/test/check_gc_g5c_residual_gate.sh`

- [ ] **Step 1: Assemble and validate each generated Component.**

  Require the pinned tool version, WIT embed/new/validate, no `(ref ...)` canonical import, mutated-source rejection, and exact host callback output `sum=42` or `result=42` with one callback.

- [ ] **Step 2: Compare GC and linear-memory ARC references.**

  Run the paired Components through the same Rust/Wasmtime host and require `42/42` plus callback counts `1/1`. Keep the ARC reference hand-authored and probe-only.

- [ ] **Step 3: Add the C14 rows to the residual gate.**

  The gate must invoke all four scripts and fail if any script is missing, fails, or is not represented in the completion inventory.

### Task 5: Sync documentation and run the complete verification matrix

**Files:**
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/pending_blocked.md`
- Modify: `CHANGELOG.md`
- Modify: `src/build/test/check_gc_migration_inventory.sh`

- [ ] **Step 1: Record C14 as a bounded closure, not a generic cutover.**

  State the exact measured layout, host/equivalence evidence, and unchanged residuals: arbitrary aggregate, default host/WIT routing, async/resource, and full G5c cutover remain pending.

- [ ] **Step 2: Run focused and full verification.**

  Run: `cd src && zig test build/main.zig`; `./src/build/test/run_tests.sh`; `bash src/build/test/check_gc_g5c_residual_gate.sh baseline`; `bash src/build/test/check_gc_migration_inventory.sh`; `cd src && zig build -Doptimize=ReleaseSmall`; `git diff --check`.

- [ ] **Step 3: Inspect the final diff and report exact evidence.**

  Confirm only C14 files plus required roadmap/inventory changes are touched; report pass/fail counts and any unverified or remaining blockers without claiming G5c/full GC completion.
