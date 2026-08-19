# GC Nested Field Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add one bounded Wasm GC synchronous slice for direct one-level nested managed-struct `@get` and `@set` field paths while preserving immutable source values.

**Architecture:** Extend the existing `codegen_gc_sync.zig` expression emitter with a path parser for `@get(root, .child, .leaf)` and `@set(root, .child, .leaf, value)`. The emitter accepts only a direct local root, one managed-struct child, and a scalar or already-admitted managed leaf; `@set` rebuilds the child and then the outer struct from loaded unchanged fields. Unsupported producers, dynamic paths, resources, async, host/WIT bindings, and multi-level paths remain fail-closed.

**Tech Stack:** Zig 0.16, parser-backed GC WAT emitter, existing compiled-test harness, Wasmtime/wasm-tools 1.255.0.

**Spec:** `doc/memory.md` and `doc/superpowers/specs/2026-08-11-gc-backend-architecture-design.md`.

## Global Constraints

- Do not add public `ref<T>`, `own<T>`, `borrow<T>`, `Result<T,E>`, or `Option<T>` syntax.
- Do not mix ARC handles with GC references in an admitted emitted module.
- Keep source value semantics: `@get` reads without mutation and `@set` returns a new logical value while preserving the old root.
- Reject unsupported shapes before WAT emission; never silently route an admitted candidate back to ARC.
- Do not expand async, resource, arbitrary producer, or host/WIT admission in this slice.
- Preserve unrelated dirty worktree changes and do not clean, reset, or push without explicit authorization.

### Task 1: Lock the bounded path contract with failing tests

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`
- Create: `src/build/test/compiled_ok/101_compiled_test_nested_field_path_gc_migration.do`
- Test: `zig test src/build/codegen_gc_sync.zig`

- [x] Add one unit test for `@get(outer, .inner, .value)` that expects the nested `struct.get` chain and currently fails with `UnsupportedGcSyncExpression`.
- [x] Add one unit test for `@set(outer, .inner, .tag, 9)` that expects two `struct.new` operations and currently fails with `UnsupportedGcSyncExpression`.
- [x] Add one negative unit test for a two-level path or call-produced child that remains rejected.
- [x] Run `zig test src/build/codegen_gc_sync.zig` and record the expected RED failures before production changes.

### Task 2: Implement one-level nested get/set lowering

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`

- [x] Parse exactly two field segments after a direct local root and resolve both layouts.
- [x] Emit nested `struct.get` for a leaf read, checking the expected leaf type.
- [x] For a leaf write, emit the new leaf, rebuild the child with all unchanged fields, then rebuild the outer struct with the new child and unchanged fields.
- [x] Accept only scalar leaves and the existing admitted `[u8]`, scalar-list, `text`, managed-struct, or managed-list leaves; reject producers unless they are direct locals/field gets already accepted by the existing emitter.
- [x] Run the focused unit tests and confirm GREEN.

### Task 3: Add compiled behavior and equivalence evidence

**Files:**
- Create: `src/build/test/compiled_ok/101_compiled_test_nested_field_path_gc_migration.do`
- Modify: `src/build/test/compiled_ok/101_compiled_test_nested_field_path_gc_migration.expect`
- Create or modify: `examples/gc-p3-runtime/nested-field-path.do`
- Create or modify: `examples/gc-p3-runtime/test_do_gc_nested_field_path.sh`
- Modify: `src/build/test/check_gc_semantic_equivalence.sh`

- [x] Add a compiled test that observes the old child and updated child after a nested scalar write.
- [x] Generate and pin only behavior-relevant GC expectations; the admitted GC example rejects `__arc_`.
- [x] Add the paired ARC/GC observable comparison and require one passing row.
- [x] Run the new fixture, the equivalence row, and the default GC parse gate.

### Task 4: Synchronize status and run release gates

**Files:**
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/pending_blocked.md`

- [x] Record the bounded one-level path boundary and keep general nested producers pending.
- [x] Run `zig build -Doptimize=ReleaseSmall`, `zig test main.zig`, `./src/build/test/run_tests.sh`, and `git diff --check`.
- [x] Leave the worktree in a verified state without committing or pushing unrelated dirty changes.

## Completion Criteria

1. Direct one-level nested `@get` and scalar-leaf `@set` lower to typed GC WAT.
2. Old outer and child values remain observable after the write.
3. Unsupported paths fail before WAT emission.
4. The compiled fixture, ARC/GC equivalence row, full regression, and parse gate pass.
5. Status docs state this is a bounded slice and do not claim general nested producer or G5c completion.
