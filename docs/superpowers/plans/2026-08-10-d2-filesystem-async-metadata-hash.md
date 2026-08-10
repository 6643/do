# D2 Filesystem Metadata Hash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Goal:** Privately admit the pinned `descriptor.metadata-hash` async filesystem method through the existing unified Component async target.

**Architecture:** Add one method-specific manifest shape and planner/emitter pair. The planner accepts only the exact `Dir` resource, `MetadataHash` record, `HashError` union, one direct await, ordinary `run`, and empty `start`; the emitter returns a fixed Core WAT template and a fixed Component WIT package. Existing generic async lowering and other filesystem methods remain unchanged.

**Tech Stack:** Zig compiler, checked-in WAT/WIT templates, `.do` compile fixtures, `wasm-tools 1.255.0`, Rust/Wasmtime oracle scripts already added in `examples/p3-runtime`.

## Global Constraints

- Pin `wasi:filesystem@0.3.0-rc-2025-09-16` and the recorded upstream WIT SHA-256.
- Require `wasm-tools 1.255.0` and its recorded tool SHA-256 in ABI verification.
- Use only the unified `--p3-async-component` target; add no CLI flag.
- Do not add public `Result<T,E>`, `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, lifetime, or generic filesystem async lowering.
- Keep `descriptor.metadata-hash-at` and arbitrary producer expressions rejected.

### Task 1: Add compiler fixtures and red tests

**Files:**
- Create: `src/build/test/compile_ok/516_wasi_filesystem_metadata_hash_component.do`
- Create: `src/build/test/compile_ok/516_wasi_filesystem_metadata_hash_component.expect`
- Create: `src/build/test/compile_err/517_wasi_filesystem_metadata_hash_unregistered.do`
- Create: `src/build/test/compile_err/517_wasi_filesystem_metadata_hash_unregistered.expect`
- Create: `src/build/test/compile_err/518_wasi_filesystem_metadata_hash_wrong_record.do`
- Create: `src/build/test/compile_err/518_wasi_filesystem_metadata_hash_wrong_record.expect`
- Create: `src/build/test/compile_err/519_wasi_filesystem_metadata_hash_second_await.do`
- Create: `src/build/test/compile_err/519_wasi_filesystem_metadata_hash_second_await.expect`

- [x] Write the exact positive source contract and expected WIT markers.
- [x] Write negative sources that prove the current compiler rejects the unregistered method, wrong record layout, and a second await.
- [x] Integrate the focused compile cases into the regression harness.

### Task 2: Register the pinned ABI

**Files:**
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/p3_async_manifest.zig`

- [x] Add the exact descriptor entry, canonical `(i32,i32)->i32` async import, `(i32,i64,i64)` task return, result-area record facts, and WIT identity.
- [x] Add `FilesystemMetadataHashShape` and a fail-closed validator checking every pinned field, record order, offsets, and drop import.
- [x] Add the shape to `LoweringShape` and `lowering_shape` dispatch.
- [x] Run manifest unit tests and assert malformed metadata-hash entries are not admitted.

### Task 3: Add the method-specific planner and emitter

**Files:**
- Create: `src/build/codegen_component_wasi_filesystem_metadata_hash.zig`
- Create: `src/build/wasi_filesystem_metadata_hash_component_template.wat`
- Modify: `src/build/codegen_component_async.zig`

- [x] Implement exact host binding/resource/record/error/function-shape validation using the existing filesystem planner style.
- [x] Emit the fixed Core WAT template and Component WIT package only after the plan succeeds.
- [x] Add target enum, target classification, Core WAT dispatch, Component WIT dispatch, and focused unit tests for positive and rejected shapes.

### Task 4: Run compiler/component gates

**Files:**
- Modify: `examples/p3-runtime/test_d2_wasi_filesystem_metadata_hash_abi.sh` only if the compiler gate needs a checked-in wrapper.

- [x] Build `ReleaseSmall` and run the positive/negative fixtures.
- [x] Run the metadata-hash ABI probe and Rust/Wasmtime runtime oracle.
- [x] Validate generated WIT and Core WAT with pinned `wasm-tools`.
- [x] Run `./src/build/test/run_tests.sh` and the WASM rerun with `RUN_WASM=1 SKIP_BUILD=1`.

### Task 5: Documentation and delivery

**Files:**
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `docs/superpowers/specs/2026-08-10-d2-filesystem-async-metadata-hash-design.md` if implementation evidence changes status.

- [x] Record the method-specific compiler admission and keep `metadata-hash-at` pending.
- [x] Update acceptance evidence with exact commands and results.
- [x] Review the diff, commit the bounded slice, and push only after all gates pass.
