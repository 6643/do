# Superseded: Host Drive ABI Design

This historical design was superseded by direct Component cancellation on
2026-07-30. Do has no `HostDrive`, operation ID, terminal acknowledgement, or
host-operation cancellation protocol. `@cancel(Future<T>)` lowers through the
descriptor-pinned Component task/subtask ABI and never promises external-effect
rollback or compensation. See
`2026-07-30-component-cancellation-lowering-design.md` for the active design.

The remainder is historical context only and must not be implemented.

## Historical Scope

This design defines the compiler-independent runtime protocol required before
resumable async lowering can emit an executable operation ABI. It does not
implement P3 host linking, Component assembly, WAT lowering, frame lowering,
or a Wasmtime adapter.

## Decision

`HostDrive` owns the boundary between logical do operations and one concrete
runtime Store. It accepts opaque descriptor and canonical-ABI argument bytes,
allocates a monotonic operation ID, and serializes host execution: at most one
operation is active at a time. Additional submissions are queued in FIFO order.

The driver exposes these operations:

```text
submit(request) -> operation_id
request_cancel(operation_id)
complete(operation_id, payload)
fail(operation_id, payload)
cancel_ack(operation_id)
next_event() -> TerminalEvent?
```

`submit` copies descriptor and argument bytes into driver-owned storage. A
completion/failure copies payload bytes into the terminal event. `next_event`
transfers that event to its caller, which must release the payload after lifting
it into the resumed frame. The driver releases submitted bytes only after an
operation reaches a terminal state.

## Cancellation

Requests declare either `not_supported` or `terminal_ack` cancellation.
`request_cancel` is idempotent for `terminal_ack`; it preserves the operation
and all owned ABI data until `Complete`, `Failed`, or `CancelledAck` is
accepted. A `not_supported` request returns `CancellationUnsupported` and does
not fabricate a timeout or cancellation terminal event.

The first selected P3 descriptor, `monotonic-clock.wait-for`, uses
`not_supported`. Timed await and `@cancel` therefore remain source-level
frontend forms until a descriptor with a tested terminal-ack contract is added.

## Scheduling

Completion, failure, or cancellation acknowledgement clears the active slot.
Only `next_event` starts the next queued operation. This makes terminal event
observation the handoff point between host work and guest resumption and
prevents Store re-entry while another host operation is active.

## Testing

The initial implementation is a fake host drive. Unit tests prove FIFO queue
admission, one-active-operation serialization, payload ownership transfer,
unsupported cancellation, and terminal-ack ordering. No test may claim P3 host
execution or remove `AsyncLoweringUnavailable`.

## Async Body Collection

The first frame collector accepts a token range for one already-validated async
body plus its parameter names. It tracks typed local declarations by brace
depth and records every `await`, `await_all`, and `await_any` token with the
currently visible parameter/local names. It is conservative capture metadata:
it may retain a binding that is dead after an await, but must not omit an
in-scope binding. Type lowering, exact liveness, and storage layout remain
emitter work.

## First Canonical ABI Envelope

The sole pinned descriptor is `monotonic-clock.wait-for`: its public argument
is `u64`, its verified Core parameter is `i64`, it has no Core result, and it
completes through `task-return` without an operation token. The first ABI
module therefore exposes only a descriptor-bound envelope for that exact
shape. It writes the `u64` bit pattern as eight little-endian bytes, requires
an empty completion payload, and represents the operation token as `absent`.

Lists, strings, records, variants, resources, nonempty results, and tokenized
operations are excluded. They require separate pinned descriptors and
ownership tests before they can share this path.

## Function Collection Boundary

The existing codegen `FuncDecl` already owns the token slice, body range, and
parameter names needed by frame collection. `collect_async_functions` will
select only declarations whose source token immediately preceding the function
name is `async`, then build one `FrameModel` per declaration. It remains an
explicit collection API; `emit_wat` continues to reject async programs before
ordinary function collection and must not invoke it until lowering is ready.
