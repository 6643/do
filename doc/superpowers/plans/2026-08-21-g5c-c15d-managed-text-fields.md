# G5c C15-D Multi-Managed-Text Record Lower Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the private manifest-backed GC/WIT lower route from one `{u32, string}` record to one fixed `{u32, string, string}` record without changing the default ARC-backed host/WIT path.

**Architecture:** Add one hash-pinned descriptor and measured 20-byte record shape. Generalize the existing managed-text lower metadata and WAT emitter to walk direct text children in declaration order, allocate/copy each span, call the flat five-word canonical import, then free both spans after the host call. Keep admission fail-closed and expose the new route only through the existing explicit `--gc-wit-marshal <descriptor-id>` option.

**Tech Stack:** Zig compiler/tests, checked-in WIT manifest, WAT, `wasm-tools 1.255.0`, Rust/Wasmtime host runners, shell gates.

**Spec:** `doc/superpowers/specs/2026-08-21-g5c-c15d-managed-text-fields-design.md`

## Global Constraints

- Admit only `demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower`.
- The exact WIT shape is `writing { code: u32, label: string, note: string }`.
- The measured layout is `code@0`, `label@4..11`, `note@12..19`, total 20 bytes, alignment 4.
- The canonical lower import is `(i32, i32, i32, i32, i32)` in `code, label.ptr, label.len, note.ptr, note.len` order.
- Each managed text field gets one `cabi_realloc(0, 0, 1, length)` and one post-call `cabi_realloc(ptr, length, 1, 0)`.
- No GC reference crosses the canonical import; invalid lengths trap before the host call.
- Unknown ids, source/hash/signature/layout/shape drift, and unsupported forms fail before WAT is returned.
- C15-A/C15-B/C15-C behavior and default `@host` ARC routing remain unchanged.
- Do not add ownership syntax, Option/Result/variant, async/resource lowering, or compatibility fallbacks.
- Preserve unrelated dirty worktree changes; do not reset, clean, or push.

---

### Task 1: Pin the new WIT descriptor and toolchain ABI

**Files:**
- Create: `examples/gc-p3-runtime/marshal-record-managed-lower-multi-manifest-source.wit`
- Create: `doc/wit/gc_marshal_record_managed_lower_multi_imports.wit`
- Modify: `doc/wit/gc_descriptor_manifest.json`
- Test: `src/build/codegen_component_manifest_route_test.zig`

**Interfaces:**
- The source declares package `demo:marshal-record-managed-lower-multi@1.0.0`, interface `api`, record `writing`, and `write(value: writing)`.
- The world fragment declares `world probe { import api; export run: func() -> u32; }`.
- The descriptor records the exact package/world/interface/member/direction, `params: ["writing"]`, `result: "_"`, source SHA-256, and derived canonical import module/name.
- The manifest loader resolves the descriptor to the exact package/world/member and measured source bytes before any marshal plan is built.

- [x] Write the WIT source and package-less world fragment exactly as specified.
- [x] Run the pinned toolchain against a minimal Component assembly to establish the five `i32` lower words and record layout; record the observed output in the manifest route test.
- [x] Compute the manifest hash over `source + newline + world_source + newline`, add the descriptor entry with the resulting `sha256:<64 lowercase hex>` value, and verify it through the existing loader.
- [x] Add a RED route test that requests the descriptor and expects `(type $canonical_lower (func (param i32 i32 i32 i32 i32)))` plus the measured 20-byte facts; run it and retain the `UnsupportedMarshalShape` failure before implementation.

### Task 2: Generalize the memory plan for ordered managed text fields

**Files:**
- Modify: `src/build/codegen_component_marshal_ops.zig`
- Modify: `src/build/codegen_component_marshal_module.zig`
- Test: `src/build/codegen_component_marshal_ops.zig`

**Interfaces:**
- Replace the boolean-only `MemoryPlan.record_managed_text_lower` special case with `ManagedTextField { field_index: u32, pointer_offset: u32, length_offset: u32 }`, stored in `MemoryPlan.managed_text_fields: [2]ManagedTextField` with `managed_text_field_count: u8`.
- Keep `record_field_count`, `record_indirect`, and existing scalar/list/lift behavior unchanged.
- The C15-D plan exposes two managed text fields at indices `1` and `2`; nested records, list fields, indirect layouts, and unsupported text positions remain rejected.

- [x] Add failing unit tests for `{u32,string,string}` asserting two managed fields in indices `1,2`, five canonical words, and deterministic allocation/copy/call/free operation ordering.
- [x] Add failing unit tests proving the existing `{u32,string}` plan still exposes one field and that `{string,u32,string}` and nested/text-list forms remain rejected.
- [x] Run the focused Zig tests and capture the expected unsupported-shape or missing-metadata failures.
- [x] Implement the small ordered metadata structure by walking direct root children; do not add a descriptor-specific planner copy.
- [x] Update module type emission to derive lower parameter words from measured direct children, producing exactly five `i32` words for C15-D while retaining C15-B output.
- [x] Run the focused tests and `zig test main.zig`; all existing tests and new planner tests must pass.

### Task 3: Emit multiple allocation/copy/free sequences

**Files:**
- Modify: `src/build/codegen_component_marshal_wat.zig`
- Test: `src/build/codegen_component_marshal_wat.zig`

**Interfaces:**
- The managed-text lower emitter consumes the ordered metadata from Task 2 and emits distinct locals for each field's GC length, index, and linear pointer.
- It emits canonical arguments as `code`, then each text field's pointer and length in source order.
- It frees spans only after `call $canonical_call`, in reverse declaration order; no cleanup is emitted before the host call.

- [x] Add a failing emitter test asserting two byte-copy loops, two allocation calls, one canonical call, two free calls, and call-before-free ordering.
- [x] Add a failing test that a GC text length larger than its byte array emits a trap path before the canonical call instead of truncating.
- [x] Implement generic direct-field emission helpers for ordered managed text fields and preserve the existing C15-B output behavior.
- [x] Run focused emitter tests and inspect generated WAT for the exact five-parameter call and post-call frees.

### Task 4: Build the standalone C15-D GC probe and toolchain gate

**Files:**
- Create: `src/build/gc_marshal_record_managed_lower_multi_probe.zig`
- Create: `src/gc_marshal_record_managed_lower_multi_probe_main.zig`
- Create: `examples/gc-p3-runtime/marshal-record-managed-lower-multi-assembly.wit`
- Create: `examples/gc-p3-runtime/marshal-record-managed-lower-multi-arc.core.wat`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_host.sh`

**Interfaces:**
- The probe constructs `{code: 7, label: "hello", note: "world"}`, exports `run`, and returns a single `i32` cleanup code whose documented convention is `allocation_count * 16 + free_count`; the expected value for C15-D is `34`.
- The shell gate uses `wasm-tools 1.255.0` and checks Core parse, component embed/new/validate, component WIT, canonical signature, absence of GC references at the import, and call-before-free ordering.
- A mutated source repository fails with `SourceHashMismatch` before WAT output.

- [x] Add the host-gate assertions and run the script to confirm the new descriptor/emitter is not yet admitted.
- [x] Implement the probe by reusing the manifest route and measured `{20,4}` layout; do not invoke a probe main from compiler dispatch.
- [x] Add the checked-in linear-memory ARC reference with the same WIT boundary and cleanup-code convention.
- [x] Run the standalone host gate and verify `code=7`, `label=hello`, `note=world`, `write-calls=1`, `allocations=2`, `frees=2`.

### Task 5: Add Rust/Wasmtime host and ARC/GC equivalence gates

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_managed_lower_multi.rs`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_managed_lower_multi_equivalence.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_equivalence.sh`

**Interfaces:**
- The host callback validates one `writing` record with `code=7`, `label="hello"`, and `note="world"`.
- The host runner rejects wrong field count/types/values, counts exactly one callback, and requires cleanup code `34`, which decodes to two allocations and two frees.
- The equivalence runner executes GC and ARC Components and requires `allocations=2/2`, `frees=2/2`, and `write-calls=1/1`.

- [x] Add the host/equivalence binaries and Cargo targets; run `cargo fmt --check` and the shell gates to expose expected missing-symbol failures.
- [x] Implement strict field validation and exact cleanup-code assertions without changing C15-B runners.
- [x] Run the host and equivalence gates and retain exact output strings in shell assertions.

### Task 6: Admit the descriptor through explicit compiler wiring

**Files:**
- Modify: `src/build/codegen_gc_wit_marshal.zig`
- Modify: `src/build/codegen_component_manifest_route_test.zig`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_equivalence.sh`

**Interfaces:**
- `codegen_gc_wit_marshal.emit_module` accepts the new descriptor only after manifest/probe gates are green and dispatches through the shared manifest route.
- The existing `--gc-wit-marshal <descriptor-id>` flag remains the sole compiler entry point; no new flag or default inference is added.
- `src/build/run.zig` and CLI parsing remain unchanged because the existing descriptor option is already threaded through the compiler entry point.
- Unknown descriptors and shape/hash/layout drift return named errors with no WAT slice.

- [x] Add RED adapter tests for the new id's five-word marker and for an unknown id producing `UnsupportedGcWitMarshalDescriptor` with no output.
- [x] Add the new descriptor adapter with measured root `{20,4}` facts and a `run` export that constructs the three-field GC record.
- [x] Run both compiler-output scripts from real `do build` output and assert `wasm-tools 1.255.0`, host output, and ARC/GC equivalence.
- [x] Re-run the existing C15-C compiler host/equivalence scripts to prove the prior descriptor remains unchanged.

### Task 7: Synchronize documentation and complete regression gates

**Files:**
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `examples/gc-p3-runtime/README.md`
- Modify: `CHANGELOG.md`
- Modify: this plan file

**Interfaces:**
- Documentation records C15-D as private, explicit, single-descriptor evidence and keeps general managed records, default host/WIT routing, async/resource lowering, and G5c cutover pending.
- The migration inventory records the new independent evidence but does not mark the general `host_wit_marshalling` or G5c rows complete.

- [x] Add exact descriptor, command, measured layout, host output, equivalence output, and non-goal boundary to each relevant document.
- [x] Run `zig test main.zig` from `src`.
- [x] Run `./src/build/test/run_tests.sh`.
- [x] Run `zig build -Doptimize=ReleaseSmall` from `src`.
- [x] Run `cargo fmt --check --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml`.
- [x] Run `git diff --check`, `bash src/build/test/check_gc_g5c_residual_gate.sh baseline`, and `bash src/build/test/check_gc_migration_inventory.sh`; preserve the inventory's expected pending exit status.
- [x] Review `git diff --stat` and `git status --short --branch`; ensure unrelated dirty changes remain untouched.

## Phase Gate

C15-D is complete only when every checkbox is checked, the standalone and real-compiler host/equivalence gates pass, all default regressions are green, and documentation preserves the private opt-in boundary. A probe-only pass is insufficient.
