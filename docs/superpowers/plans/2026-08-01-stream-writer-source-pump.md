# Stream Writer Source Pump Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Generalize the pinned `stream<u8>` guest producer to a bounded source-level sequence while preserving descriptor-driven ABI and explicit rejection boundaries.

**Architecture:** Keep `p3_async_manifest` as the ABI source of truth. Extend `StreamWriterPlan` to carry an ordered bounded `u8` source sequence; emit the sequence through one frame-owned resumable pump. The pump treats `Blocked`, `Completed`, and `Dropped` as distinct states and owns endpoint cleanup exactly once.

**Tech Stack:** Zig compiler, WAT Component async lowering, Rust/Wasmtime 47.0.2 fixtures, existing shell regression harness.

## Global Constraints

- Only the registered `wasi:cli/stdout.write-via-stream` `stream<u8>` descriptor is admitted.
- Ordinary `do build` continues to return `AsyncLoweringUnavailable` for async programs.
- No arbitrary payload, dynamic iteration, external writable endpoint, or public ownership/reference syntax is added.
- Production changes require a red test before implementation and focused plus full verification.
- Preserve the dirty worktree; do not reset, clean, stage, or commit unrelated files.

---

### Task 1: Ordered Source Plan

**Files:**
- Modify: `src/build/codegen_component_async_plan.zig`
- Test: `src/build/codegen_component_async_plan.zig`
- Create: `src/build/test/check/395_stream_writer_source_sequence.do`

**Interfaces:**
- `StreamWriterPlan.producer_values` remains the bounded source representation.
- `StreamWriterPlan.analyze` must preserve source order and reject a sequence that exceeds `max_guest_producer_writes`.

- [x] **Step 1: Add the red plan test.**

Add a fixture with three bound `u8` values and three awaited `writer(value)`
operations. Assert the plan reports `producer_write_count == 3` and values
`[65, 66, 67]`; the bounded source check fixture covers the same source shape
and the plan unit test rejects an over-limit token sequence with
`UnsupportedP3StreamWriterComponent`.

- [x] **Step 2: Run the focused test and confirm the missing behavior.**

Run:

```bash
cd src && zig test build/codegen_component_async_plan.zig
```

The ordered-sequence assertion was observed red before the plan/emitter change;
the focused plan suite is now green.

- [x] **Step 3: Implement the minimal plan capture.**

Use the existing `GuestU8ValueBinding` and `GuestWriteBinding` scanners to walk
the complete linear body, append each value once, and require an await binding
for every write. Return the existing unsupported error for missing awaits,
non-`u8` values, control flow, or overflow.

- [x] **Step 4: Verify the plan.**

Run the focused Zig test and the source check fixture. Confirm the public
descriptor and endpoint mode are unchanged.

### Task 2: Frame Pump State Contract

**Files:**
- Modify: `src/build/codegen_component_stream_writer.zig`
- Test: `src/build/codegen_component_stream_writer.zig`

**Interfaces:**
- `$writer-pump-step(frame)` advances one source index and returns the existing
  waitable-set callback code.
- Frame initialization covers queue head/count/capacity, pending producer,
  terminal/error, pending pointer/length, and producer index.

- [x] **Step 1: Add red WAT assertions.**

Require generated guest-producer WAT to contain the ordered data segment,
explicit initialization markers for every queue field, one pump helper, and no
second direct hard-coded write call.

- [x] **Step 2: Run the emitter test to observe the red state.**

Run:

```bash
cd src && zig test build/codegen_component_stream_writer.zig
```

- [x] **Step 3: Emit the source sequence and state transitions.**

Keep the data segment indexed by the frame producer index. On `stream-write`
return `0`, advance the index; on `-1`, retain the current item and join the
writable handle before waiting; on `Dropped`/other terminal status, clear the
pending slot and close the endpoint without re-promotion. Initialize all frame
slots before the first direct write.

- [x] **Step 4: Verify generated WAT and Zig tests.**

Run the focused emitter test, `zig fmt --check` on touched Zig files, and
`git diff --check`.

### Task 3: Runtime Sequence Matrix

**Files:**
- Modify: `examples/p3-runtime/cli-stream-stdout-guest-producer.do`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/cli_stream_stdout_guest_producer.rs`
- Modify: `examples/p3-runtime/test_rust_guest_stream_writer.sh`

**Interfaces:**
- The fixture exercises three values in normal, early-drop, and host-error
  modes; the host records order, pending count, and exactly-once drops.

- [x] **Step 1: Add a red runtime expectation for the third value.**

Extend the source fixture and shell assertions from `[65, 66]` to
`[65, 66, 67]`, then run the script to confirm the current emitter rejects or
fails to deliver the third value.

- [x] **Step 2: Update the host consumer expectation.**

Return `Completed` for intermediate items and `Dropped` after the configured
final item so the host callback can observe a real terminal stream state.

- [x] **Step 3: Run the pending/early-drop/error matrix.**

Run:

```bash
bash examples/p3-runtime/test_rust_guest_stream_writer.sh
```

Require ordered items, one host callback, one pending write, one reader drop,
and one writer close in every applicable mode.

### Task 4: Release Boundary

**Files:**
- Modify: `doc/async-design.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `docs/superpowers/plans/2026-07-31-future-result-stream-next-phase.md`

- [x] **Step 1: Record the B1 boundary and evidence.**

Document the accepted bounded source sequence and state that dynamic iteration,
arbitrary payloads, external writable endpoints, and abort error mapping remain
deferred.

- [x] **Step 2: Run the release gate.**

Run:

```bash
cd src && zig test build/codegen_component_async_plan.zig
cd .. && bash examples/p3-runtime/test_do_cli_stream_stdout_lowering.sh
bash examples/p3-runtime/test_rust_stream_writer.sh
bash examples/p3-runtime/test_rust_guest_stream_writer.sh
./src/build/test/run_tests.sh
git diff --check
```

Record exact results without claiming global formatting success when unrelated
dirty files fail `zig fmt --check build`.
