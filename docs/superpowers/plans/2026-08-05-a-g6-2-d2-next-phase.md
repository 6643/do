# A + G6.2 + D2 Next Phase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute the approved next phase as three independently testable sub-projects: Result policy closure, one bounded G6.2 variant shape, and D2 real host smoke.

**Architecture:** A is the source/ABI policy checkpoint. G6.2 extends the descriptor-driven async compiler only after a measured canonical probe. D2 consumes already generated Components through separate local-resource runners and never introduces compiler special cases to make a smoke test pass.

**Tech Stack:** Zig 0.16.0, Do compiler, WAT, `wasm-tools` 1.254.0, Rust 1.97.1, Wasmtime 47.0.2.

## Global Constraints

- Preserve the dirty worktree; do not stage, commit, reset, clean, or push.
- Ordinary Do results use `T | E`; private WIT/Component probes may use `Result<T,E>`.
- Every new G6.2 shape needs a design, pinned probe, registry entry, positive/negative Do fixture, Component gate, and Rust/Wasmtime cleanup matrix.
- D2 uses one Component/Store drive loop and local temporary resources only.
- No public `own<T>`, `borrow<T>`, `ref<T>`, generic scheduler, or complete-WASI claim.

## Plan Map

| Order | Plan | Independent deliverable |
| --- | --- | --- |
| 1 | [Result policy closure](2026-08-05-result-policy-closure.md) | Public/private Result boundary and regression checkpoint |
| 2 | [G6.2 variant resource stream](2026-08-05-g6-2-variant-resource-stream.md) | Registered private variant stream lowering and runtime matrix |
| 3 | [D2 real host runtime smoke](2026-08-05-d2-real-host-runtime-smoke.md) | Real local filesystem/stream smoke with explicit socket/HTTP residuals |

## Dependency and Execution Rules

1. Run Result Task 1 before changing any public signature or registry descriptor.
2. G6.2 Task 1 may start after the Result source policy is confirmed, but registry admission waits for its canonical probe and manifest tests.
3. D2 Task 1 may run in parallel with G6.2 implementation because it is an inventory-only task. D2 real runners must consume only targets already accepted by `codegen_component_async.zig`.
4. Do not combine G6.2 emitter changes with D2 runner changes in one implementation task.
5. After each sub-plan, update `doc/start_here.md`, `doc/pending_blocked.md`, `doc/roadmap_status.md`, and `doc/master_plan.md` only with verified evidence.

## Cross-Project Verification

After all selected tasks are green, run:

```bash
cd src && zig test main.zig
cd ../
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

Expected result: no regression in existing Result/WASI/async gates; any unsupported G6.2 shape or D2 resource remains an explicit pending row rather than an inferred completion claim.

## Handoff

Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` when implementing the three sub-plans. Start with the Result policy closure plan, then review its gate before enabling the G6.2 descriptor. D2 can execute its inventory and admitted filesystem/stream tasks independently, but its roadmap closeout must use the cross-project verification above.
