# Resource Result Buffer Accounting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (recommended) or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Apply the existing checked byte counter to the private resource Result probe's fixed 8-byte canonical result slot.

**Architecture:** Reuse `$async-byte-budget-reserve` and `$async-byte-budget-release` emitted by the frame table allocator. Reserve 8 bytes before the resource result-buffer helper can grow memory, roll back on an impossible grow, and release after both immediate and resumed `task-return` paths before frame cleanup. Keep this as checked accounting, not a configurable quota.

**Tech Stack:** Zig code generation, Core Wasm WAT, Wasm-tools, Rust/Wasmtime resource probe.

## Global Constraints

- Preserve the private resource probe ABI and its existing two-word Result payload.
- Keep reserve-before-memory-mutation and exactly-once terminal release.
- Do not add public ownership syntax, scheduler behavior, or ARC/GC migration.

### Task 1: Add The Failing WAT Contract

- [x] Extend `src/build/codegen_component_resource_async.zig` tests to require
  `[canonical-buffer-bytes] 8`, an 8-byte reserve in
  `$result-buffer-for-handle`, rollback on grow failure, and release after both
  task-return forms.
- [x] Run the focused Zig test and observe failure against the current raw
  `memory.grow` helper.

### Task 2: Implement Resource Slot Accounting

- [x] Import `async_byte_budget.zig`, keep the slot size as one named constant,
  and emit checked metadata from the canonical formula.
- [x] Add reserve/rollback to the helper and a zero-argument release helper.
- [x] Insert release after immediate and resumed `task-return` and before each
  `$frame-free`.

### Task 3: Verify And Record The Boundary

- [x] Run the resource Zig test, component lowering, assembly, and Rust
  Wasmtime resource runner.
- [x] Update `doc/host_abi_blockers.md` and the resource probe README text to
  distinguish checked accounting from a configured quota.

### Task 4: Regression Closure

- [x] Run `bash examples/gc-p3-runtime/test_async_frame_table.sh`.
- [x] Run `./src/build/test/run_tests.sh`, ReleaseSmall build, and
  `git diff --check`.
