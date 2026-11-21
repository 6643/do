# D2 `descriptor.advise` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one private, opt-in compiler/runtime route for the pinned `wasi:filesystem/types@0.3.0-rc-2025-09-16` `descriptor.advise` method.

**Architecture:** Follow the existing method-specific filesystem async routes. Add an exact manifest shape, source matcher, fixed direct-ABI Core/WIT templates, and a Rust/Wasmtime gate. Keep the default compiler route fail-closed and do not add public ownership or generic filesystem lowering.

**Tech Stack:** Zig compiler, Do fixtures, pinned WIT mirrors, Core WebAssembly text, `wasm-tools`, Rust component host, Wasmtime.

**Spec:** `doc/superpowers/specs/2026-08-11-d2-filesystem-async-advise-design.md`

## Global Constraints

- Locator is `wasi:filesystem/types@0.3.0-rc-2025-09-16`; upstream WIT SHA-256 is `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`.
- The measured method Core import is direct `(i32, i64, i64, i32, i32) -> i32`, in descriptor, offset, length, advice, result-area order.
- Advice discriminants are `normal=0`, `sequential=1`, `random=2`, `will-need=3`, `dont-need=4`, `no-reuse=5`.
- The route is available only through `--p3-async-component`; ordinary default compilation remains unavailable for this shape.
- The Rust host runner uses its checked-in `Cargo.lock`, which pins Wasmtime `50.0.0`; do not update dependencies as part of this task.
- Unsupported locator/member/version/types/control flow fail before WAT; no indirect ABI fallback is allowed.
- Cancellation releases compiler/runtime state and does not claim to roll back an advisory call already issued to the host.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, generic filesystem lowering, or a GC migration inventory row.

## Review Focus

- Reordered or incomplete `Advice` mappings must fail before WAT; cover with an enum-mapping negative fixture.
- Wrong receiver, width, locator, or result union must not select the target; cover each with a compile-error fixture.
- Branches, loops, second awaits, extra host bindings, and async roots must remain rejected; cover topology negatives.
- A pending call must preserve both `u64` arguments and the enum discriminant across a wake; assert exact host-observed values.
- Store disposal must not be reported as guest cancellation or an empty live `ResourceTable`; assert the existing Wasmtime boundary.

---

### Task 1: Register The Measured Descriptor Shape

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Test: `src/build/p3_async_manifest.zig`

**Interfaces:**
- Produces: a distinct `filesystem_advise` `LoweringShape` with validated descriptor, canonical import, task-return, payload tag, and WIT identity facts.

- [x] **Step 1: Add manifest unit tests** for accepted direct parameters `[i32, i64, i64, i32, i32] -> [i32]`, the `unit | error-code` payload, descriptor resource identity, and WIT package/interface/operation. Add mutations for each ABI or WIT method fact and assert rejection.
- [x] **Step 2: Run `cd src && zig test build/p3_async_manifest.zig`** with the repository's existing isolated-cache convention and confirm the new assertions fail because the lowering shape is absent.
- [x] **Step 3: Add `FilesystemAdviseShape`, its exact validator, and the registry row** using the pinned hashes and direct ABI facts. Do not represent an indirect argument block.
- [x] **Step 4: Run `cd src && zig test build/p3_async_manifest.zig`** and confirm accepted and mutated descriptors produce the expected shape/rejection.

### Task 2: Add Exact Source Admission And Component Emission

**Files:**
- Create: `src/build/codegen_component_wasi_filesystem_advise.zig`
- Create: `src/build/wasi_filesystem_advise_component_template.wat`
- Modify: `src/build/codegen_component_async.zig`
- Create: `src/build/test/compile_ok/807_wasi_filesystem_advise_component.do`
- Create: `src/build/test/compile_ok/807_wasi_filesystem_advise_component.expect`
- Create: `src/build/test/compile_err/807_wasi_filesystem_advise_unregistered.do` through `820_wasi_filesystem_advise_async_root.do`, with matching `.expect` files
- Modify: `src/build/test/test_harness.zig`
- Test: `src/build/codegen_component_async.zig`

**Interfaces:**
- Consumes: Task 1's `filesystem_advise` manifest shape.
- Produces: an opt-in target that accepts only the exact `Advice`, `AdviseError`, descriptor resource, host binding, one direct await, and empty synchronous `start` source shape.

- [x] **Step 1: Add a positive compile fixture** for the design's `(File, u64, u64, Advice) -> nil | AdviseError` binding and one direct await; assert the selected target and generated WIT/Core imports.
- [x] **Step 2: Add negative fixtures** for unregistered/wrong-version locator, wrong receiver, wrong offset/length type, wrong error/result source, missing/reordered/duplicate Advice arm, second await, branch, loop, extra host binding, and async root. Use IDs `807`-`820` in that order and assert each fails before WAT.
- [x] **Step 3: Run `cd src && zig test build/codegen_component_async.zig`** and verify the positive case initially fails admission while all negative cases fail closed.
- [x] **Step 4: Implement `FilesystemAdvisePlan.analyze`** and wire target selection, Core emission, and WIT emission using the existing `set-size` module boundary.
- [x] **Step 5: Run `cd src && zig test build/codegen_component_async.zig`** and compare generated Core imports byte-for-byte with the direct ABI: `(i32,i64,i64,i32,i32)->i32`.

### Task 3: Lock Regular And Cancellation Component ABI

**Files:**
- Modify: `examples/p3-runtime/wit/wasi-filesystem-advise-probe.wit`
- Modify: `examples/p3-runtime/wit/wasi-filesystem-advise-cancel-probe.wit`
- Create: `examples/p3-runtime/wasi-filesystem-advise.core.wat`
- Create: `examples/p3-runtime/wasi-filesystem-advise-cancel.core.wat`
- Modify: `examples/p3-runtime/test_d2_wasi_filesystem_advise_abi.sh`

**Interfaces:**
- Consumes: Task 2's generated WIT and Core template plus the existing ABI probe tool/mirror hashes.
- Produces: a reproducible regular/cancel Component parse, assembly, validation, and generated-vs-canonical ABI comparison.

- [x] **Step 1: Extend the existing ABI gate** to check both generated and hand-authored Core against the measured import signature, enum order, task-return, cancel imports, result area, descriptor drop, and absence of neighboring methods.
- [x] **Step 2: Assemble and validate** regular and cancellation worlds with the locally pinned `wasm-tools 1.263.0` binary and hash; preserve the repository-wide toolchain lock as-is.
- [x] **Step 3: Add generated/canonical Component parity assertions** for the exact method and WIT world.
- [x] **Step 4: Run the ABI gate** and record its exact tool identity and observed signatures.

### Task 4: Verify Rust/Wasmtime Lifecycle And Advice Values

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_advise.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_advise.sh`

**Interfaces:**
- Consumes: Task 3's regular/cancel Components and generated compiler fixture.
- Produces: a bounded runtime gate covering every valid advice value and each applicable terminal path.

- [x] **Step 1: Add the Rust runner and mode assertions** for all six valid advice values, exact descriptor/range values, ready, pending, explicit error, cancel, Store-disposal early-drop, and repeat. Assert exactly-once Future/descriptor cleanup and empty `ResourceTable` only for live-Store terminal rows.
- [x] **Step 2: Add a test-only invalid-discriminant probe** proving raw value `6` traps/rejects at the Component boundary; do not count it as a successful invocation.
- [x] **Step 3: Build the generated Component** with `--p3-async-component`, assemble it with the matching WIT world, and compare its behavior to the canonical Component.
- [x] **Step 4: Run the focused Rust/Wasmtime gate** and check all six discriminants, pending argument preservation, explicit cancellation, Store disposal, repeat, and cleanup counts.

### Task 5: Close Documentation And Regression Gates

**Files:**
- Modify: `doc/superpowers/specs/2026-08-11-d2-filesystem-async-advise-design.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/master_plan.md`
- Modify: `examples/p3-runtime/README.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Tasks 1-4's passing manifest, compiler, ABI, and runtime gates.
- Produces: an evidence-bounded status update saying private `descriptor.advise` admission is closed, without claiming generic D2 support.

- [x] **Step 1: Update the design status and evidence** with exact commands, the direct signature, enum observations, cleanup counts, and remaining generic filesystem/HTTP blockers.
- [x] **Step 2: Update current-status documents** to move `descriptor.advise` from ABI-only to a private bounded compiler/runtime slice; retain the 1.263.0 local pin disclosure and do not alter the global lock.
- [x] **Step 3: Run the focused ABI/runtime gates, `./src/build/test/run_tests.sh`, `./src/build/test/run_release_smoke.sh`, and `git diff --check`.**

