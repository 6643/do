# Superseded: Async Runtime Coordination Experiment

This historical plan composes `HostDrive`, a guest scheduler, operation IDs,
and terminal events. Those abstractions were removed by the direct Component
cancellation decision on 2026-07-30 and must not be restored.

The compiler will lower an affine Future through descriptor-pinned Component
async/task operations, retain frame-owned values until the ABI lifecycle
permits cleanup, and make no promise about rollback of committed external
effects. Host scheduling policy remains outside the Do language contract. See
`2026-07-30-component-cancellation-lowering.md` and the active Task 4 in
`2026-07-29-async-future-stream.md`.

The remainder is retained solely as historical context and must not be
implemented.

---

### Task 1: Reservation Boundaries

**Files:**
- Modify: `src/build/async_host_drive.zig`
- Modify: `src/build/async_guest_scheduler.zig`
- Test: Zig unit tests in both modules

**Interfaces:**
- Produces `HostDrive.peek_next_event_operation() ?OperationId`.
- Produces `GuestScheduler.reserve_park(TaskId) !void`, `park_reserved(TaskId, OperationId) void`, `reserve_terminal(OperationId) !TaskId`, and `accept_reserved_terminal(OperationId) TaskId`.

- [x] **Step 1: Write red observation and reservation tests**

Test that `peek_next_event_operation` exposes the completed operation ID but
does not promote the next queued operation. Test that a terminal reservation
identifies the parked task without waking it; only the commit method appends it
to the ready queue. Test that the commit method rejects neither allocation nor
an unknown operation after a successful reservation.

- [x] **Step 2: Verify red state**

Run:

```bash
cd src && zig test build/async_host_drive.zig
zig test build/async_guest_scheduler.zig
```

Expected: the new APIs are missing.

- [x] **Step 3: Implement checked reserve and no-fail commit methods**

`peek_next_event_operation` reads only the first terminal event. `reserve_park`
checks that the task is running and reserves one parked-operation slot;
`park_reserved` appends with `appendAssumeCapacity`. `reserve_terminal` finds
the parked operation, reserves one ready slot, and returns its task ID without
state changes. `accept_reserved_terminal` removes that exact association,
changes the task to ready, and appends it with `appendAssumeCapacity`.

- [x] **Step 4: Verify green**

Run the two focused tests and confirm all existing ownership tests remain green.

### Task 2: Runtime Coordination Facade

**Files:**
- Create: `src/build/async_runtime_loop.zig`
- Test: Zig unit tests in `src/build/async_runtime_loop.zig`
- Modify: `doc/host_abi_blockers.md`

**Interfaces:**
- Produces `AsyncRuntime.init`, `deinit`, `spawn_task`, `next_ready`, `finish_turn`, `submit_and_park`, and `next_terminal`.
- `next_terminal() !?ResumedTerminal` contains `task_id` and an owned `host_drive.TerminalEvent` with a `deinit` method.

- [x] **Step 1: Write the red end-to-end ownership test**

Create one case with two parked tasks: complete the first with payload `done`,
then call `next_terminal`; assert the returned task/payload and that only this
observation promotes the second host operation. Create a separate case where a
second task is already ready when the first is woken; assert the ready task
runs before the woken task. Use `std.testing.FailingAllocator` to force both
the park reservation and terminal reservation allocation points: after the
first fails the running task must retry, and after the second fails the event
must remain peekable while queued host work remains unpromoted.

- [x] **Step 2: Verify red state**

Run: `cd src && zig test build/async_runtime_loop.zig`

Expected: fail because `AsyncRuntime` does not exist.

- [x] **Step 3: Implement the facade with reservation ordering**

`submit_and_park` calls `scheduler.reserve_park`, then `host_drive.submit`,
then `scheduler.park_reserved`. `next_terminal` peeks the operation ID, calls
`scheduler.reserve_terminal`, transfers with `host_drive.next_event`, commits
with `scheduler.accept_reserved_terminal`, and returns the event unchanged.
It returns null when no terminal event is queued.

- [x] **Step 4: Verify regression boundary**

Run:

```bash
cd src && zig test build/async_runtime_loop.zig
cd .. && ./src/build/test/run_tests.sh && git diff --check
```

Expected: focused and full tests pass; async build fixtures still report
`AsyncLoweringUnavailable`.

- [x] **Step 5: Document the non-adapter boundary**

State that this facade is a fake coordination model only. It does not sleep,
resume a Component call, invoke a runtime future, lower a frame, or establish
P3 execution support.

### Task 3: Pinned Wait-For Runtime Request

**Files:**
- Modify: `src/build/async_runtime_loop.zig`
- Modify: `doc/host_abi_blockers.md`
- Test: Zig unit tests in `src/build/async_runtime_loop.zig`

**Interfaces:**
- Consumes `p3_async_manifest.Descriptor` and the existing
  `async_canonical_abi.lower_wait_for` / `lift_wait_for_completion` APIs.
- Produces `AsyncRuntime.submit_wait_for(TaskId, Descriptor, u64)` and
  `AsyncRuntime.next_wait_for_terminal(Descriptor) !?ResumedTerminal`.

- [x] **Step 1: Write the red pinned-request test**

Load the single pinned descriptor from a test registry. Start a task and call
`submit_wait_for` with `0x0102_0304_0506_0708`; assert the copied host request
uses `wasi:clocks@0.3.0/monotonic-clock.wait-for`, the little-endian eight-byte
argument, and `not_supported` cancellation. Complete with an empty payload and
assert `next_wait_for_terminal` returns the task. A nonempty completion must
return `InvalidWaitForCompletionPayload` while releasing the transferred event.

- [x] **Step 2: Verify red state**

Run: `cd src && zig test build/async_runtime_loop.zig`

Expected: fail because `submit_wait_for` does not exist.

- [x] **Step 3: Implement the descriptor-bound methods**

`submit_wait_for` calls `lower_wait_for`, builds the owned
`locator/member` identity, submits with `not_supported`, then frees only the
temporary canonical request and identity after `HostDrive` has copied them.
`next_wait_for_terminal` delegates to `next_terminal`, validates its optional
payload through `lift_wait_for_completion`, and releases the event if lifting
rejects it. Do not infer or store a generic descriptor mapping.

- [x] **Step 4: Verify runtime and compiler boundaries**

Run:

```bash
cd src && zig test build/async_runtime_loop.zig
cd .. && ./src/build/test/run_tests.sh && git diff --check
```

Expected: the pinned runtime test and full suite pass; all async build fixtures
continue to return `AsyncLoweringUnavailable`.
