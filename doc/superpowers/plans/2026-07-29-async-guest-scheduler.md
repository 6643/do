# Superseded: Async Guest Scheduler Experiment

This historical plan depended on the removed `async_host_drive` operation-ID
protocol. It is superseded by the direct Component cancellation decision on
2026-07-30. Do does not implement a guest scheduler that maps source Futures
to host operation IDs or terminal events.

Future/Stream lowering will use descriptor-pinned Component async operations,
explicit guest frames, and Component task/subtask lifecycle rules. Scheduler
admission, polling, and effects outside the component are host-runtime
responsibilities. See `2026-07-30-component-cancellation-lowering.md` and the
active Task 4 in `2026-07-29-async-future-stream.md`.

The remainder is retained solely as historical context and must not be
implemented.

---

### Task 1: Guest Ready Queue Model

**Files:**
- Create: `src/build/async_guest_scheduler.zig`
- Test: Zig unit tests in `src/build/async_guest_scheduler.zig`
- Modify: `doc/host_abi_blockers.md`

**Interfaces:**
- Consumes: `async_host_drive.OperationId`.
- Produces: `GuestScheduler.init`, `deinit`, `spawn`, `next_ready`, `park_on_operation`, `finish_turn`, and `accept_terminal`.

- [x] **Step 1: Write failing FIFO and boundary tests**

```zig
var scheduler = GuestScheduler.init(std.testing.allocator);
defer scheduler.deinit();
const first = try scheduler.spawn();
const second = try scheduler.spawn();
var budget = DrainBudget.init(1);
try std.testing.expectEqual(NextReady{ .task = first }, scheduler.next_ready(&budget));
try scheduler.finish_turn(first, .requeue);
try std.testing.expectEqual(NextReady.yield, scheduler.next_ready(&budget));
budget.reset();
try std.testing.expectEqual(NextReady{ .task = second }, scheduler.next_ready(&budget));
```

Add a separate test that parks a running task on operation `7`, accepts that
operation once, and verifies that the task returns to the FIFO queue behind an
already ready task. Add a third test for an empty queue returning `park`.

- [x] **Step 2: Verify red state**

Run: `cd src && zig test build/async_guest_scheduler.zig`

Expected: fail because `GuestScheduler` does not exist.

- [x] **Step 3: Implement the pure state model**

Create `TaskId` and task states `ready`, `running`, and `parked`. `next_ready`
must return `.park` before checking the drain budget when the queue is empty;
otherwise return `.yield` after the budget limit. `finish_turn(.requeue)` appends
the running task to the FIFO queue. `park_on_operation` moves only a running
task to parked state and records one operation ID. `accept_terminal` removes
that association, appends the task to ready, and rejects a second terminal ID.

- [x] **Step 4: Verify green and preserve compiler boundary**

Run:

```bash
cd src && zig test build/async_guest_scheduler.zig
cd .. && ./src/build/test/run_tests.sh && git diff --check
```

Expected: scheduler unit tests and the full suite pass; the async build
fixtures continue to report `AsyncLoweringUnavailable`.

- [x] **Step 5: Document the remaining adapter boundary**

State in `doc/host_abi_blockers.md` that the model defines ready/FIFO/budget
semantics only. A selected runtime adapter must still prove how `park` sleeps,
how it resumes a component call, and how it drives the host future without
re-entering a Store.
