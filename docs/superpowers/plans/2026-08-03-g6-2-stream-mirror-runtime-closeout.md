# G6.2 StreamMirror Runtime Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` (or `superpowers:subagent-driven-development`) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining G6.2 descriptor-bounded `StreamMirror` runtime gate by fixing exactly-once stream/future cleanup in normal terminal paths and recording fresh evidence for every supported mode.

**Architecture:** Keep the existing private `StreamMirrorPlan` and descriptor-selected WAT emitter. Diagnose the Wasmtime `resource has children` failure at the host/guest endpoint boundary, then change only the responsible cleanup ordering or terminal-state transition; do not widen the source-shape parser or introduce a general ownership/async IR. The Rust runner remains the executable ownership oracle and the shell gate remains the reproducible Component assembly boundary.

**Tech Stack:** Zig 0.16 compiler/tests, Do fixtures, WAT/WIT Component assembly, pinned `wasm-tools 1.254.0`, Rust 2024, Wasmtime `47.0.2` legacy async runner, Bash regression harness.

## Global Constraints

- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Keep the accepted StreamMirror shape fixed: registered `read-via-stream`, bounded `u8` reads, one guest `StreamWriter<u8>`, one sink transfer, and one source completion cancellation.
- Preserve ordinary `do build` rejection with `AsyncLoweringUnavailable`; only `--p3-async-component` uses this emitter.
- Preserve the established cancellation decision: cancellation stops guest work and drops live resources; it does not roll back external side effects.
- Keep `wasm-tools 1.254.0` and Wasmtime `47.0.2` unchanged.
- Do not extend parameterized forwarding beyond five hops, nested owned-resource depth beyond six, or general producer/resource shapes in this phase.
- Preserve unrelated dirty worktree changes; do not reset, clean, checkout, commit, or push.

## Current Evidence

- `examples/p3-runtime/test_do_stream_mirror_lowering.sh` passes Core WAT parsing/validation, Component assembly/validation, WIT comparison, and the ordinary-build guard.
- `cargo check --bin do-p3-stream-mirror-host-runner` passes with the repository Zig linker wrapper.
- `test_rust_stream_mirror.sh` now passes all six modes: `pending`, `ready`, `source-eof`, `error`, `cancel`, and `early-drop`.
- Every mode reaches its cleanup assertions: one source future drop, one source stream drop, one sink callback/drop, and `table-empty=true`; normal modes also verify their mode-specific pending behavior.

---

### Task 1: Make the runtime failure observable and mode-isolated

**Files:**

- Modify: `examples/p3-runtime/rust-host-runner/src/bin/stream_probe_stream_mirror.rs`
- Modify: `examples/p3-runtime/test_rust_stream_mirror.sh`
- Test: `examples/p3-runtime/rust-host-runner/Cargo.toml` binary check

**Interfaces:**

- Preserve `Mode::{Pending, Ready, SourceEof, Error, Cancel, EarlyDrop}` and the existing `verify_mode`/`verify_cancel` contracts.
- Change `test_rust_stream_mirror.sh` to accept an optional first argument naming one mode; with no argument it runs the full six-mode matrix.
- Add only diagnostic event recording around source acquisition, source producer polling, sink callback installation, sink consumer polling, and `Drop` implementations; diagnostics are enabled by `DO_DEBUG` and do not alter behavior.

- [x] **Step 1: Reproduce each mode with a bounded command.**

```bash
for mode in pending ready source-eof error cancel early-drop; do
  timeout 30s bash examples/p3-runtime/test_rust_stream_mirror.sh "$mode"
done
```

Expected before the fix: normal modes fail with `resource has children`; `cancel` is the only passing mode.

- [x] **Step 2: Add `debug()` and event markers.**

Use the existing `DO_DEBUG` convention from `cli_stream_stdout_guest_producer.rs`. Emit markers before/after `reader.pipe`, before each `poll_produce`/`poll_consume`, on `RecordingSource`, `RecordingCompletion`, and `RecordingSink` drops, and immediately before the nested `produce.call_concurrent` result is mapped. Keep counters unchanged.

- [x] **Step 3: Add a timeout and optional mode selector to the matrix script.**

Use `modes=(pending ready source-eof error cancel early-drop)` when no argument is supplied, or `modes=("$1")` for one supplied mode; reject any other arity or unknown mode, wrap each `cargo run` invocation in `timeout 30s`, print `stream-mirror mode=<mode>`, and preserve the exact linker environment. A hang must fail the gate with its mode instead of leaving an unbounded process.

- [x] **Step 4: Verify the diagnostic-only change.**

```bash
cargo check --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml \
  --bin do-p3-stream-mirror-host-runner
DO_DEBUG=1 bash examples/p3-runtime/test_rust_stream_mirror.sh pending
```

Record the first failing event and the endpoint whose drop returns `resource has children`; do not claim the runtime gate is fixed in this task.

### Task 2: Add a red cleanup-order regression and align the terminal state machine

**Files:**

- Modify: `src/build/codegen_component_stream_writer.zig`
- Modify: `src/build/codegen_component_stream_writer.zig` unit-test section
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/stream_probe_stream_mirror.rs`
- Test: generated WAT from `examples/p3-runtime/stream-probe-stream-mirror.do`

**Interfaces:**

- Keep `emit_stream_mirror_component_wat` and `emit_stream_mirror_component_wit` signatures unchanged.
- Keep `StreamMirrorFrameLayout` offsets (`source_reader=64`, `source_completion=68`, `remaining=88`, `size=96`) unchanged.
- Terminal paths must retain one source-future drop, one source-stream drop, one sink stream drop, one writer lease finalization, and one frame release.

- [x] **Step 1: Write the failing WAT assertions.**

Generate the current mirror WAT and assert that the four callback markers `[stream-mirror-sink-result]`, `[stream-mirror-cancel]`, `[stream-mirror-source-read]`, and `[stream-mirror-writer-write]` each occur once. Add a dedicated marker immediately before each shared cleanup transition, for example:

```wat
;; [stream-mirror-cleanup] source-completion
;; [stream-mirror-cleanup] source-reader
;; [stream-mirror-cleanup] sink-writable
;; [stream-mirror-cleanup] writer-finalize
```

The red assertion must fail while the host trace still identifies a live child at the failing drop; the test must not weaken the current `resource has children` failure into a warning.

- [x] **Step 2: Compare the mirror terminal sequence with the passing guest-producer emitter.**

Use `codegen_component_stream_writer.zig`'s existing producer terminal sequence as the reference. Confirm which endpoint is still host-owned when the mirror calls `mirror-finish-source` or `mirror-drop-writable`; do not change the parser, registry, or WIT shape.

- [x] **Step 3: Implement the smallest state-machine fix.**

Change only `stream_mirror_entry_wat`, `stream_mirror_callback_body`, or the shared cleanup helper that owns the failing transition. The resulting state machine must:

1. stop source reads before terminal cleanup;
2. signal the sink stream terminal state exactly once;
3. drop the source completion and source reader only after their pending operations are no longer live;
4. drop the transferred sink endpoint in the order required by the Wasmtime trace;
5. finalize the writer lease and frame exactly once on success, error, early-drop, and cancellation.

Do not suppress the Wasmtime error, ignore a failed drop, or relax `table-empty` checks.

- [x] **Step 4: Run focused compiler tests and inspect the emitted order.**

```bash
(cd src && zig test build/codegen_component_stream_writer.zig && zig test build/codegen_component_async_plan.zig)
```

```bash
bash examples/p3-runtime/test_do_stream_mirror_lowering.sh
```

Expected: WAT/Component gates remain green and the cleanup markers show one terminal path per branch.

### Task 3: Close the Rust/Wasmtime mode matrix

**Files:**

- Modify: `examples/p3-runtime/test_rust_stream_mirror.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/stream_probe_stream_mirror.rs` only if Task 2 exposes a runner contract mismatch

**Interfaces:**

- `verify_mode` must continue to require:
  `source_stream_drops=1`, `source_future_drops=1`, `source_completion_polls=0`, `sink_callbacks=1`, `sink_stream_drops=1`, the mode-specific `sink_pending_polls`, and `ResourceTable::is_empty() == true`.
- `verify_cancel` must continue to require no completion poll, one source stream drop, one source future drop, one sink callback/drop, and an empty resource table.

- [x] **Step 1: Run each mode independently after the cleanup fix.**

```bash
for mode in pending ready source-eof error early-drop; do
  DO_DEBUG=1 bash examples/p3-runtime/test_rust_stream_mirror.sh "$mode" 2>&1 | tee "/tmp/stream-mirror-$mode.log"
done
```

Use the script's mode loop output to verify that each mode reaches `verify_mode`; do not accept a process exit without the expected line.

- [x] **Step 2: Verify cancellation separately.**

```bash
DO_DEBUG=1 timeout 30s bash examples/p3-runtime/test_rust_stream_mirror.sh cancel
```

Expected: `stream mirror passed mode=cancel source-future-drop=1 table-empty=true`.

- [x] **Step 3: Run the complete gate.**

```bash
bash examples/p3-runtime/test_rust_stream_mirror.sh
```

Expected: one passing line for `pending`, `ready`, `source-eof`, `error`, `cancel`, and `early-drop`, followed by `stream mirror Rust/Wasmtime matrix passed ...`.

### Task 4: Refresh status documents from fresh evidence

**Files:**

- Modify: `doc/async-design.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: this plan file

**Interfaces:**

- Documentation must distinguish the already-verified lowering gate from the newly verified runtime gate.
- Keep sixth forwarding hop, seventh nested level, borrowed/list/variant resource fields, arbitrary producer expressions, general async calls, and real D2 host I/O explicitly blocked.

- [x] **Step 1: Update the G6.2 boundary text.**

Record the exact supported StreamMirror modes and cleanup invariants only after Task 3 passes. Before Task 3 passes, retain `G6.2` as blocked and include the exact `resource has children` failure as evidence.

- [x] **Step 2: Refresh counts only from commands executed in this phase.**

Use fresh output from the focused Zig tests, `./src/build/test/run_tests.sh`, `RUN_WASM=1 ./src/build/test/run_tests.sh`, and `./src/build/test/run_release_smoke.sh`; do not copy counts from the stale checked-in plan.

- [x] **Step 3: Validate non-code artifacts.**

```bash
rustfmt --edition 2024 --check examples/p3-runtime/rust-host-runner/src/bin/stream_probe_stream_mirror.rs
bash -n examples/p3-runtime/test_do_stream_mirror_lowering.sh examples/p3-runtime/test_rust_stream_mirror.sh
python3 -m json.tool src/build/p3_async_registry.json >/dev/null
git diff --check
```

### Task 5: Stop at the G6.2 review gate

**Files:**

- Verify: `doc/pending_blocked.md`, `doc/host_abi_blockers.md`, `doc/roadmap_status.md`

- [x] **Step 1: Confirm no product arbitration is required for this closeout.**

The current blocker is an implementation/runtime lifecycle defect with a reproducible failure and an existing bounded contract. No decision about public ownership syntax, reference semantics, or cancellation rollback is needed to resolve it.

- [x] **Step 2: Do not start the next expansion in the same change.**

After the matrix passes, pause for review before any of the following:

```text
general producer leases
public own<T>/borrow<T>/ref<T>
borrowed/list/variant resource fields
sixth forwarding hop or seventh nested level
general async-call lowering
real WASI/D2 host I/O
```

- [x] **Step 3: Prepare the next design decision as a separate plan.**

The next candidate is a feasibility/design phase for general resource ownership and host ABI, not an immediate codegen expansion. It must specify ownership states, async-call lowering, cancellation terminal states, and exactly-once cleanup before implementation is authorized.

## Verification Summary

The phase is complete. Fresh evidence is:

- default regression: `pass=1068 fail=0 skip=3`;
- WASM regression with workspace `TMPDIR`: `pass=1070 fail=0 skip=3`, wasm smoke `pass=6 fail=0`;
- ReleaseSmall smoke with workspace `TMPDIR`: build/test/check/fmt/run/lsp all passed;
- focused StreamMirror lowering and Rust/Wasmtime six-mode matrix passed with exactly-once cleanup and `table-empty=true`;
- `rustfmt --check`, shell syntax checks, registry JSON validation, and `git diff --check` passed.

The residual risks are unchanged: general producer leases, borrowed/list/variant resource fields, sixth forwarding, seventh nested resource level, arbitrary producer expressions, general async-call lowering, and real D2 host I/O remain blocked and are handled by the separate general-resource-ownership plan.
