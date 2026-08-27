# G5a Generic Nested Managed-Struct Field Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace duplicated one- through five-level nested managed-struct GC
path code with one fixed-capacity internal representation while preserving the
current five-level admission boundary.

**Architecture:** Parse direct nested paths into one value record containing a
root, a bounded array of managed layouts/fields, and a scalar terminal. Emit
`@get` and `@set` from loops over that record. The record capacity remains five
managed links; depth six and all other unsupported shapes stay fail-closed.

**Tech Stack:** Zig compiler, existing `.do` fixtures, Wasm GC WAT, pinned
`wasm-tools 1.255.0`, Wasmtime 47 GC probes, Bash regression gates.

**Spec:** `doc/superpowers/specs/2026-08-22-g5a-generic-nested-field-path-design.md`

## Global Constraints

- Preserve all unrelated dirty-worktree changes; do not reset, checkout,
  clean, commit, or push in this unit.
- Do not change public syntax, ownership types, host/WIT routing,
  async/resource lowering, or migration inventory row status.
- Keep one- through five-level direct paths green and keep the sixth-level,
  producer, dynamic, and non-scalar boundaries fail-closed.
- Use only the pinned `wasm-tools 1.255.0 (76e20611d 2026-07-30)` and the
  repository's existing Wasmtime GC binary.

---

### Task 1: Lock the generic path contract with focused tests

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`
- Use existing: `src/build/test/compiled_ok/106_compiled_test_five_level_nested_field_path_gc_migration.do`

- [x] Add a fixed-capacity generic path record and focused helper-level tests
  that prove one-level and five-level paths can represent their layouts and
  terminal fields without allocation.
- [x] Keep the existing sixth-level negative test and require
  `error.UnsupportedGcSyncExpression`.
- [x] Run `cd src && zig test build/codegen_gc_sync.zig` before replacing the
  production dispatch; the new focused test must be the only expected change.

### Task 2: Replace duplicated parser branches

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`

- [x] Implement one loop-based parser for `@get` and `@set` using the generic
  record; validate direct root, managed intermediate fields, registered child
  layouts, scalar terminal, and exact value arity.
- [x] Preserve the existing direct managed-field fallback by returning `null`
  when the path has no nested managed link.
- [x] Reject a sixth managed link before constructing WAT and keep existing
  error categories for producer, resource, and malformed paths.
- [x] Route both `emit_get_field_expr` and `emit_set_field_expr` through the
  new parser, then remove only the five duplicated path records/parsers and
  their dispatch branches.

### Task 3: Replace duplicated emit/rebuild branches

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`

- [x] Add a generic terminal-chain emitter for `@get` that emits one load/get
  pair per managed link and one terminal scalar get.
- [x] Add a generic terminal-to-root rebuild loop for `@set`; for each layout,
  preserve declaration order, replace only the selected child/value, emit one
  `struct.new`, and store non-root rebuilt children in the existing temporary
  locals.
- [x] Keep the original root payload and every untouched field observable.
- [x] Run `cd src && zig test build/codegen_gc_sync.zig` and inspect the WAT
  markers for the existing one- and five-level tests.

### Task 4: Preserve probe and regression gates

**Files:**
- Modify only if needed: `src/build/gc_sync_probe.zig`,
  `src/build/test/check_gc_default_build_gate.sh`,
  `src/build/test/check_gc_semantic_equivalence.sh`,
  `src/build/test/check_gc_g5c_residual_gate.sh`
- Do not add a sixth-level positive fixture.

- [x] Run the existing one-, two-, three-, four-, and five-level GC probes;
  require the same `27815` oracle and chain-preservation checks.
- [x] Run the existing sixth-level negative probe/test and confirm it remains
  rejected before WAT.
- [x] Keep the default fixture count, equivalence row count, and inventory
  status unchanged; update no gate unless the refactor requires a path name.

### Task 5: Documentation and full verification

**Files:**
- Modify: `doc/start_here.md`, `doc/roadmap_status.md`,
  `doc/pending_blocked.md`, `CHANGELOG.md`

- [x] Record that the implementation now uses a generic internal path record,
  while only one through five managed links are admitted.
- [x] Record that sixth/deeper paths, producer expressions, async/resource,
  general host/WIT lowering, and G5c full cutover remain pending.
- [x] Run `cd src && zig test main.zig`.
- [x] Run `./src/build/test/run_tests.sh`.
- [x] Run `cd src && zig build -Doptimize=ReleaseSmall` and
  `./src/build/test/run_release_smoke.sh`.
- [x] Run `bash src/build/test/check_gc_g5c_residual_gate.sh baseline` and
  retain the intentional inventory pending status.
- [x] Run `git diff --check` and inspect `git status --short` without cleaning
  or reverting unrelated changes.
