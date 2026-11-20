# GC Nested Field Paths Without a Fixed Depth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lower direct-local nested managed-struct `@get` and `@set` paths at any source-representable depth in the Wasm GC route.

**Architecture:** Replace the fixed arrays in `GenericNestedFieldPath` with compiler-owned variable-length path storage. Preserve the existing iterative validation and emission logic, add GC compiled runtime coverage beyond the old limit, and keep the existing non-goals fail-closed.

**Tech Stack:** Zig 0.16, Do compiler, Wasm GC, Node-based compiled-test runner.

**Spec:** `doc/superpowers/specs/2026-11-20-gc-unbounded-nested-field-path-design.md`

## Global Constraints

- GC is the only runtime route; ARC equivalence is not required.
- The root remains a direct local identifier and the terminal remains an inline Wasm scalar.
- Producer expressions, dynamic field names, aggregate terminals, resource fields, async, and host/WIT remain unsupported.
- Do not modify the frozen G5c inventory or its historical row evidence.

## Review Focus

- Long paths must not overflow a fixed array or recurse on the compiler call stack; exercise 12 managed links.
- Allocation failures or invalid paths must not leak temporary path storage; exercise malformed paths with the testing allocator.
- `@set` must preserve sibling fields and the original value; assert both in compiled GC execution.
- Existing short paths must retain their behavior; retain existing one-to-five-level fixtures and run the full harness.
- The path bound removal must not widen unrelated shapes; keep negative coverage for non-managed intermediates and non-scalar terminals.

### Task 1: Add Dynamic-Depth Unit Tests

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`

**Interfaces:**
- Consumes: `emit_test_source(allocator, source)` and the existing `GenericNestedFieldPath` parser/emitter.
- Produces: tests proving `@get` and `@set` lower paths with 6 and 12 managed links, plus invalid path rejection.

- [ ] **Step 1: Add failing tests**

Add a test-only source builder for a chain of uniquely named managed structs. Assert a 12-link `@get` emits 13 field reads, a 12-link `@set` emits 13 struct constructions, and a missing field returns `UnsupportedGcSyncExpression`.

- [ ] **Step 2: Verify the new depth test fails for the current limit**

Run from `src/`: `zig test build/codegen_gc_sync.zig --test-filter "nested managed scalar paths without a depth cap"`.
Expected: failure from the current five-link guard, not a parse or test-construction error.

### Task 2: Replace Fixed Path Storage

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`

**Interfaces:**
- Consumes: the new tests from Task 1.
- Produces: dynamically sized `layouts` and `managed_fields` in `GenericNestedFieldPath`, with explicit cleanup in both `@get` and `@set` callers.

- [ ] **Step 1: Implement variable-length path storage**

Build path slices as the parser validates each managed edge. Ensure null, error, and successful-return paths release or transfer storage exactly once. Remove `max_nested_managed_segments`; keep parsing and emitters iterative.

- [ ] **Step 2: Run focused tests**

Run from `src/`: `zig test build/codegen_gc_sync.zig --test-filter "nested managed scalar paths without a depth cap"`.
Expected: both 6-link and 12-link cases pass and malformed paths still reject.

### Task 3: Add GC Runtime and Admission Coverage

**Files:**
- Create: `src/build/test/ok/420_unbounded_nested_field_path.do`
- Create: `src/build/test/ok/420_unbounded_nested_field_path.compiled_must_pass`
- Create: `examples/gc-p3-runtime/unbounded-nested-field-path.do`
- Modify: `src/build/test/check_gc_default_build_gate.sh`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/start_here.md`
- Modify: `examples/gc-p3-runtime/README.md`
- Modify: `doc/g5c/evidence/nested_structs.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: dynamic nested path lowering from Task 2.
- Produces: default GC build admission and compiled GC execution coverage for a 12-link update/read path.

- [ ] **Step 1: Add a compiled GC behavior fixture**

Build a 12-link struct chain with distinct sibling scalar fields. The compiled test must verify the deep read, updated terminal value, unchanged sibling values, and unchanged source root.

- [ ] **Step 2: Register the source in the default GC build gate**

Add `unbounded-nested-field-path.do` to the expected fixture list; require successful default build and Core GC validation without ARC markers.

- [ ] **Step 3: Update current status and preserve historical evidence**

Remove the five-level ceiling from current summaries. Mark the existing five-level G5c row evidence as an archived snapshot and state that the new GC-only capability does not change its frozen inventory or equivalence matrix.

- [ ] **Step 4: Run the focused compiled fixture and default admission gate**

Run the single compiled fixture through the harness and `bash src/build/test/check_gc_default_build_gate.sh`.
Expected: the test executes on the GC route and the build gate accepts the 12-link source.

### Task 4: Full Verification

**Files:**
- No additional files.

- [ ] Run `./src/build/test/run_tests.sh`.
- [ ] Run `cd src && zig build --prefix .. -Doptimize=ReleaseSmall` and the repository release smoke command documented by the test harness.
- [ ] Run `git diff --check` and inspect the final diff for unrelated changes.
