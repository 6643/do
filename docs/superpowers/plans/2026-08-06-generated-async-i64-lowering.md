# Generated Async Scalar i64 Lowering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing bounded generated-WIT async Component gate with one measured `Future<i64>` capability while preserving the existing `Future<u32>` contract and rejecting all unregistered or unmeasured shapes.

**Architecture:** Add a private `component-async-scalar-i64-v1` descriptor beside the existing unit and scalar-u32 descriptors. The WIT manifest validator and build-side manifest loader admit only the exact pinned i64 package/member/signature and measured payload descriptor. The scalar source analyzer consumes the validated descriptor and accepts either the matching `Future<u32>` or `Future<i64>` shape; the Component template receives the descriptor's load/store operations and metadata instead of assuming 32-bit payloads.

**Tech Stack:** Zig 0.16.0, the `do` compiler/import graph, WIT parser/resolver/emitter, `wasm-tools 1.254.0`, Wasmtime 47.0.2, Rust 1.97.1, existing Cargo host runner.

## Global Constraints

- Keep generated async lowering bounded to the two pinned scalar capabilities; do not claim unrestricted WIT async support.
- Measure the i64 payload descriptor with `wasm-tools component embed --async-callback --dummy-names legacy`; do not infer offsets from the u32 fixture.
- Preserve `Future<u32>` behavior and all existing negative admission/manifest tests.
- Do not introduce public `own<T>`, `borrow<T>`, `ref<T>`, pointer, resource, list, text, or variant lowering in this change.
- Use red/green tests for every new capability and run `./src/build/test/run_tests.sh` before delivery.

---

### Task 1: Add the failing i64 capability and source gate

**Files:**
- Create: `examples/p3-runtime/wit/generic-async-scalar-i64-probe.wit`
- Create: `examples/wit-bindgen-do/project/scalar_i64_async_main.do`
- Modify: `src/build/codegen_generated_async_scalar_plan.zig`
- Test: `src/build/test/check/431_generated_async_scalar_i64.do`
- Test fixture: `src/build/test/check/wit/scalar_i64/`

**Interfaces:**
- Consumes: the existing generated scalar analyzer and module-graph lowering descriptor.
- Produces: a red test proving a valid generated `Future<i64>` shape is currently rejected.

- [x] **Step 1: Write the i64 WIT and generated caller fixture.**

  Use `future<s64>` in the same private package/world/interface/member shape as the u32 probe, and use the existing one-await/one-cancel caller shape with `Future<i64>`.

- [x] **Step 2: Add the analyzer acceptance test before implementation.**

  Add a test graph descriptor for the measured i64 shape and assert the new caller is accepted. The test must fail with `UnsupportedGeneratedAsyncScalarShape` until capability recognition is added.

- [x] **Step 3: Run the focused Zig test and verify the expected red failure.**

  Run `zig test src/build/codegen_generated_async_scalar_plan.zig`; expected: the new i64 acceptance test fails because no i64 lowering is admitted.

---

### Task 2: Measure and register the i64 WIT descriptor

**Files:**
- Create: `examples/wit-bindgen-do/test_generated_async_scalar_i64_lowering.sh`
- Modify: `src/wit/async_lowering.zig`
- Modify: `src/wit/manifest.zig`
- Modify: `src/wit/manifest_test.zig`
- Modify: `src/wit/tests.zig` if the WIT test import list requires the new fixture.

**Interfaces:**
- Consumes: the i64 WIT source and the measured dummy async-callback ABI.
- Produces: `component-async-scalar-i64-v1` with exact package/member/signature/import/payload metadata.

- [x] **Step 1: Generate the measurement artifact.**

  `wasm-tools component embed` was used to validate the pinned `future<s64>` world shape; the generated runtime WAT gate records the descriptor and validates the actual `i64.load`/`i64.store` payload operations. The frame layout is measured as `offset=16`, `byte_size=8`, `alignment=8`, `core_type=i64`, `encoding=core-s64`; the canonical async import names remain the pinned future-read/cancel/drop names.

- [x] **Step 2: Add a manifest test that fails before registration.**

  Resolve the i64 WIT source and assert `async_lowering.detect` returns one capability named `component-async-scalar-i64-v1`; before the implementation it must fail because the detector returns no capability.

- [x] **Step 3: Implement exact i64 detection and manifest validation.**

  Add constants and exact descriptor checks in `src/wit/async_lowering.zig` and `src/wit/manifest.zig`. The validator must reject a changed payload offset, signature, import name, or encoding.

- [x] **Step 4: Run focused WIT tests and the measurement gate.**

  Run `zig test src/wit/manifest_test.zig` and `bash examples/wit-bindgen-do/test_generated_async_scalar_i64_lowering.sh`; expected: both pass and the generated descriptor is reproducible.

---

### Task 3: Carry and validate i64 metadata through the build graph

**Files:**
- Modify: `src/build/generated_wit_manifest.zig`
- Modify: `src/build/codegen_generated_async_scalar_plan.zig`
- Modify: `src/build/codegen_component_async.zig`

**Interfaces:**
- Consumes: validated schema-2 i64 manifest metadata.
- Produces: an owned `GeneratedAsyncScalarPlan` containing the i64 descriptor and matching source payload type.

- [x] **Step 1: Add a build-side manifest rejection test for an unknown i64 capability.**

  Mutate a temporary valid manifest to use `component-async-scalar-i64-v1` with a wrong offset and assert `GeneratedWitManifestMismatch` before code generation.

- [x] **Step 2: Admit the exact i64 descriptor.**

  Extend `validate_lowerings` and `GeneratedAsyncLowering` loading checks with the measured i64 package/member/signature and payload facts; retain u32 checks unchanged.

- [x] **Step 3: Make source admission descriptor-driven.**

  Replace u32-only predicates with a small scalar descriptor mapping that validates the source `Future<T>` and awaited `T` against `payload.encoding/core_type`. Keep text, timeout, second-await, async-root, and hand-written-host negative tests red.

- [x] **Step 4: Run the focused build tests.**

  Run `zig test src/build/codegen_generated_async_scalar_plan.zig` and `zig test src/build/codegen_component_async.zig`; expected: u32 and i64 acceptance tests pass and existing negatives remain rejected.

---

### Task 4: Parameterize Component payload operations and add the runtime gate

**Files:**
- Modify: `src/build/codegen_component_generated_async_scalar.zig`
- Modify: `src/build/generated_async_scalar_component_template.wat`
- Create: `examples/wit-bindgen-do/test_generated_async_scalar_i64_lowering.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/generated_async_scalar.rs` or create a dedicated i64 runner binary if the host import types must remain isolated.

**Interfaces:**
- Consumes: descriptor-driven scalar plan from Task 3.
- Produces: valid Component WAT/WIT with i64 payload operations and ready/pending/cancel runtime evidence.

- [x] **Step 1: Add an emitter test for i64 operations.**

  Assert the rendered WAT contains `core-i64`, `i64.load`, and `i64.store`, and contains no `i32.load`/`i32.store` in payload operation markers.

- [x] **Step 2: Parameterize the template.**

  Add placeholders for payload load/store instructions and replace only those placeholders from a validated descriptor. Reject unknown encodings with `InvalidGeneratedAsyncScalarTemplate`.

- [x] **Step 3: Add the generated i64 Component/Rust/Wasmtime gate.**

  Run WIT check/bind/manifest validation, build the generated caller, embed the WIT, create/validate the Component, then exercise ready/pending/cancel with exact i64 value and poll/drop counts. Mutated manifest descriptors must fail before WAT emission.

- [x] **Step 4: Run focused gates.**

  Run `bash examples/wit-bindgen-do/test_generated_async_scalar_i64_lowering.sh` and the existing `bash examples/wit-bindgen-do/test_generated_async_scalar_lowering.sh`.

---

### Task 5: Document and close the checkpoint

**Files:**
- Modify: `examples/wit-bindgen-do/README.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/pending_blocked.md` if the bounded-scalar status table changes.

**Interfaces:**
- Consumes: passing i64 focused and runtime gates plus the existing full matrix.
- Produces: an explicit statement that bounded generated scalar lowering covers u32 and i64 only, with generic/text/list/resource lowering still blocked.

- [x] **Step 1: Update the bounded capability table and residual risk.**
- [x] **Step 2: Run the complete verification matrix.**

  Run the Bun-shimmed `./src/build/test/run_tests.sh` (the repository's Node-compatible test entry), both generated u32/i64 Component gates, the focused WIT/build tests, and `cd src && zig build -Doptimize=ReleaseSmall`. Result: `pass=1109 fail=0 skip=3`; all focused gates pass.

- [x] **Step 3: Review the diff and commit only this checkpoint.**

  Diff review and `git diff --check` passed. The checkpoint remains uncommitted in the working tree so the pre-existing untracked implementation plans and user changes are preserved for the delivery decision.

  Keep the pre-existing untracked `docs/superpowers/plans/2026-08-06-generated-async-lowering.md`; do not delete or rewrite it.

## Execution Order

Tasks 1 through 4 are sequential because each later gate consumes the descriptor produced by the earlier task. Task 5 is the final documentation and verification checkpoint. No public ownership/reference semantics or unrestricted WIT async lowering is part of this plan.
