# ARC 03.8.3 Path Cleanup Facts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce the smallest ownership interface for path cleanup facts and release-plan skips without changing current loop move or lowering behavior.

**Architecture:** Keep the change focused on `tool/build/ownership.zig`, then thread the new facts through `tool/build/codegen.zig` as metadata only. The ownership layer will accept explicit `PathCleanupFacts` for local exits and per-frame loop exits, while current codegen callers keep using the same effective behavior by passing empty/default facts.

**Tech Stack:** Zig compiler code, Zig unit tests, Markdown docs.

---

### Task 1: Lock the ownership interface with failing tests

**Files:**
- Modify: `tool/build/ownership.zig`

- [ ] **Step 1: Add a failing test for local-exit path facts**

Add a unit test that builds a return exit plan with explicit cleanup facts:

```zig
const facts = PathCleanupFacts{
    .cleanup_visible = true,
    .release_skip_names = &.{"moved_value"},
};
const plan = try buildReturnExitPlanWithFacts(allocator, locals, facts);
```

The test should assert that `moved_value` is skipped from the generated release steps.

- [ ] **Step 2: Add a failing test for per-frame loop release skips**

Add a unit test that builds a loop-control exit plan from two frames, where the inner frame carries:

```zig
.path_facts = .{
    .cleanup_visible = true,
    .release_skip_names = &.{"inner_skip"},
}
```

The test should assert that `inner_skip` is absent from the flattened loop-control release steps, while non-skipped locals still release in reverse frame/local order.

- [ ] **Step 3: Run the ownership tests and confirm they fail**

Run: `cd tool && zig test build/ownership.zig`
Expected: FAIL because `PathCleanupFacts`, `buildReturnExitPlanWithFacts(...)`, and `LoopFrame.path_facts` do not exist yet.

### Task 2: Implement the minimal facts interface

**Files:**
- Modify: `tool/build/ownership.zig`
- Modify: `tool/build/codegen.zig`

- [ ] **Step 1: Add `PathCleanupFacts` and per-frame facts to ownership**

Introduce:

```zig
pub const PathCleanupFacts = struct {
    cleanup_visible: bool = false,
    release_skip_names: []const []const u8 = &.{},
};
```

Extend `LoopFrame` with default `path_facts: PathCleanupFacts = .{}`.

- [ ] **Step 2: Add facts-based exit-plan builders**

Add new ownership entry points:

```zig
pub fn buildReturnExitPlanWithFacts(...)
pub fn buildGuardReturnExitPlanWithFacts(...)
pub fn buildFallthroughExitPlanWithFacts(...)
pub fn buildBlockExitPlanWithFacts(...)
```

Keep the old wrappers and route them through the new facts-based builders with default facts or `release_skip_names`.

- [ ] **Step 3: Honor per-frame release skips in loop-control planning**

Update `buildLoopControlExitPlan(...)` so each `LoopFrame` contributes `frame.path_facts.release_skip_names` to `appendReverseLocals(...)`.

- [ ] **Step 4: Thread default facts through codegen without behavior change**

Update `tool/build/codegen.zig` to use the new facts-based builders while keeping:

1. existing `skip_names` behavior unchanged,
2. loop-control frames defaulting to empty facts,
3. `allow_call_arg_last_use_move = loop_ctx == null` unchanged.

### Task 3: Sync docs and verify no lowering drift

**Files:**
- Modify: `doc/memory.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`

- [ ] **Step 1: Record 03.8.3 in docs**

Document that path/cleanup facts are now explicit metadata, and that release-plan skip is representable for return/guard-return and per-frame loop control, but loop `arc-call-move` policy is still unchanged.

- [ ] **Step 2: Mark roadmap progress**

Mark `03.8.3` complete with exact verification evidence.

- [ ] **Step 3: Run verification**

Run:

```bash
cd tool && zig test build/ownership.zig
cd tool && zig test build/codegen.zig
SKIP_BUILD=1 ./tool/build/test/run_tests.sh
```

Expected: all pass, with no new loop move output and no syntax/doc churn outside the active ownership phase.
