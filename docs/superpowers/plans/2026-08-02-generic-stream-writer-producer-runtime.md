# Generic Stream-Writer Producer Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate the bounded guest `StreamWriter<u8>` producer pump through the registered private `do:stream-probe` descriptor.

**Architecture:** Reuse the existing writer emitter and Rust host implementation, adding only a custom descriptor producer fixture and a runner variant that selects its sink/export names. Keep stdout producer behavior unchanged.

**Tech Stack:** Zig compiler/WAT, pinned `wasm-tools 1.254.0`, Rust/Wasmtime `47.0.2`.

## Global Constraints

- No public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Only two literal `u8` writes, capacity one, one close, and one host transfer.
- No dynamic producer loop, arbitrary element layout, or payload-bearing producer error.
- Preserve existing stdout producer and all unrelated dirty-worktree changes.

### Task 1: TDD Fixture And Lowering Gate

- [x] Add the custom producer Do source, exact WIT sidecar, and lowering script.
- [x] Add emitter assertions and run them red before the fixture is registered/accepted.

### Task 2: Runtime Adapter

- [x] Add a custom sink/export variant to `cli_stream_stdout.rs` without duplicating the runner state machine.
- [x] Run pending/ready/error through the custom component; scheduler coverage remains the existing stdout gate.

### Task 3: Closure

- [x] Keep stdout producer and descriptor writer probes green.
- [x] Run full regression, ReleaseSmall smoke, `git diff --check`, and the custom runtime gate.
- [x] Document the custom producer evidence and the validator-backed borrowed-field boundary.
