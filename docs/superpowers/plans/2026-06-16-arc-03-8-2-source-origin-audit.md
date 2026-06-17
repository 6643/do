# ARC 03.8.2 Source Origin Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Audit and attach explicit `SourceOrigin` metadata to existing managed move-candidate helpers without changing current lowering behavior.

**Architecture:** Keep the change local to `tool/build/codegen.zig` and `doc/memory.md`. Extend the move-candidate helper result so each current candidate carries its observed origin, then add focused Zig tests that prove the metadata is preserved while existing `arc-call-move` and `field-get-move` behavior stays unchanged.

**Tech Stack:** Zig compiler code, Zig unit tests, Markdown docs.

---

### Task 1: Extend move-candidate metadata in codegen

**Files:**
- Modify: `tool/build/codegen.zig`

- [x] **Step 1: Write a failing Zig test for move-candidate origin**

Add a unit test near the existing `SourceOrigin` test that exercises one direct local move candidate and one field-read move candidate, and checks their returned origin values.

```zig
test "move candidates carry source origin metadata" {
    // direct local candidate should report param_or_import
    // field-get candidate should report fresh_local for fresh struct literal source
}
```

- [x] **Step 2: Run the Zig test and confirm it fails for the right reason**

Run: `cd tool && zig test build/codegen.zig`
Expected: FAIL because `LastUseManagedMoveSource` does not yet expose origin metadata.

- [x] **Step 3: Implement minimal metadata propagation**

Update `LastUseManagedMoveSource` to include `origin: SourceOrigin`, then thread origin through:
- `directManagedLastUseMoveSource(...)`
- `directManagedCallLastUseMoveSource(...)`
- `directManagedUnionBindingCallMoveSource(...)`
- `fieldGetLastUseMoveSource(...)`

Keep current move allow/reject logic unchanged. Do not change emitted WAT comments or zeroing behavior.

- [x] **Step 4: Run the Zig test again**

Run: `cd tool && zig test build/codegen.zig`
Expected: PASS, with the new test proving candidate origins are attached.

### Task 2: Record the 03.8.2 evidence in docs

**Files:**
- Modify: `doc/memory.md`
- Modify: `doc/roadmap_status.md`

- [x] **Step 1: Update memory doc with 03.8.2 outcome**

Add a short subsection after 8.10 stating that current move-candidate helpers now carry explicit `SourceOrigin`, and list the audited candidate families:
- direct local move candidate
- direct call-arg move candidate
- union-binding call move candidate
- field-get move candidate

Also state explicitly that this step still does not change lowering or loop-move policy.

- [x] **Step 2: Mark 03.8.2 complete in roadmap**

Change the 03.8.2 checkbox to done and append exact verification evidence:
- `cd tool && zig test build/codegen.zig`
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

- [x] **Step 3: Diff-check doc scope**

Run: `git diff -- doc/memory.md doc/roadmap_status.md`
Expected: only 03.8.2 status/evidence updates, no 03.8.3 design work.

### Task 3: Regress behavior and keep output stable

**Files:**
- Verify: `tool/build/codegen.zig`
- Verify: `tool/build/test/run_tests.sh`

- [x] **Step 1: Run compiler unit tests**

Run: `cd tool && zig test build/codegen.zig`
Expected: PASS.

- [x] **Step 2: Run integration regression without rebuild**

Run: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`
Expected: PASS with no lowering drift; the summary should stay at or above the current green baseline recorded in `doc/roadmap_status.md`.

- [x] **Step 3: Final scope check**

Run: `git diff -- tool/build/codegen.zig doc/memory.md doc/roadmap_status.md`
Expected: only 03.8.2 source-origin audit changes; no `ownership.zig` edits, no new loop `arc-call-move`, no syntax/doc churn outside the active phase.
