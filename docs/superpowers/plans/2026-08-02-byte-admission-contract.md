# Byte Admission Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Define and verify a transactional byte-budget contract for the future GC/async runtime without claiming that the active ARC backend has migrated.

**Architecture:** `ByteBudget` owns committed and in-flight reservation bytes for one runtime instance. A reservation accounts for bytes before a channel, frame, value, or ABI buffer mutates state; it either commits into an idempotent allocation token or rolls back. Pure checked size formulas keep overflow and accounting decisions outside the allocator and make the contract independently testable before runtime integration.

**Tech Stack:** Zig standard library, focused `zig test`, existing GC/runtime blocker documentation.

## Global Constraints

- No source-level pointer, reference, `own<T>`, or `borrow<T>` syntax is added.
- This contract does not switch the active ARC backend or claim GC runtime completion.
- Byte arithmetic is checked; overflow is an instance-failure-class result, never a wrapped quota value.
- Reservation, commit, rollback, and release are exactly-once operations.
- No unrelated dirty-worktree files are reset, cleaned, staged, committed, or pushed.

---

### Task 1: Transactional Budget Core

**Files:**
- Create: `src/build/async_byte_budget.zig`
- Create: `src/build/async_byte_budget_test.zig`

**Interfaces:**
- `ByteBudget.init(limit: u64) ByteBudget`
- `ByteBudget.reserve(bytes: u64) !Reservation`
- `Reservation.commit() !Allocation`
- `Reservation.rollback() !void`
- `Allocation.release() !void`

- [x] **Step 1: Write the failing tests.**

  Cover committed usage, in-flight reservation usage, rollback restoring
  capacity, duplicate finalization errors, and limit overflow rejection.

- [x] **Step 2: Verify red.**

  Run `cd src && zig test build/async_byte_budget_test.zig` and require the
  missing `async_byte_budget.zig` import/API failure.

- [x] **Step 3: Implement the minimal budget state machine.**

  Track `limit`, `committed`, and `reserved` as `u64`. `reserve` checks
  `committed + reserved + bytes` with checked arithmetic before incrementing
  `reserved`; `commit` moves the reservation to `committed`; `rollback` drops
  the reservation; `release` returns committed bytes. Reject every second
  finalization.

- [x] **Step 4: Verify green.**

  Run the focused Zig test and `git diff --check`.

### Task 2: Checked Runtime Cost Formulas

**Files:**
- Modify: `src/build/async_byte_budget.zig`
- Modify: `src/build/async_byte_budget_test.zig`

**Interfaces:**
- `bytes_for_task_frame(header_bytes: u64, payload_bytes: u64) !u64`
- `bytes_for_queue_slots(slot_bytes: u64, slots: u64) !u64`
- `bytes_for_text_backing(header_bytes: u64, utf8_bytes: u64) !u64`
- `bytes_for_list_backing(header_bytes: u64, elem_bytes: u64, capacity: u64) !u64`
- `bytes_for_canonical_buffer(header_bytes: u64, payload_bytes: u64) !u64`

- [x] **Step 1: Add red arithmetic tests.**

  Assert exact addition/multiplication for ordinary sizes and explicit
  overflow errors for every multiplication or addition boundary.

- [x] **Step 2: Implement checked formulas.**

  Use `std.math.add` and `std.math.mul`; do not saturate or wrap. Each formula
  returns only the bytes owned by its accounting point, so callers can reserve
  it before mutating state.

- [x] **Step 3: Verify formulas and budget together.**

  Run `cd src && zig test build/async_byte_budget_test.zig`.

### Task 3: Record the Runtime Boundary

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `examples/gc-p3-runtime/README.md`

- [x] **Step 1: Document the contract and its limit.**

  Record the instance-owned budget, the five accounting points, transactional
  admission rule, and the fact that the model is not runtime integration.

- [x] **Step 2: Run the release gate.**

  Run the focused budget test, the Core GC probe, `./src/build/test/run_tests.sh`,
  ReleaseSmall build, and `git diff --check`. Keep the GC Task 0 status NO-GO
  until actual scheduler and allocation call sites consume this contract.

### Task 4: Integrate Queue-Slot Admission

**Files:**
- Modify: `src/build/codegen_component_stream_writer.zig`

**Interfaces:**
- `StreamWriterQueue.init_with_budget(capacity: usize, budget: *ByteBudget, slot_bytes: u64) !StreamWriterQueue`

- [x] **Step 1: Write the failing queue admission tests.**

  Require accepted and pending slots to reserve `slot_bytes`, reject a third
  write without changing queue state when the budget is exhausted, and release
  accepted/pending reservations on `pop` and `close`.

- [x] **Step 2: Implement queue-owned allocation tokens.**

  Store one committed allocation token beside every accepted or pending item;
  move the token with a promoted item, release it when the item is consumed,
  and release pending tokens on close/abort. Keep `init(capacity)` as the
  unbudgeted compatibility constructor.

- [x] **Step 3: Verify the queue integration.**

  Run `cd src && zig test build/codegen_component_stream_writer.zig` and the
  existing stream-writer focused scripts. The GC/runtime NO-GO remains until
  TaskFrame, allocator, and canonical ABI call sites use the same contract.

### Task 5: Integrate TaskFrame Admission Model

**Files:**
- Modify: `src/build/codegen_gc_async_frame.zig`
- Create: `src/build/codegen_gc_async_frame_test.zig`

**Interfaces:**
- `bytes_for_frame_layout(layout) !u64`
- `TaskFramePool.init(budget, frame_bytes)`
- `TaskFramePool.acquire() !Allocation`
- `TaskFramePool.release(allocation) !void`

- [x] **Step 1: Write the failing TaskFrame admission tests.**

  Cover layout-header validation, budget rejection without changing the live
  frame count, exactly-once release, and emitted byte metadata.

- [x] **Step 2: Implement the minimal TaskFrame model.**

  Account the existing 16-byte frame header plus `FrameLayout.size` payload,
  reserve/commit before increasing the live-frame count, and release the token
  before decrementing the count. Keep the generated table allocator unchanged.

- [x] **Step 3: Verify the TaskFrame model.**

  Run `cd src && zig test build/codegen_gc_async_frame_test.zig`; keep the
  runtime/ARC NO-GO because `$frame-alloc` has not yet consumed this budget.

### Task 6: Integrate Canonical Buffer Admission Model

**Files:**
- Modify: `src/build/async_byte_budget.zig`
- Modify: `src/build/async_byte_budget_test.zig`
- Modify: `src/build/codegen_component_wasi_http.zig`

**Interfaces:**
- `CanonicalBufferPool.init(budget, header_bytes, payload_bytes)`
- `CanonicalBufferPool.acquire() !Allocation`
- `CanonicalBufferPool.release(allocation) !void`

- [x] **Step 1: Write failing buffer-pool and HTTP metadata tests.**

  Require checked slot sizing, budget rejection without increasing live
  buffers, release capacity restoration, cross-pool token rejection, and the
  HTTP emitter's 64-byte canonical result-slot metadata.

- [x] **Step 2: Implement the minimal fixed-slot model.**

  Reuse the transactional `FixedAllocationPool` for canonical buffer slots;
  tag committed tokens with their pool owner, keep WAT memory growth unchanged,
  and expose the accounted size as metadata.

- [x] **Step 3: Verify the canonical buffer model.**

  Run `cd src && zig test build/async_byte_budget_test.zig` and
  `cd src && zig test build/codegen_component_wasi_http.zig`. Runtime/ARC
  remains NO-GO until the WAT allocator itself consumes the budget.

### Task 7: Runtime Frame-Table Admission Probe

**Files:**
- Modify: `examples/gc-p3-runtime/async-frame-table.wat`
- Modify: `examples/gc-p3-runtime/test_async_frame_table.sh`
- Modify: `doc/host_abi_blockers.md`
- Modify: `examples/gc-p3-runtime/README.md`

**Interfaces:**
- `budget_probe() -> i32` in the standalone Core GC fixture
- `canonical_budget_probe() -> i32` in the same fixture

- [x] **Step 1: Write the failing runtime assertion.**

  Require the probe to export `budget_probe`; before implementation the script
  fails because the export is absent.

- [x] **Step 2: Add transactional frame admission to the probe.**

  Reserve 8 bytes before `table.grow`, reserve another 8-byte canonical slot
  before `memory.grow`, reject the next allocation under a 16-byte limit, and
  release each charge from cleanup or a failed grow.

- [x] **Step 3: Verify the isolated runtime path.**

  Run `bash examples/gc-p3-runtime/test_async_frame_table.sh`. This remains a
  probe boundary; generated Component allocators and scheduler integration are
  still not runtime-integrated.

### Task 8: Generated Frame Checked Accounting

**Files:**
- Modify: `src/build/codegen_gc_async_frame.zig`
- Modify: `src/build/codegen_p3_wait_for.zig`
- Modify: `src/build/codegen_component_resource_async.zig`
- Modify: `src/build/codegen_component_wasi_http.zig`
- Create: `src/build/codegen_gc_async_frame_test.zig`

**Interfaces:**
- `emit_frame_table_allocator_with_bytes(allocator, out, frame_bytes)`

- [x] **Step 1: Write the failing WAT contract test.**

  Require the allocator text to expose the frame byte metadata and reserve/
  release calls around table allocation and frame cleanup.

- [x] **Step 2: Emit checked runtime accounting.**

  Pass each known `FrameLayout.size` to the allocator emitter. The generated
  code uses an instance-local checked i64 counter, releases on table-grow
  failure and frame-free, and traps on overflow or impossible release. Keep
  the legacy no-size helper for existing unit fixtures.

- [x] **Step 3: Verify generated paths.**

  Run the frame, wait-for, resource Result, HTTP service, empty-request, and
  request-body focused tests/runners. Task 8 itself does not add a host import;
  the Core-only limit hook is covered separately in Task 9 and the runtime/ARC
  GO gate remains closed.

### Task 9: Add The Instance Limit Configuration Boundary

**Files:**
- Modify: `src/build/codegen_gc_async_frame.zig`
- Modify: `src/build/codegen_gc_async_frame_test.zig`
- Modify: `src/build/async_byte_budget.zig`
- Modify: `src/build/async_byte_budget_test.zig`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/async-design.md`

**Interfaces:**
- Generated Core hook: `[async-config]byte-budget-limit(i64) -> i32`.
- Model hook: `ByteBudget.configure(limit: u64) !void`.

- [x] Write failing assertions for the generated owner limit and model limit
  reconfiguration.
- [x] Emit the instance-local `-1` unlimited default, validate non-negative
  limits, reject limits below committed/reserved usage, and keep reserve-before-
  mutation ordering.
- [x] Verify focused Zig tests, generated WAT parsing/component lowering, and
  existing Rust/Wasmtime async cleanup paths.
- [x] Record that the hook is Core-only and does not yet provide Component host
  configuration, scheduler admission, or non-HTTP allocation coverage.

### Task 10: Account The Generated Stream-Writer Frame

**Files:**
- Modify: `src/build/codegen_component_stream_writer.zig`
- Modify: `doc/host_abi_blockers.md`

**Interfaces:**
- Generated frame metadata: `[async-frame-budget-bytes] 64`.
- Generated Core configuration hook: `[async-config]byte-budget-limit(i64) -> i32`.

- [x] Add a failing writer-emitter assertion for the fixed frame budget,
  reserve/release calls, and shared limit hook.
- [x] Reserve 64 bytes before every writer frame allocation and release them
  before frame recycling, preserving the existing frame reuse behavior.
- [x] Verify the complete writer Zig suite, descriptor lowering, and both
  forwarding/guest-producer Wasmtime runners.
- [x] Keep `cabi_realloc`, generic queue-to-stream pumping, and external
  scheduler admission explicitly outside this slice.

### Task 11: Account The Generated CLI-stdin Frame

**Files:**
- Modify: `src/build/codegen_component_cli_stream_stdin.zig`
- Modify: `doc/host_abi_blockers.md`

**Interfaces:**
- Generated frame metadata: `[async-frame-budget-bytes] 32`.
- Generated Core configuration hook: `[async-config]byte-budget-limit(i64) -> i32`.

- [x] Add a failing stdin-emitter assertion for the fixed frame budget,
  reserve/release calls, and shared limit hook.
- [x] Reserve 32 bytes before every stdin frame allocation, including freelist
  reuse, and release them before frame recycling.
- [x] Verify the stdin Zig suite, Core/WIT ABI and lowering scripts, and the
  Rust/Wasmtime runner.
- [x] Keep stream/future endpoint storage and generic scheduler admission
  explicitly outside this slice.

### Task 12: Account Generated `cabi_realloc`

**Files:**
- Create: `src/build/codegen_component_cabi_realloc.zig`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: generated Component probe templates that already own a budget
  helper
- Modify: `doc/host_abi_blockers.md`

**Interfaces:**
- `codegen_component_cabi_realloc.rewrite(allocator, wat)`
- Generated `cabi_realloc(old, old_size, align, size) -> ptr`

- [x] Add failing rewrite assertions for budget-owner injection, growth,
  shrink, and grow-failure rollback text.
- [x] Reserve `size - old_size` before growth, release `old_size - size` on
  shrink, and release the growth delta before trapping on failed
  `memory.grow`; preserve the `-1` unlimited limit.
- [x] Make the rewrite idempotent for templates that already contain the
  instance budget helper and heap owner; route async and special-target
  pipeline outputs through it.
- [x] Verify helper tests, the component async suite, WAT lowering, and the
  affected Wasmtime runners.
- [x] Add an isolated runtime probe that calls exported `cabi_realloc` for
  grow, shrink, and quota rejection, and uses its shared non-trapping try path
  to observe failed-grow rollback through the exported byte counter.
- [x] Keep external scheduler admission and general canonical buffer
  ownership outside this task.

### Task 13: Account The Registered Scalar Result Frame

**Files:**
- Modify: `src/build/codegen_p3_wait_for.zig`
- Modify: `doc/host_abi_blockers.md`

**Interfaces:**
- Generated frame metadata: `[async-frame-budget-bytes] 20`.
- Generated Core configuration hook: `[async-config]byte-budget-limit(i64) -> i32`.

- [x] Derive the fixed 20-byte frame charge from
  `bytes_for_task_frame(16, 4)` rather than duplicating the size in the
  emitter template.
- [x] Reserve the charge before linear frame allocation, release it on frame
  cleanup, and roll it back on overflow or memory-boundary failure.
- [x] Verify scalar Result lowering, pending/immediate/cancel Rust adapters,
  CLI Result lowering, and the focused Zig suite.
- [x] Keep arbitrary Result payloads, resource payload ownership, external
  scheduler admission, and general canonical allocation outside this task.

### Task 14: Prove The Private Component Budget Adapter

**Files:**
- Modify: `src/build/codegen_gc_async_frame.zig`
- Modify: `src/build/codegen_component_stream_writer.zig`
- Modify: `src/build/codegen_component_cli_stream_stdin.zig`
- Modify: `src/build/codegen_component_wasi_http.zig`
- Modify: `src/build/codegen_component_cabi_realloc.zig`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/scalar_result.rs`
- Create: `examples/p3-runtime/test_rust_scalar_result_budget_adapter.sh`
- Modify: `doc/host_abi_blockers.md`

**Interfaces:**
- Private Core alias: `byte-budget-limit(i64) -> i32`.
- Existing internal hook remains `[async-config]byte-budget-limit`.

- [x] Keep the normal compiler-generated Component WIT unchanged while adding
  a WIT-safe Core alias for an explicit host adapter.
- [x] Add a host-only sidecar augmentation and call the alias before async
  entry; verify `limit=20` admits one scalar Result frame.
- [x] Verify `limit=19` rejects before frame mutation and preserves the normal
  generated WIT surface.
- [x] Keep this as adapter evidence only; generic scheduler policy and public
  WIT configuration remain outside the task.

### Task 15: Probe Descriptor-Specific Host Admission

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/budget_gate.rs`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/scalar_result.rs`
- Modify: `examples/p3-runtime/test_rust_scalar_result_budget_adapter.sh`
- Modify: `doc/host_abi_blockers.md`

**Interfaces:**
- Host-only `BudgetGate::try_acquire(bytes) -> BudgetPermit`.
- No Component or Do source API changes.

- [x] Add checked host permits with RAII release, overflow rejection, and
  unchanged usage on admission failure.
- [x] Reject a second 20-byte scalar Result call before `run_concurrent` while
  the first permit is held.
- [x] Release after completion and admit the next call; verify the private
  Component configuration alias first.
- [x] Keep this descriptor-specific probe separate from generic scheduler
  policy, stream queue admission, and canonical ownership.

### Task 16: Probe Stream-Writer Host Admission

**Files:**
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/cli_stream_stdout.rs`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/cli_stream_stdout_guest_producer.rs`
- Create: `examples/p3-runtime/test_rust_cli_stream_stdout_scheduler.sh`
- Create: `examples/p3-runtime/test_rust_cli_stream_stdout_budget_adapter.sh`
- Modify: `examples/p3-runtime/test_rust_guest_stream_writer.sh`
- Modify: `doc/host_abi_blockers.md`

**Interfaces:**
- Host-only `DO_STREAM_WRITER_SCHEDULER_LIMIT` probe.
- Fixed generated stream-writer frame charge: `64` bytes.
- No Component or Do source API changes.

- [x] Reuse `BudgetGate` and hold one 64-byte permit across the first
  `run_concurrent` call.
- [x] Reject limits below 64 before the Component callback and reject a second
  admission while the first permit is live.
- [x] Release after completion, re-admit the second call, and verify both
  stream drops and output payloads.
- [x] Apply the same gate to the bounded guest-producer runner, isolating its
  per-consumer item count across repeated calls.
- [x] Exercise the generated private `byte-budget-limit` alias with 64-byte
  success and 63-byte pre-callback rejection for the forwarding and bounded
  guest-producer fixtures.
- [x] Keep the probe descriptor-specific; generic scheduler policy, public WIT
  configuration, and endpoint-storage accounting remain outside this task.

### Task 17: Probe CLI-stdin Host Admission

**Files:**
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/cli_stream_stdin.rs`
- Modify: `examples/p3-runtime/test_rust_cli_stream_stdin.sh`
- Modify: `doc/host_abi_blockers.md`

**Interfaces:**
- Host-only `DO_CLI_STDIN_SCHEDULER_LIMIT` and
  `DO_CLI_STDIN_BUDGET_LIMIT` probes.
- Fixed generated stdin frame charge: `32` bytes.
- No Component or Do source API changes.

- [x] Reuse `BudgetGate` for 32-byte admission and verify provider-call
  suppression below the frame limit.
- [x] Reject a second live admission, release after completion, and admit the
  next stdin call.
- [x] Configure the private Component alias in the temporary sidecar and
  verify 32-byte success plus 31-byte pre-provider rejection.
- [x] Keep stream/future endpoint storage and generic scheduler policy outside
  the descriptor-specific probe.
