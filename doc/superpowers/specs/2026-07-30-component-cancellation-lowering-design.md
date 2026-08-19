# Component Cancellation Lowering Design

## Goal

Align Do async cancellation with the pinned WASI/Component async ABI. A Do
`@cancel(future)` lowers directly to the ABI cancellation operation for that
Future's Component subtask. Do does not define a second host-operation
cancellation protocol.

## Scope

- Keep `@cancel(future)` as an async-body-only, affine Future consumer.
- Lower cancellation through the pinned Component ABI profile, including its
  task/subtask and waitable operations.
- Keep canonical ABI cleanup required by the selected Component ABI.
- Verify generated Core WAT, component assembly, and Wasmtime execution for
  standard cancellation behavior.

## Non-Goals

- No Do `operation_id`, `request_cancel`, `CancelledAck`, or per-descriptor
  cancellation capability.
- No automatic database rollback, HTTP compensation, idempotency store, or
  external-side-effect reconciliation.
- No public `Cancelled` Result branch. Cancellation is a task lifecycle event,
  not a WIT API result value.
- No claim that cancellation reverses an external operation that may already
  have committed.

## Architecture

The pinned Component ABI profile is the single source of cancellation
semantics and exact Core import names. The compiler associates each `Future<T>`
binding with the Component subtask handle created by the async import lowering.
`@cancel(future)` consumes that binding and emits the profile's subtask cancel
operation. `await`, `await_all`, and `await_any` remain alternative affine
consumers and use the same profile's standard waitable/task operations.

No compiler path calls a Do-specific host broker. The runtime adapter only
implements the selected Wasmtime Component async API and wakes/drives the
Component as required by that API; it does not receive a Do operation ID or
publish Do terminal events.

External operation effects remain owned by the host API. The adapter must not
translate task cancellation into a false promise that a database transaction or
other side effect was rolled back.

## Removal Boundary

The following experimental model is removed from the compiler's supported async
architecture:

- `src/build/async_operation_broker.zig`
- `src/build/async_host_drive.zig`
- `src/build/async_runtime_loop.zig`
- the `cancel` field in `src/build/p3_async_registry.json`
- `CancelledAck`, `terminal-ack`, `not-supported`, operation-ID tests, and the
  associated blocker/plan claims

`src/build/async_guest_scheduler.zig` is evaluated together with the direct
Component waitable lowering. It is retained only if a source-visible Do task
semantic requires it; it must not schedule host operations through a custom
broker.

## Tests

1. A Do fixture proves `@cancel(future)` consumes the binding and rejects a
   later await/cancel.
2. A fixed P3 component fixture asserts the canonical subtask-cancel import and
   call in generated WAT.
3. `wasm-tools component embed/new/validate` accepts the pinned WIT/Core pair.
4. A Rust Wasmtime Component adapter executes cancellation through the selected
   ABI, covering cancellation before completion and cancellation after an
   already-terminal subtask without inventing application rollback behavior.
5. The full compiler regression suite remains green after removal of the custom
   cancellation experiment.

## Migration Order

1. Add direct-lowering red tests and verify the existing compiler rejects or
   lacks the desired artifact.
2. Remove descriptor cancellation metadata and custom broker/drive dependencies.
3. Implement direct profile-driven lowering and the Wasmtime fixture.
4. Update blockers, plans, and runtime documentation to state the precise
   non-goal for external side effects.
