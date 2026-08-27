# G5c C14 Four-Level Scalar-Record Compiler Boundary Implementation Plan

> **For agentic workers:** Execute this plan inline with test-first gates. Each step must leave fresh verification evidence.

**Goal:** Add the exact C14 four-level nested scalar-record `lift` and `lower`
compiler routes behind explicit `--gc-wit-marshal` validation.

**Architecture:** Reuse the checked-in descriptor manifest, measured marshal
plan, and existing four-level probe emitters. Extend only the manifest-derived
host-boundary validator from flat fields to recursively checked named record
children. Keep the default host/WIT route and migration inventory unchanged.

**Tech Stack:** Zig compiler, Do fixtures, WIT manifest, pinned
`wasm-tools 1.255.0`, Wasmtime host runners, Bash gates.

**Spec:** `doc/superpowers/specs/2026-08-22-g5c-c14-four-level-scalar-record-compiler-boundary-design.md`

## Global Constraints

- Admit only the two exact C14 descriptor ids.
- Reject descriptor/source/signature/shape drift before WAT output exists.
- Keep canonical Component imports free of GC references.
- Do not widen default host/WIT routing, arbitrary aggregate depth, async,
  resource, list/text record, or ownership support.
- Preserve all unrelated dirty worktree changes and do not change the 15-row
  migration inventory.

### Task 1: Add RED fixtures and focused route tests

**Files:**
- Create: `src/build/test/compile_ok/586_gc_wit_nested_record_deeper_lift_host_boundary.do`
- Create: `src/build/test/compile_ok/587_gc_wit_nested_record_deeper_lower_host_boundary.do`
- Create: `src/build/test/compile_err/588_gc_wit_nested_record_deeper_lift_host_boundary_async.do`
- Create: `src/build/test/compile_err/588_gc_wit_nested_record_deeper_lift_host_boundary_async.expect`
- Create: `src/build/test/compile_err/589_gc_wit_nested_record_deeper_lift_host_boundary_shape.do`
- Create: `src/build/test/compile_err/589_gc_wit_nested_record_deeper_lift_host_boundary_shape.expect`
- Create: `src/build/test/compile_err/590_gc_wit_nested_record_deeper_lower_host_boundary_mismatch.do`
- Create: `src/build/test/compile_err/590_gc_wit_nested_record_deeper_lower_host_boundary_mismatch.expect`
- Modify: `src/build/codegen_gc_wit_marshal.zig`

- [x] Add exact positive and negative source declarations.
- [x] Add C14 descriptor constants and a focused emitter test that initially
  demonstrates the descriptor is not yet admitted.
- [x] Run the focused Zig test and retain the expected RED failure before the
  implementation change.

### Task 2: Implement recursive boundary validation and C14 explicit emitters

**Files:**
- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/codegen_component_descriptor_manifest.zig`
- Modify: `src/build/codegen_gc_wit_marshal.zig`

- [x] Represent nested expected fields as recursively owned field slices while
  preserving existing flat managed-record specs.
- [x] Derive nested record shape from resolved WIT records and free the owned
  tree on every validation path.
- [x] Register the two descriptors and delegate to the existing C14 probe
  emitters after validation.
- [x] Run `cd src && zig test main.zig` and require all focused tests green.

### Task 3: Add compiler host/equivalence/negative gates

**Files:**
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deeper_compiler_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deeper_compiler_equivalence.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deeper_compiler_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deeper_compiler_equivalence.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_nested_deeper_compiler_boundary_negative.sh`

- [x] Build both positive fixtures with explicit descriptor ids, parse and
  validate the Core/Component output, and run the existing C14 Rust hosts.
- [x] Compare both generated Components with the existing ARC references.
- [x] Require async, locator/member, and nested field drift to reject before
  WAT and leave no output artifact.
- [x] Run `bash -n` and execute all five gates with pinned tools.

### Task 4: Wire evidence and complete repository verification

**Files:**
- Modify: `src/build/test/check_gc_g5c_residual_gate.sh`
- Modify: `examples/gc-p3-runtime/README.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/pending_blocked.md`
- Modify: `CHANGELOG.md`

- [x] Include the five C14 compiler gates in the residual baseline without
  changing inventory row status.
- [x] Record C14 compiler-boundary evidence and explicitly keep default route,
  arbitrary aggregate, async/resource and full G5c cutover pending.
- [x] Run focused Zig, full regression, residual gate, inventory, ReleaseSmall,
  release smoke, shell syntax, and `git diff --check`.
