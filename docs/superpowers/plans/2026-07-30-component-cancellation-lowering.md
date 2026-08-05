# Component Cancellation Lowering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the experimental Do host-operation cancellation protocol with direct `@cancel(Future<T>)` lowering through the pinned Component async ABI.

**Architecture:** Async descriptors retain only WIT and canonical-call facts. Future cancellation is an affine source operation lowered to the pinned Component subtask cancellation instruction. No host operation ID, acknowledgement, or external-effect protocol is emitted.

**Tech Stack:** Zig, WAT, wasm-tools, Rust Wasmtime Component Model.

## Global Constraints

- Do has no `operation_id`, `CancelledAck`, public `Cancelled` Result branch, pointer, or reference syntax.
- Task cancellation never promises database rollback, HTTP compensation, idempotency, or external-effect reconciliation.
- Exact task/subtask ABI names come from the pinned profile, never inferred from host locator/member text.
- Shared dirty worktree: no reset, clean, stage, commit, or unrelated overwrite.

---

### Task 1: Remove The Custom Cancellation Experiment

**Files:** Modify `src/build/p3_async_registry.json` and `src/build/p3_async_manifest.zig`; delete `src/build/async_operation_broker.zig`, `src/build/async_host_drive.zig`, and `src/build/async_runtime_loop.zig`; modify or delete `src/build/async_guest_scheduler.zig`.

**Produces:** `p3_async_manifest.Descriptor` has no `cancel` field and no `src/build` source imports the removed experiment.

- [x] **Step 1: Write failing manifest tests.** Remove `cancel` from the valid embedded JSON fixture in `p3_async_manifest.zig`. Add a second fixture with `cancel: not-supported` that expects `error.InvalidP3AsyncManifest`.
- [x] **Step 2: Verify red.** Run `cd src && zig test build/p3_async_manifest.zig`. The valid fixture must fail because the parser currently requires `cancel`.
- [x] **Step 3: Implement removal.** Remove cancel parsing, allocation, validation, storage, deallocation, JSON test fields, and registry fields. Add an allowlist that rejects the obsolete key. Delete broker/drive/runtime-loop. Retain `async_guest_scheduler.zig` only if an active compiler import remains after deletion; otherwise delete it.
- [x] **Step 4: Verify green.** Run `cd src && zig test build/p3_async_manifest.zig`; then scan `build` Zig/JSON files for `async_operation_broker`, `async_host_drive`, `async_runtime_loop`, `CancelledAck`, `terminal-ack`, and `not-supported`. Tests pass and the scan is empty.

### Task 2: Emit Direct `@cancel` Lowering

**Files:** Modify `src/build/codegen_p3_wait_for.zig` and `src/build/codegen_pipeline.zig`; create `examples/p3-runtime/cancel-wait-for-component.do` and `examples/p3-runtime/test_do_cancel_wait_for_lowering.sh`.

**Produces:** The opt-in P3 target accepts exactly `async run() -> nil { pending Future<nil> = host_wait_for(1); @cancel(pending) }`. Its WAT contains pinned `[subtask-cancel]` and `call $subtask-cancel`, without custom host names.

- [x] **Step 1: Write the failing fixture and unit assertion.** Add the source fixture. Add a codegen unit test that asserts `[subtask-cancel]`, `call $subtask-cancel`, and absence of `operation_id` and `request_cancel`.
- [x] **Step 2: Verify red.** Run `cd src && zig test build/codegen_p3_wait_for.zig`. The fixed-source matcher must reject the fixture or the call assertion must fail.
- [x] **Step 3: Implement direct lowering.** Extend only the opt-in P3 fixed matcher. The legacy callback ABI uses synchronous `subtask.cancel`; it must observe `RETURN_CANCELLED (4)` before `subtask.drop`, then call `task-return`. Do not add a host call, broker record, operation ID, terminal event, or rollback path.
- [x] **Step 4: Verify assembly.** The new shell test builds with `--p3-wait-for-component`, asserts the direct call and absence of custom names, and runs `wasm-tools component embed`, `component new`, and `validate`. Run `bash examples/p3-runtime/test_do_cancel_wait_for_lowering.sh`.

### Task 3: Execute Standard Cancellation In Wasmtime

**Files:** Create `examples/p3-runtime/cancel-wait-for-component.wit`, `examples/p3-runtime/rust-host-runner/src/bin/cancel_wait_for.rs`, and `examples/p3-runtime/test_rust_cancel_wait_for.sh`; modify `examples/p3-runtime/test.sh`.

**Produces:** A Rust adapter using the pinned Wasmtime Component async API emits three markers: `Rust P3 cancel adapter passed`, `cancel before completion observed`, and `terminal subtask is not completed twice`.

- [x] **Step 1: Write failing shell assertions.** Create the shell script to assemble the Core WAT/WIT pair and require the three markers before the runner exists.
- [x] **Step 2: Verify red.** Run `bash examples/p3-runtime/test_rust_cancel_wait_for.sh`; it must fail because `cancel_wait_for.rs` does not exist.
- [x] **Step 3: Implement only the standard adapter fixture.** Reuse the Wasmtime configuration and compiler-wrapper environment from `cli_result_probe.rs`. Register the pinned async import, leave it pending, and observe standard Component cancellation without second completion. Do not add a broker, acknowledgement, rollback callback, or user-visible cancellation result.
- [x] **Step 4: Verify execution.** Run `bash examples/p3-runtime/test_rust_cancel_wait_for.sh`; all three markers must appear.

### Task 4: Align Documentation And Regression Matrix

**Files:** Modify `doc/host_abi_blockers.md`, `doc/async-design.md`, `doc/spec_rules.md`, `examples/p3-runtime/README.md`, `docs/superpowers/plans/2026-07-29-p3-async-descriptor-manifest.md`, and `docs/superpowers/plans/2026-07-29-host-drive-abi.md`.

**Produces:** Documentation says cancellation follows pinned Component task semantics and makes no external-effect rollback claim.

- [x] **Step 1: Remove obsolete cancellation claims.** Delete claims requiring `CancelledAck`, operation IDs, `terminal-ack`, or per-descriptor cancellation capability. Preserve the explicit non-goal for committed external effects.
- [x] **Step 2: Run the full matrix.** Run `cd src && zig build -Doptimize=ReleaseSmall`; then run `test_do_wait_for_lowering.sh`, `test_do_cancel_wait_for_lowering.sh`, `test_rust_cancel_wait_for.sh`, `test_do_cli_result_lowering.sh`, `./src/build/test/run_tests.sh`, and `git diff --check`. Every command must exit zero. If Wasmtime lacks the needed standard async API, report a toolchain blocker and do not restore a custom fallback.

## Plan Self-Review

- Tasks 1-2 remove the custom model and implement direct ABI lowering.
- Task 3 validates only real Component behavior.
- Task 4 removes stale claims and validates the complete regression surface.
