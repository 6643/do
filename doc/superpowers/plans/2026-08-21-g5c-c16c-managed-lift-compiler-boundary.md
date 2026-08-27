# G5c C16-C Managed Lift Compiler Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or superpowers:subagent-driven-development) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a private explicit compiler route for the already measured C15-A managed-record lift descriptor.

**Architecture:** Reuse the existing manifest-backed synchronous marshal emitter and extend the source validator with a direction-specific fixed descriptor spec. The normal `@host_func` route remains ARC-backed and no generic WIT type inference is introduced.

**Tech Stack:** Zig compiler, Do fixtures, pinned `wasm-tools 1.255.0`, Rust/Wasmtime host runners, Bash regression gates.

**Spec:** `doc/superpowers/specs/2026-08-21-g5c-c16c-managed-lift-compiler-boundary-design.md`

## Global Constraints

- Keep `--gc-wit-marshal` explicit and fail-closed.
- Preserve C15-B and C16-A behavior and all unrelated dirty worktree changes.
- Do not change the migration inventory or default ARC routing.
- Do not add `own<T>`, `borrow<T>`, `ref<T>`, generic aggregate lowering, async/resource lowering, or compatibility branches.

### Task 1: Lock the source boundary with RED tests

**Files:**
- Create: `src/build/test/compile_ok/566_gc_wit_managed_record_lift_host_boundary.do`
- Create: `src/build/codegen_gc_wit_host_boundary.zig` test additions
- Modify: `src/build/codegen_gc_wit_marshal.zig` emitter test

- [x] Add the exact `read`/`Reading` fixture from the spec.
- [x] Add focused validator and emitter tests expecting the current
  `UnsupportedGcWitHostDescriptor` or equivalent failure for the new lift
  descriptor.
- [x] Run `cd src && zig test main.zig --test-filter 'C16-C'` and confirm the
  failure is caused by the missing descriptor support.

### Task 2: Implement the fixed lift descriptor and emitter

**Files:**
- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/codegen_gc_wit_marshal.zig`
- Modify: `src/build/run.zig`

- [x] Add a direction-specific `DescriptorSpec` entry for C15-A with zero
  params, result `Reading`, and fields `code/u32`, `label/text`.
- [x] Make host signature validation support either lower parameters/result or
  lift zero-parameter/result-record shape without weakening existing checks.
- [x] Add the 12-byte managed-lift measurement and append the existing typed
  `$run` wrapper used by the verified C15-A probe.
- [x] Keep C15-B/C16-A lower output byte-for-byte behavior and run focused
  GREEN tests.

### Task 3: Add compiler host/equivalence and fail-closed gates

**Files:**
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_compiler_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_compiler_equivalence.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_compiler_boundary_negative.sh`
- Create: `src/build/test/compile_err/579_gc_wit_managed_record_lift_host_boundary_async.do/.expect`
- Create: `src/build/test/compile_err/580_gc_wit_managed_record_lift_host_boundary_mismatch.do/.expect`

- [x] Build the positive fixture with descriptor
  `demo:marshal-record-managed-lift/api.read@1.0.0/lift`, parse the WAT, and
  validate the exact lift import `(func (param i32))` plus the managed record
  fields.
- [x] Assemble the generated Component and run the existing C15-A host and
  equivalence Rust binaries; require `value=12` and `12/12`.
- [x] Require async and locator mismatch rejection with no WAT artifact.
- [x] Build without the opt-in and require the ARC marker and no private
  canonical import.

### Task 4: Synchronize documentation and verify the repository

**Files:**
- Modify: `CHANGELOG.md`, `doc/start_here.md`, `doc/roadmap_status.md`,
  `doc/pending_blocked.md`, `doc/host_abi_blockers.md`,
  `examples/gc-p3-runtime/README.md`

- [x] Record C16-C as private C15-A lift compiler evidence and keep inventory
  pending rows unchanged.
- [x] Run `cd src && zig test main.zig`, `./src/build/test/run_tests.sh`,
  `cd src && zig build -Doptimize=ReleaseSmall`, release smoke, all focused
  compiler gates, `bash -n`, and `git diff --check`.
