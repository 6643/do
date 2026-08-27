# G5c Mixed Text + Byte/U32 Lists Record Lower Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan task-by-task with review checkpoints. Preserve unrelated dirty changes in the current `main` checkout.

**Goal:** Add one measured synchronous `Writing { code, label, bytes, values }` lower descriptor with a GC-safe temporary linear-memory bridge.

**Architecture:** Add one exact-shape operation variant for a text field followed by a byte list and a u32 list. Reuse the existing manifest-backed `LoadedRequest`, descriptor registry, `SyncValuePlan`, span guards, cleanup mask, and canonical seven-word import. Do not add a generic aggregate emitter, list inference, or a second layout table.

**Tech Stack:** Zig 0.16.0, `wasm-tools 1.255.0`, Wasmtime 47.0.2, repository shell gates, and the existing Rust host runner.

**Spec:** `doc/superpowers/specs/2026-08-25-g5c-mixed-text-byte-u32-lists-lower-design.md`

## Global Constraints

- Admit only descriptor `demo:marshal-record-mixed-text-byte-u32-lists-lower/api.write@1.0.0/lower`.
- Require root 28 bytes/alignment 4, fields at `0/4/12/20`, byte-list capacity `4`, u32-list capacity `3`, and canonical `(param i32 i32 i32 i32 i32 i32 i32)`.
- Validate every span before copying and free `values`, `bytes`, `label` exactly once.
- Keep unknown, async, resource, ownership, arbitrary aggregate, dynamic-list, and unsupported element shapes fail-closed.
- Keep inventory at `complete_rows=15 pending_rows=15`; do not claim full GC cutover.

## Verification status (2026-08-26)

The exact descriptor has fresh green evidence in the current checkout. The
focused marshal suites pass `90/90`, `43/43`, and `66/66`; the source/WIT hash
matches the manifest (`sha256:2d966dfc68f27f42ba7ce5f44c471907cf2ebe922a9af24d3cfc810847cce9c3`);
the manifest parses as JSON; and the dedicated host, equivalence, and negative
scripts pass. Host observations are `code=7`, `label=hello`,
`bytes=[10, 20, 5]`, `values=[3, 4]`, `write-calls=1`,
`allocations=3`, `frees=3`; ARC/GC equivalence observes `3/3` cleanup and
`1/1` callback. The seven descriptor-drift fixtures reject before WAT and an
unadmitted host fixture retains the ARC fallback.

The default GC gate, residual gate, semantic-equivalence matrix, full
regression, `zig test main.zig`, ReleaseSmall build, and release smoke all
pass with pinned Zig `0.16.0`, `wasm-tools 1.255.0`, and Wasmtime `47.0.2`.
The migration inventory remains deliberately open at
`complete_rows=15 pending_rows=15` with exit `1`. The unchecked steps below
describe the historical red/green execution order; this section records the
current evidence without reconstructing an unobserved missing-runner failure.

### Task 1: Add the failing operation and WAT tests

**Files:**

- Modify: `src/build/codegen_component_marshal_ops.zig`
- Modify: `src/build/codegen_component_marshal_wat.zig`
- Test: focused unit tests in those modules

**Interfaces:**

- Consumes: the measured four-field `SyncValuePlan` from the new manifest.
- Produces: a named three-span lower variant with byte/u32 element dispatch and
  canonical seven-word call order.

- [x] **Step 1: Add the operation-plan assertion.** The exact root shape is
  recognized, `bytes` is `ScalarListElementKind.byte`, `values` is `.u32`, and
  the operation sequence contains one canonical call and three frees in
  reverse order. The historical pre-admission red run was not reconstructed.
- [x] **Step 2: The focused operation test now passes.** A historical run
  before descriptor admission was not replayed; the current green evidence is
  recorded in the verification section above.
- [x] **Step 3: Add the smallest exact-shape operation variant.** Keep field
  offsets, capacities, and element kinds fixed in the validator; do not make
  the existing generic list matcher accept arbitrary records.
- [x] **Step 4: Add the WAT assertions** for the seven-word import,
  `array.get_s $do_bytes`, `array.get $do_u32`, span guards before loads, and
  `values -> bytes -> label` cleanup. The current assertions pass.
- [x] **Step 5: Implement the fixed emitter and rerun focused operation/WAT
  tests.** The emitter must preserve the existing cleanup-mask trap path.

### Task 2: Register the descriptor and source boundary

**Files:**

- Modify: `doc/wit/gc_descriptor_manifest.json`
- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/codegen_component_descriptor_manifest.zig`
- Modify: `src/build/run.zig` if the default-admission fixture table requires it
- Create: `src/build/test/compile_ok/682_gc_wit_mixed_text_byte_u32_lists_lower_host_boundary.do`
- Create: matching negative fixtures under `src/build/test/compile_err` numbered after 681

**Interfaces:**

- Consumes: the exact source/world files and hash in the spec.
- Produces: one manifest-backed default route with fail-closed source admission.

- [x] **Step 1: Add the positive Do boundary fixture and validate the exact
  source boundary.**
- [x] **Step 2: Add the descriptor manifest entry with measured root/children,
  `do_record_name: "Writing"`, and canonical import.** Validate the SHA-256
  against the source/world concatenation before compiling.
- [x] **Step 3: Add the locator/member registration and exact shape admission.**
  Keep unknown descriptors on ARC fallback.
- [x] **Step 4: Add negative fixtures for async, locator drift, member drift,
  field reorder, byte/u32 substitution, extra field, and record-name drift.
  Each `.expect` must assert rejection before WAT.
- [x] **Step 5: Run manifest, host-boundary, compile-ok, and compile-err tests.**

### Task 3: Add executable host and ARC/GC equivalence gates

**Files:**

- Create: `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_u32_lists_lower_manifest_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_u32_lists_lower_manifest_equivalence.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_u32_lists_lower_negative.sh`
- Create: `examples/gc-p3-runtime/marshal-record-mixed-text-byte-u32-lists-lower-assembly.wit`
- Create: fixed ARC/core WAT and Zig probe files following the existing lower-route pattern
- Create: matching Rust runner binaries under `examples/p3-runtime/rust-host-runner/src/bin`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`

**Interfaces:**

- Consumes: the descriptor, positive fixture, assembly WIT, and seven-word import.
- Produces: Component validation, host payload, ARC/GC equivalence, negative,
  allocation/free, and callback-count evidence.

- [x] **Step 1: Add host assertions for `code=7`, `label=hello`,
  `bytes=[10, 20, 5]`, `values=[3, 4]`, one callback, and `3/3` cleanup.**
- [x] **Step 2: The historical pre-runner missing-adapter failure is not
  reconstructed; the current host gate passes and this omission is recorded
  explicitly in the verification section above.
- [x] **Step 3: Add the minimal Rust host/equivalence adapters and ARC oracle;
  keep WIT package and member names identical between GC and ARC.**
- [x] **Step 4: Run host and equivalence gates with pinned `wasm-tools 1.255.0`
  and Wasmtime GC enabled.**
- [x] **Step 5: Run the negative gate and require no WAT artifact after every
  rejected source fixture.**

### Task 4: Promote the exact route and verify the repository

**Files:**

- Modify: the applicable default-route, residual, and semantic-equivalence gate scripts
- Modify: `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/start_here.md`, and `examples/gc-p3-runtime/README.md`

**Interfaces:**

- Consumes: focused operation, source-boundary, host, negative, and equivalence evidence.
- Produces: a documented bounded promotion without changing inventory semantics.

- [x] **Step 1: Add the exact fixture to the default route and assert no ARC
  marker and no canonical `(ref` import.**
- [x] **Step 2: Run `./src/build/test/run_tests.sh` and `(cd src && zig test main.zig)`.**
- [x] **Step 3: Run default GC, residual, semantic-equivalence,
  ReleaseSmall, and release-smoke gates.**
- [x] **Step 4: Run inventory and require `complete_rows=15 pending_rows=15`
  with exit `1`.**
- [x] **Step 5: Run `git diff --check`, inspect only candidate files, and
  document remaining general aggregate/list and async/resource boundaries.**

## Exit Criteria

The candidate is complete only when all four tasks have fresh green evidence,
the full regression and release gates pass, the source hash and measured layout
match the spec, and the migration inventory remains intentionally
`complete_rows=15 pending_rows=15` with exit `1`. Failure of any focused gate
stops promotion and keeps the descriptor out of the default route.
