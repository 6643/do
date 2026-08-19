# Parser-Backed Record Component Assembly Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove that the parser-backed scalar-record `lift` plan can produce a valid Core module that assembles into a Component without exposing Wasm GC references at the canonical boundary.

**Architecture:** Keep the existing synchronous, measured scalar-record `lift` slice. Add a test-only generator entry that resolves the checked-in WIT source, binds the fixed record layout, and delegates all WAT emission to `emit_sync_marshal_module`; the shell gate then runs the pinned `wasm-tools` assembly sequence. The normal `do build` host/WIT route remains unchanged and ARC-backed.

**Tech Stack:** Zig 0.16, Core Wasm GC WAT, `wasm-tools 1.255.0`, shell regression gates.

**Spec:** `doc/superpowers/specs/2026-08-16-gc-canonical-marshal-plan-design.md`

## Global Constraints

- Only scalar-record result `lift` is admitted: two measured `u32` fields, eight-byte result area, one canonical `i32` pointer parameter.
- No `record lower`, nested/text/list fields, `Option`/`Result`/`Variant`, async, resources, or default compiler-route wiring.
- No `(ref ...)` may occur in canonical import parameter/result types.
- Use only the pinned `wasm-tools 1.255.0`; preserve the dirty worktree and do not revert unrelated changes.

### Task 1: Add a parser-backed WAT generator test entry

**Files:**
- Create: `src/build/gc_marshal_record_probe.zig`
- Create: `src/gc_marshal_record_probe_main.zig`
- Test: `src/build/gc_marshal_record_probe.zig`

- [x] Add a command entry that accepts `<wit-source> <output-wat>` and resolves the fixed `probe/api/read` member through `build_sync_value_plan_from_wit_source`.
- [x] Bind `RecordMeasurement` for `code@0` and `count@4`, then call `emit_sync_marshal_module` with the canonical `demo:marshal-record-assembly/api@1.0.0::read` descriptor.
- [x] Write the emitted WAT without hand-authored module fragments.
- [x] Add unit tests for invalid arguments and for `$do_record`, the one-word lift import, and the absence of `cabi_realloc`.

### Task 2: Add the assembly-only fixture and gate

**Files:**
- Create: `examples/gc-p3-runtime/marshal-record-assembly.wit`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_component.sh`

- [x] Generate a temporary Core WAT from the checked-in WIT with the probe entry.
- [x] Run `wasm-tools parse`, reject GC references in canonical imports, then run `component embed`, `component new`, `validate`, and `component wit`.
- [x] Assert the `read: func() -> reading` surface and the generated canonical import shape.
- [x] Add a negative member-rename check and a synthetic GC-reference import check, matching the existing text assembly gate.

### Task 3: Synchronize evidence and verify

**Files:**
- Modify: `doc/roadmap_status.md`
- Modify: `doc/host_abi_blockers.md`

- [x] Record that parser-backed record Core/WIT assembly is green, while host execution remains covered by the existing hand-authored runner and default-route wiring remains pending.
- [x] Run the focused Zig test, the new assembly gate, `zig test main.zig`, `./src/build/test/run_tests.sh`, the G5c residual baseline gate, and `git diff --check`.
