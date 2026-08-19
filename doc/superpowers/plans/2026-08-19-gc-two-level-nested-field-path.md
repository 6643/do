# GC Two-Level Nested Field Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Admit a bounded two-level managed-struct field path in synchronous typed-GC lowering with compiled and Wasmtime evidence.

**Architecture:** Add an exact-depth parser and a small field-chain emitter beside the existing one-level path. Rebuild nested structs from the deepest parent outward, reusing unchanged GC references. Keep the existing fail-closed one-level and unsupported-producer boundaries.

**Tech Stack:** Zig compiler, WAT GC structs, `wasm-tools 1.255.0`, Wasmtime GC, shell regression probes.

**Spec:** `doc/design/2026-08-19-gc-two-level-nested-field-path.md`

## Global Constraints

- Only the direct-local, two-managed-segment synchronous shape is admitted.
- No ARC compatibility markers may be emitted on the admitted path.
- Existing user changes and unrelated dirty files must remain untouched.
- Every production change is preceded by a test that fails for the missing behavior.

### Task 1: Lock the missing behavior with RED unit tests

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`

**Interfaces:**
- Consumes: current `@get`/`@set` nested-path parser and typed GC struct layouts.
- Produces: failing tests for deep read/write and a preserved deeper-path guard.

- [x] **Step 1: Add a deep scalar write test**

Add a `Leaf`, `Inner`, and `Outer` source where `@set(outer, .inner, .leaf, .value, 9)` is expected to emit `struct.new` for all three layouts and no `__arc_` marker.

- [x] **Step 2: Add a deep managed-field read test**

Return `[u8]` from `@get(outer, .inner, .leaf, .value)` and assert the three chained `struct.get` operations.

- [x] **Step 3: Run the focused test and verify RED**

Run `cd src && zig test build/codegen_gc_sync.zig`. Expected: the two new tests fail with the current unsupported-path error; existing tests remain green.

### Task 2: Implement exact two-level path lowering

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`

**Interfaces:**
- Consumes: direct-local root and two intermediate `gc_managed` struct fields.
- Produces: typed GC WAT for exact three-segment field paths.

- [x] **Step 1: Add an exact-depth path record and parser**

Resolve `root -> first managed field -> second managed field -> leaf` and keep optional setter value bounds. Return `null` for other arities so existing one-level parsing and fail-closed errors remain authoritative.

- [x] **Step 2: Add a chained field loader**

Emit `local.get`, `ref.as_non_null`, and `struct.get` for each layout/field pair in declaration order.

- [x] **Step 3: Add deep getter lowering**

Check the expected leaf type, follow the three field segments, and return the leaf type.

- [x] **Step 4: Add deep setter rebuilding**

Require an inline scalar leaf; rebuild `Leaf`, then `Inner`, then `Outer`, substituting only the changed child and loading all other fields through the original chain.

- [x] **Step 5: Run focused tests and refactor only after GREEN**

Run `cd src && zig test build/codegen_gc_sync.zig` and confirm all tests pass with no ARC marker in the deep output.

### Task 3: Add runtime and compiled evidence

**Files:**
- Create: `examples/gc-p3-runtime/two-level-nested-field-path.do`
- Create: `examples/gc-p3-runtime/test_do_gc_two_level_nested_field_path.sh`
- Create: `src/build/test/compiled_ok/102_compiled_test_two_level_nested_field_path_gc_migration.do`
- Create: `src/build/test/compiled_ok/102_compiled_test_two_level_nested_field_path_gc_migration.expect`
- Modify: `src/build/test/check_gc_semantic_equivalence.sh`

**Interfaces:**
- Consumes: deep typed-GC lowering from Task 2.
- Produces: Wasmtime result `27815`, compiled old/new observation, and one ARC/GC equivalence row.

- [x] **Step 1: Add the GC runtime fixture and probe**

Use nested `Leaf`/`Inner`/`Outer` values with an unchanged byte-list field and a changed scalar leaf; compile with `gc_sync_probe.zig`, parse with `wasm-tools`, run with Wasmtime `-W gc=y`, and require result `27815`.

- [x] **Step 2: Add the compiled fixture and expectation**

Observe the original deep scalar and byte-list length plus the rewritten scalar and outer tag, and require the deep `struct.get`/`struct.new` markers.

- [x] **Step 3: Register the equivalence row**

Run the existing ARC/GC comparison for the fixture and require identical output.

### Task 4: Synchronize inventory and release gates

**Files:**
- Modify: `doc/memory.md`
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/pending_blocked.md`

**Interfaces:**
- Consumes: verified unit, compiled, probe, equivalence, and full-regression evidence.
- Produces: an accurate bounded two-level nested-path status without claiming general nested aggregate or G5c completion.

- [x] **Step 1: Update the boundary text and counts**

Record the new admitted path and retain deeper paths, arbitrary producers, async/resource, and host/WIT rows as pending.

- [x] **Step 2: Run all required gates**

Run `cd src && zig build -Doptimize=ReleaseSmall`, `cd src && zig test main.zig`, `cd src && zig test build/codegen_gc_sync.zig`, `./src/build/test/run_tests.sh`, the focused GC probe/equivalence scripts, `bash src/build/test/check_gc_migration_inventory.sh`, and `git diff --check`.

- [x] **Step 3: Record only verified outcomes**

Leave unrelated user changes untouched and report any unavailable external gate as unverified with its exact failure.

## Completion Criteria

1. Exact two-level nested `@get` and scalar-leaf `@set` emit valid typed-GC WAT.
2. The original deep child and rewritten deep child are both observable.
3. Deeper paths and unsupported producers still fail closed.
4. Focused, compiled, Wasmtime, equivalence, and full regression gates pass; the inventory gate reports the unchanged global G5c residual (`14` pending rows) without evidence drift.
5. Documentation describes the bounded slice and does not claim full GC cutover.
