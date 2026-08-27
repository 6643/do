# G5c C16-D Managed Lift Multi Compiler Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or superpowers:subagent-driven-development) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the private compiler route for the measured `Reading { code: u32, label: text, note: text }` lift descriptor.

**Architecture:** Extend the fixed descriptor table and reuse the existing manifest-backed record-lift emitter. The only new runtime shape is the measured 20-byte result area; no generic aggregate inference or default route change is introduced.

**Tech Stack:** Zig compiler, Do fixtures, pinned `wasm-tools 1.255.0`, Rust/Wasmtime host runners, Bash gates.

**Spec:** `doc/superpowers/specs/2026-08-21-g5c-c16d-managed-lift-multi-compiler-boundary-design.md`

## Global Constraints

- Keep `--gc-wit-marshal` explicit and fail-closed.
- Preserve the existing C15-B, C15-D, and C16-C output paths.
- Keep ordinary `@host_func` compilation ARC-backed.
- Do not change the 15-row migration inventory.
- Do not add `own<T>`, `borrow<T>`, `ref<T>`, generic aggregate lowering, async/resource lowering, or compatibility branches.

### Task 1: Add the exact source and RED tests

**Files:**
- Create: `src/build/test/compile_ok/581_gc_wit_managed_record_lift_multi_host_boundary.do`
- Create: `src/build/test/compile_err/582_gc_wit_managed_record_lift_multi_host_boundary_async.do`
- Create: `src/build/test/compile_err/582_gc_wit_managed_record_lift_multi_host_boundary_async.expect`
- Create: `src/build/test/compile_err/583_gc_wit_managed_record_lift_multi_host_boundary_mismatch.do`
- Create: `src/build/test/compile_err/583_gc_wit_managed_record_lift_multi_host_boundary_mismatch.expect`
- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/codegen_gc_wit_marshal.zig`

- [x] Add the exact three-field `read`/`Reading` fixture and matching negative fixtures.
- [x] Add focused validator and emitter tests for descriptor `demo:marshal-record-managed-lift-multi/api.read@1.0.0/lift`.
- [x] Run `cd src && zig test main.zig --test-filter 'C16-D'` and confirm the missing descriptor support fails.

### Task 2: Implement the fixed descriptor and 20-byte lift route

**Files:**
- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/codegen_gc_wit_marshal.zig`
- Modify: `doc/wit/gc_descriptor_manifest.json`
- Create: `examples/gc-p3-runtime/marshal-record-managed-lift-multi-manifest-source.wit`
- Create: `doc/wit/gc_marshal_record_managed_lift_multi_imports.wit`
- Create: `examples/gc-p3-runtime/marshal-record-managed-lift-multi-assembly.wit`

- [x] Add the lift descriptor-specific ordered field table and allow zero-parameter `Reading` validation.
- [x] Add the manifest-backed 20-byte measurement and typed `$run` wrapper that returns `17` for `7`, `hello`, and `world`.
- [x] Add the manifest entry with the concatenated source hash and canonical `read` import.
- [x] Run the focused C16-D tests and verify the new route is green while existing lower/lift focused tests remain green.

### Task 3: Add host, equivalence, and fail-closed compiler gates

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_managed_lift_multi.rs`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_managed_lift_multi_host_equivalence.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_multi_compiler_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_multi_compiler_equivalence.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_multi_compiler_boundary_negative.sh`

- [x] Require the exact canonical lift import, three managed text fields, no GC reference import, Component validation, and host output `value=17`.
- [x] Compare generated GC and ARC Components and require `17/17`.
- [x] Require async and locator mismatch rejection before WAT and default ARC routing without opt-in.
- [x] Run `bash -n` on all new gates and execute each gate with the pinned toolchain.

### Task 4: Synchronize docs and run repository verification

**Files:**
- Modify: `CHANGELOG.md`, `doc/start_here.md`, `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/host_abi_blockers.md`, `examples/gc-p3-runtime/README.md`
- Modify: this plan file

- [x] Record C16-D as private evidence and keep general aggregate/default host/WIT/async/resource/ownership boundaries pending.
- [x] Mark all plan checkboxes after their commands pass.
- [x] Run `cd src && zig test main.zig`, `./src/build/test/run_tests.sh`, `cd src && zig build -Doptimize=ReleaseSmall`, `./src/build/test/run_release_smoke.sh`, `git diff --check`, `bash -n`, and the migration inventory check through `bash`.
