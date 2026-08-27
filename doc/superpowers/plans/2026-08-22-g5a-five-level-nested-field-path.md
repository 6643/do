# G5a Five-Level Nested Managed-Struct Field Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one fixed fifth-level direct nested managed-struct `@get/@set` path to the synchronous typed GC route.

**Architecture:** Extend the existing explicit nested-path parser/emitter and
the standalone GC probe with a dedicated five-level shape. The source remains
fail-closed for dynamic producers, deeper paths, async/resource code, and
general aggregate inference.

**Tech Stack:** Zig compiler, `.do` fixtures, Wasm GC WAT, pinned
`wasm-tools 1.255.0`, Wasmtime 47 GC probe, Bash regression gates.

**Spec:** `doc/superpowers/specs/2026-08-22-g5a-five-level-nested-field-path-design.md`

## Global Constraints

- Preserve unrelated dirty-worktree changes; do not reset, checkout, clean, commit, or push in this unit.
- Do not change public syntax, ownership types, host/WIT routing, async/resource lowering, or migration inventory row status.
- Keep all existing one- through five-level paths green and keep unsupported producer/deeper shapes fail-closed.
- Use only `wasm-tools 1.255.0 (76e20611d 2026-07-30)` and the repository's existing Wasmtime GC binary.

---

### Task 1: Add the positive fixture and focused RED test

**Files:**
- Create: `examples/gc-p3-runtime/five-level-nested-field-path.do`
- Create: `src/build/test/compiled_ok/106_compiled_test_five_level_nested_field_path_gc_migration.do`

- [x] Add `Top -> Outer -> Inner -> Middle -> Leaf -> Core` declarations and the exact direct `@set` path from the spec.
- [x] Add a compiled test that preserves the old chain and observes the terminal scalar update.
- [x] Run the existing probe/compiler on the new fixture before production changes and retain the expected `UnsupportedGcSyncProbeSignature`/unsupported lowering failure.

### Task 2: Extend the typed GC parser/emitter minimally

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`

- [x] Add `QuintNestedFieldPath` with five managed field links and one terminal field.
- [x] Parse exactly five managed segments for `@get` and `@set`; reject a sixth segment or non-direct root.
- [x] Emit `struct.get` through all five links and rebuild `Core`, `Leaf`, `Middle`, `Inner`, `Outer`, and `Top` in reverse order, reusing untouched fields and the original payload reference.
- [x] Add focused unit coverage for positive get/set and a sixth-segment/producer negative boundary.

### Task 3: Extend the standalone probe and RED→GREEN verification

**Files:**
- Modify: `src/build/gc_sync_probe.zig`
- Create: `examples/gc-p3-runtime/test_do_gc_five_level_nested_field_path.sh`

- [x] Add the five-level classifier, wrapper, chain-preservation assertions, and focused classifier test.
- [x] Run the focused Zig test and probe; require WAT markers for five links/six constructors and Wasmtime result `27815`.

### Task 4: Close regression/equivalence/docs gates

**Files:**
- Modify: `src/build/test/check_gc_default_build_gate.sh`
- Modify: `src/build/test/check_gc_semantic_equivalence.sh`
- Modify: `src/build/test/check_gc_migration_inventory.sh` only for evidence paths; keep `15/15` status.
- Modify: `examples/gc-p3-runtime/README.md`, `doc/start_here.md`, `doc/roadmap_status.md`, `doc/pending_blocked.md`, `CHANGELOG.md`

- [x] Add the positive fixture and probe to the default/equivalence gates.
- [x] Keep a sixth-level/deeper producer negative assertion outside admission.
- [x] Record that only five-level direct paths are closed; generic nested aggregate and producer work remains pending.

### Task 5: Full verification

- [x] Run `cd src && zig test main.zig`.
- [x] Run `./src/build/test/run_tests.sh`.
- [x] Run `bash src/build/test/check_gc_g5c_residual_gate.sh baseline` and retain the intentional inventory pending exit.
- [x] Run `cd src && zig build -Doptimize=ReleaseSmall`, release smoke, `git diff --check`, and inspect `git status --short`.
