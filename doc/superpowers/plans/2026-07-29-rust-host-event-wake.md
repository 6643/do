# Rust Host Event Wake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove one Wasmtime Rust async `wait-for` invocation parks and resumes from a host-originated wake event.

**Architecture:** The first host Future poll waits on a one-shot completion and returns `Pending`. The host callback uses `Accessor::spawn` to enqueue a completion task in the same Store event loop; that task records the wake and resolves the one-shot. The test script requires a new exact marker.

**Tech Stack:** Rust 1.97, Wasmtime 47.0.2 component-model-async, futures 0.3, Bash.

## Global Constraints

- Keep one Store, the existing WIT fixture, and `func_wrap_concurrent`.
- Do not alter Zig compiler code, Component ABI, cancellation, or resources.
- The existing `AsyncLoweringUnavailable` gate remains unchanged.

---

### Task 1: Observable External Wake

**Files:**
- Modify: `examples/p3-runtime/test_rust_wait_for.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/main.rs`
- Modify: `examples/p3-runtime/README.md`
- Modify: `doc/host_abi_blockers.md`

**Interfaces:**
- Produces runner marker `wait-for external-wakes=1`.
- Extends `Stats` with `external_wakes: u32`.

- [x] **Step 1: Write the failing shell assertion**

Add a `case` requiring `wait-for external-wakes=1` after the existing pending
poll marker assertion.

- [x] **Step 2: Verify red state**

Run `examples/p3-runtime/test_rust_wait_for.sh`.
Expected: fail with `missing wait-for external-wakes marker` because the runner
does not emit it.

- [x] **Step 3: Implement the host event wake**

Replace `cx.waker().wake_by_ref()` in `WaitFor::poll` with a one-shot receiver.
Use `Accessor::spawn` to enqueue `HostWake`, which increments
`Stats.external_wakes` and resolves the sender in the Store event loop. Print
the external-wakes marker only after the one-call/one-pending/one-completion
assertion also checks that counter.

- [x] **Step 4: Verify green**

Run `examples/p3-runtime/test_rust_wait_for.sh`.
Expected: exit 0 after the runner proves one host-originated wake.

- [x] **Step 5: Document the boundary**

State that the wake is a small embedder event-loop probe, not Zig scheduler
integration or compiler async lowering.
