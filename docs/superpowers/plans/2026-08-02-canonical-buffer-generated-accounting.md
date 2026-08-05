# Generated Canonical Buffer Accounting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (recommended) or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make generated HTTP result-buffer allocation consume and release the existing instance-local byte counter without claiming a configurable runtime quota.

**Architecture:** Reuse the checked `$async-byte-budget-reserve` and `$async-byte-budget-release` helpers emitted with the async frame table. The fixed 64-byte HTTP result slot is reserved before any `memory.grow`, released on the common terminal path after `task-return`, and released before an impossible grow traps. No source-level ownership syntax or ARC/GC backend switch is introduced.

**Tech Stack:** Zig code generation, Core Wasm WAT, Wasmtime component probes, existing Rust HTTP runners.

## Global Constraints

- Keep the current dirty worktree; do not reset, clean, commit, or push.
- Preserve the existing 64-byte canonical result slot formula and frame accounting.
- Reserve before memory mutation; release exactly once after task-return has consumed the result.
- Do not introduce a configurable quota, scheduler policy, or public `own<T>`/`borrow<T>`/`ref<T>` syntax.
- Keep ordinary `do build` async guards and all unsupported HTTP shapes unchanged.

### Task 1: Lock The Generated WAT Contract

**Files:**
- Modify: `src/build/codegen_component_wasi_http.zig`
- Test: `src/build/codegen_component_wasi_http.zig`

- [x] Add a focused failing assertion for generated HTTP WAT requiring:
  `i64.const 64` followed by `$async-byte-budget-reserve` in
  `$result-buffer-for-handle`, a release before its grow-failure trap, and a
  `$canonical-buffer-release` call after `$task-return` and before `$frame-free`.
- [x] Run `cd src && zig test build/codegen_component_wasi_http.zig` and confirm
  the assertion fails because only metadata is emitted today.

### Task 2: Add Canonical Reservation And Release

**Files:**
- Modify: `src/build/codegen_component_wasi_http.zig`

- [x] Reserve the fixed `http_result_buffer_slot_bytes` in the shared result
  buffer helper before testing/growing memory.
- [x] Release the reservation before `unreachable` when `memory.grow` returns
  `-1`.
- [x] Add one `$canonical-buffer-release` helper and invoke it on the shared
  HTTP terminal path after each `task-return` branch and before `$frame-free`.

### Task 3: Verify The Narrow Runtime Boundary

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `examples/gc-p3-runtime/README.md`

- [x] Run the HTTP focused Zig test and all HTTP lowering/runtime scripts that
  use the shared service template.
- [x] Update the boundary text to say generated HTTP result slots now use the
  checked counter, while the counter is still unconfigured and non-HTTP
  canonical allocations remain outside the gate.

### Task 4: Regression Closure

- [x] Run `bash examples/gc-p3-runtime/test_async_frame_table.sh`.
- [x] Run `./src/build/test/run_tests.sh`.
- [x] Run `cd src && zig build -Doptimize=ReleaseSmall`.
- [x] Run `git diff --check` and inspect generated WAT ordering before reporting.
