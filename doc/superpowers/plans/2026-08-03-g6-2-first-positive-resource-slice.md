# G6.2 First Positive Resource Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the private, descriptor-bounded `StreamWriter<T>` producer path with one explicit lease handoff and exactly one terminal completion branch, while preserving value semantics and the current Component/runtime boundaries.

**Architecture:** Keep the existing `do:stream-probe@0.1.0` descriptor and private `StreamWriter<u8>` lowering. Extend the semantic plan to admit one helper-mediated lease transfer followed by one terminal action selected by a guarded branch: `close(writer)` for normal completion or `abort(writer, 2)` for the registered `pipe` error discriminant. Emit both paths through one frame-owned finalization routine so the lease, queue, task completion, and waitable set remain exactly-once. No public ownership type or general async lowering is introduced.

**Tech Stack:** Zig 0.16 compiler/tests, Do fixtures, WAT/WIT Component assembly, pinned `wasm-tools 1.254.0`, Rust 2024, Wasmtime `47.0.2`, Bash regression harness.

## Global Constraints

- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Do not enable arbitrary async-call composition, arbitrary producer expressions, borrowed/list/variant resource fields, sixth forwarding, seventh nesting, or D2/real WASI host I/O.
- Preserve the existing affine writer lease: one transfer, one active owner, one terminal action.
- Preserve cancellation semantics: stop guest work and release live Component resources; never compensate an external side effect.
- Keep `wasm-tools 1.254.0` and Wasmtime `47.0.2` pinned.
- Preserve unrelated dirty worktree changes; do not reset, clean, checkout, commit, or push.

## Entry Gate

Start only after the current G6.2 planning gate remains green:

```bash
TMPDIR="$PWD/.tmp/do-tmp/negative-default" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/negative-zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/negative-zig-gcache" \
./src/build/test/run_tests.sh
```

Expected: `pass=1068 fail=0 skip=3`. Also require the focused negative gates to pass:

```bash
(cd src && zig test build/p3_async_manifest.zig)
bash examples/p3-runtime/test_do_g6_general_boundary_rejection.sh
bash examples/p3-runtime/test_do_borrowed_resource_rejection.sh
```

If any entry-gate failure is a compiler/runtime assertion rather than temporary-storage exhaustion, stop this plan and repair the boundary fixture first.

## File Map

- Modify: `src/build/codegen_component_async_plan.zig` — recognize the bounded branch-terminal producer shape and expose its terminal action to codegen.
- Modify: `src/build/sema_stream_lease.zig` — enforce one transfer and equal terminal state at the branch join; reject use, second transfer, and incomplete terminal paths.
- Modify: `src/build/codegen_component_stream_writer.zig` — emit the abort terminal operation and route close/abort through one exactly-once frame cleanup sequence.
- Modify: `src/build/codegen_component_async.zig` — preserve the existing `UnsupportedP3AsyncComponent` mapping for shapes outside the new bounded form.
- Create: `src/build/test/check/413_stream_writer_branch_terminal.do` — positive semantic fixture with one transfer and a guarded close/abort terminal.
- Create: `examples/p3-runtime/stream-probe-guest-producer-branch-terminal.do` — P3 component fixture using the new private shape.
- Create: `examples/p3-runtime/wit/stream-probe-guest-producer-branch-terminal.wit` — expected generated WIT snapshot.
- Create: `examples/p3-runtime/test_do_stream_writer_guest_producer_branch_terminal.sh` — lowering, WIT, and rejection checks.
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/stream_probe_guest_producer_dynamic.rs` — add a terminal-error mode that verifies abort reaches the consumer and cleanup remains exactly-once.
- Create: `examples/p3-runtime/test_rust_stream_writer_guest_producer_branch_terminal.sh` — pending/ready/abort Wasmtime runtime matrix.
- Modify: `doc/design/2026-08-03-g6-2-general-resource-ownership.md` — record the verified positive shape and its limits.
- Modify: `doc/pending_blocked.md`, `doc/roadmap_status.md`, `doc/host_abi_blockers.md` — record only the newly verified private slice and retain all unrelated blocked boundaries.

## Task 1: Add the semantic red/green contract

**Interfaces:**

- Consumes: existing `LeaseState`, `StreamWriterPlan`, `StreamWriterAlreadyFinalized`, and branch-join rules.
- Produces: one accepted shape with exactly one transfer and equal terminal states on all exits.

- [x] **Step 1: Write the positive fixture.**

Create `src/build/test/check/413_stream_writer_branch_terminal.do` with a private `StreamWriter<u8>` parameter passed exactly once to `finish_stream`, where `finish_stream` selects `close(writer)` or `abort(writer, 2)` under a single guarded branch and awaits the registered sink result. The literal `2` is the pinned `pipe` error discriminant, not an arbitrary runtime error code.

- [x] **Step 2: Write the negative siblings.**

Add two in-memory sema cases in `src/build/sema_stream_lease.zig`: one uses the writer after the terminal branch and must return `StreamWriterAlreadyFinalized`; the other closes only one branch and must return `StreamWriterLeasePathConflict`.

- [x] **Step 3: Run the tests before implementation.**

Run:

```bash
(cd src && zig test build/sema_stream_lease.zig)
DO_LIB_ROOT="$PWD/lib" ./bin/do build --p3-async-component \
  examples/p3-runtime/stream-probe-guest-producer-branch-terminal.do \
  -o .tmp/do-tmp/branch-terminal-red.wat
```

Expected: the new P3 fixture is rejected with `UnsupportedP3AsyncComponent`, while the two negative unit tests retain their current failure diagnostics. This is the red baseline for the plan. The positive `check` fixture is added to the normal semantic suite only after the plan analyzer accepts it.

## Task 2: Extend the bounded semantic plan

**Interfaces:**

- Consumes: `StreamWriterPlan.analyze`, the existing countdown/parameterized producer parser, and Task 1 fixtures.
- Produces: a plan field such as `terminal_action` with only `close` or `abort(i32)` and a fixed `forwarding_depth == 1` for this slice.

- [x] **Step 1: Parse only the guarded terminal grammar.**

Accept a branch whose two arms each contain exactly one terminal operation on the transferred writer, with no writes after the branch and no second helper call. Accept only `abort(writer, 2)`, which maps to the registered `pipe` error discriminant. Reject nested branches, loops around the terminal, dynamic abort codes, other abort literals, and terminals in different helper depths with `UnsupportedP3StreamWriterComponent`.

- [x] **Step 2: Bind the terminal action into `StreamWriterPlan`.**

Use an explicit enum/struct rather than a boolean so codegen can distinguish `close` from `abort` and carry the literal abort code. Keep existing fixed/countdown/parameterized producer modes unchanged.

- [x] **Step 3: Add unit tests for admission and rejection.**

Cover: close branch, `abort(writer, 2)`, one helper transfer, dynamic abort code rejection, one-sided terminal rejection, and a second transfer rejection.

- [x] **Step 4: Verify the plan layer.**

Run:

```bash
(cd src && zig test build/codegen_component_async_plan.zig)
```

Expected: all existing tests pass and the new positive/rejection tests pass.

## Task 3: Implement exactly-once terminal codegen

**Interfaces:**

- Consumes: Task 2 `terminal_action` and existing writer frame offsets/import names.
- Produces: WAT that drops pending queue data, marks the writer finalized once, emits close or abort, completes the task once, and drops the waitable set/frame once.

- [x] **Step 1: Add the minimal WAT abort primitive.**

Emit `$writer-abort(frame, code)` beside `$writer-finalize(frame)`. It must return `-1` when the frame is already terminal, clear pending writes, set the terminal/error slots, wake the consumer, and never drop the same endpoint twice. The only admitted call site passes `2`, so the Component result remains a valid `pipe` discriminant.

- [x] **Step 2: Route both branch arms through one cleanup epilogue.**

The normal arm calls `$writer-finalize`; the error arm calls `$writer-abort`; both then use the same task-return/frame-free path. No arm may directly free the frame or waitable set.

- [x] **Step 3: Keep unsupported shapes guarded.**

If plan analysis fails, preserve the existing `UnsupportedP3AsyncComponent` result from `codegen_component_async.zig`; do not silently lower a different producer shape.

- [x] **Step 4: Run focused Zig tests.**

```bash
(cd src && zig test build/codegen_component_stream_writer.zig)
(cd src && zig test build/codegen_component_async.zig)
```

Expected: queue abort tests, existing producer WAT assertions, and all async guard tests pass.

## Task 4: Add lowering and pinned Component gates

**Interfaces:**

- Consumes: Task 3 WAT and the existing `do:stream-probe` descriptor.
- Produces: a stable positive fixture and a stable negative gate for unsupported branch forms.

- [x] **Step 1: Add the Do fixture and WIT snapshot.**

Use `examples/p3-runtime/stream-probe-guest-producer-branch-terminal.do` with one private helper transfer. The generated WIT must remain the existing `write-via-stream` stream<u8> contract; no `own<T>`/`borrow<T>` appears in source or output.

- [x] **Step 2: Add the lowering script.**

`test_do_stream_writer_guest_producer_branch_terminal.sh` must invoke `./bin/do build --p3-async-component`, compare the WIT snapshot, require `[writer-endpoint-mode] guest-producer`, require both `[writer-finalize]` and `[writer-abort]` markers, then invoke the negative dynamic-code fixture and require `UnsupportedP3AsyncComponent`.

- [x] **Step 3: Run pinned Component embedding.**

Run `wasm-tools component embed` and `wasm-tools component new` with the repository WIT snapshot and generated core module. Expected: exit zero; no borrowed/list/variant payload is introduced.

## Task 5: Verify pending, ready, and abort runtime behavior

**Interfaces:**

- Consumes: Task 4 component and the existing dynamic stream host runner.
- Produces: runtime evidence for one transfer, one terminal completion, and exactly-once stream/future/frame cleanup. This producer-only runner has no `ResourceTable` and must not claim `table-empty=true`.

- [x] **Step 1: Extend the runner with terminal-error mode.**

Add a mode that invokes the producer with a value selecting `abort(writer, 2)`, then verifies the exported result is `Err(pipe)` after the sink observes the terminal and records consumer drop, host-call count, and pending polls. Keep the existing pending/ready/error modes unchanged.

- [x] **Step 2: Add the runtime shell gate.**

`test_rust_stream_writer_guest_producer_branch_terminal.sh` must run pending and ready normal completion plus the abort path. Each run must assert one host call, one stream drop, one terminal completion, and the expected item prefix. It must not assert `table-empty=true`, because this runner does not instantiate a `ResourceTable`.

- [x] **Step 3: Run Rust formatting and checks.**

```bash
rustfmt --edition 2024 --check examples/p3-runtime/rust-host-runner/src/bin/stream_probe_guest_producer_dynamic.rs
(cd examples/p3-runtime/rust-host-runner && cargo check --locked)
```

Expected: zero exit status using the repository Zig linker wrapper.

## Task 6: Update evidence and close the slice

**Interfaces:**

- Consumes: Tasks 1–5 command output.
- Produces: status documents that distinguish this verified private slice from remaining blocked work.

- [x] **Step 1: Update the capability matrix.**

Add one row for “one helper-mediated lease transfer with branch-selected close/abort terminal” marked `verified`, including the exact scripts and pinned tool versions.

- [x] **Step 2: Preserve explicit negative boundaries.**

Keep sixth forwarding, seventh nesting, borrowed/list/variant fields, arbitrary producer expressions, shared leases, public ownership syntax, and general async calls marked blocked with their existing diagnostics.

- [x] **Step 3: Run the focused and full gates.**

```bash
bash examples/p3-runtime/test_do_stream_writer_guest_producer_branch_terminal.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_branch_terminal.sh
TMPDIR="$PWD/.tmp/do-tmp/final-tmp" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/final-zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/final-zig-gcache" \
./src/build/test/run_tests.sh
git diff --check
```

Expected: focused gates pass, default regression is `pass=1068 fail=0 skip=3`, `RUN_WASM=1` reports `pass=1070 fail=0 skip=3` with `wasm run summary: pass=6 fail=0`, and `git diff --check` is empty.

## Stop Conditions and Follow-up

Stop this slice if the new terminal requires a second live owner, a new public type, an unregistered descriptor, a change to cancellation compensation, or any increase to forwarding/nesting limits. Those findings become a separate design decision. After this slice is green, the next review point is whether to add another private terminal shape or begin an independent feasibility plan for resource-bearing result payloads; public `own<T>`, `borrow<T>`, and `ref<T>` remain out of scope.
