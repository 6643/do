# D2 Filesystem Read-Via-Stream Private Boundary

Date: 2026-09-15
Status: approved design; implementation plan committed; implementation not started

## Goal

Admit one additional private Preview 3 filesystem capability:

```wit
descriptor.read-via-stream: func(
    offset: filesize,
) -> tuple<stream<u8>, future<result<_, error-code>>>;
```

The source of truth is the pinned filesystem package at
`src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit`.
The route must consume a finite byte slice, await its independent completion,
and dispose every guest-owned handle exactly once.

This design does not add generic filesystem async lowering, generic stream
lowering, public `own<T>`, `borrow<T>`, or `ref<T>` syntax.

## Selected Boundary

The compiler accepts only this private declaration shape:

```do
read_via_stream = @host_func(
    "wasi:filesystem/types@0.3.0-rc-2025-09-16",
    "descriptor.read-via-stream",
    (File, u64) -> Tuple<Stream<u8>, Future<Result<nil, FileError>>>,
)
```

`File` is the fixed `filesystem/types/descriptor` resource mirror. `FileError`
is the fixed filesystem `error-code` mirror. The route accepts one through
three sequential byte reads, each with this shape:

```do
pending Future<Result<u8, nil>> = @next(reader)
item Result<u8, nil> = @await(pending)
_ = item
```

The method call itself is synchronous: it creates and returns the readable
stream and completion-future handles. `@next(reader)` and `@await(completion)`
are the asynchronous operations. The declaration is therefore `@host_func`,
not `@host_async_func`.

The source must then await and discard the completion future before returning:

```do
completed Result<nil, FileError> = @await(completion)
_ = completed
```

One to three reads keep the operation finite and give a stable test surface.
EOF is represented by `Result<u8, nil>` rather than a compiler-special value;
the runtime probe defines the actual terminal event encoding before compiler
admission. A source shape outside this grammar is rejected.

## Architecture

```mermaid
flowchart LR
    S[.do host_func acquires handles] --> A[Private compiler admission]
    A --> E[Dedicated read-via-stream emitter]
    E --> C[Sync method ABI plus async handle operations]
    C --> W[Component assembly]
    W --> H[Wasmtime host probe]
    H --> L[ResourceTable lifecycle assertions]
    L --> G[Regression gates]
```

The dedicated emitter follows the control-flow ownership pattern of the
existing `descriptor.read-directory` emitter, but it is a separate module.
It does not share stream-result layout assumptions: directory entries use a
record result area, while this route consumes one `u8` item.

## ABI Measurement Gate

Before a registry descriptor or WAT emitter is added, a pinned-WIT Component
probe records and validates all Core imports used by this exact method:

- the synchronous `[method]descriptor.read-via-stream` import and all
  parameter/result Core value types;
- the `u64` `filesize` offset lowering and its argument order;
- readable stream construction, read, cancellation, and drop imports;
- readable future construction, read, cancellation, and drop imports;
- result-area layout for a byte item, EOF, completion success, and
  `error-code` completion failure;
- waitable/context/task-return imports used by the chosen async adapter.

Current-toolchain observation is an input to this gate, not an inferred
compatibility promise: `wasm-tools 1.258.0` emits the method import with Core
shape `(i32, i64, i32) -> nil`. The arguments are descriptor handle, `u64`
offset, and canonical result-area pointer. The method returns stream/future
handles through that result area. The committed probe must reproduce this
exact observation from the pinned WIT and fail when it changes.

The probe emits an inspectable import snapshot. Its test compares the snapshot
to the pinned WIT hash and fails when an import name, argument list, result
list, or layout assumption drifts. The compiler remains fail-closed when that
proof is absent or invalid.

## Frame And Lifecycle Contract

The WAT frame owns exactly these live handles after method acquisition:

- the descriptor;
- the readable byte stream;
- the readable completion future;
- the waitable set.

The frame also stores the `u64` offset until the method call is started, the
bounded-read counter, and a byte-item result area. Completion processing never
assumes that stream EOF proves completion success; the independent completion
future is always awaited unless cancellation or store disposal ends the task.

Cleanup is idempotent. It drops completion future, then stream, then
descriptor, clears each frame slot, drops the waitable set, clears task
context, frees the frame, and returns the task. A terminal path may run cleanup
more than once logically, but each nonzero handle can reach its matching drop
import only once.

Cancellation follows the current Component/WASI rule: it cancels live guest
Component state and releases guest-owned handles. It never claims to roll back
an already-issued filesystem read or another host effect.

## Runtime Matrix

The Rust/Wasmtime host runner records method calls, byte-stream reads,
completion polls, cancellation callbacks, every drop category, and final
`ResourceTable` state. It must prove these cases independently:

| Case | Required result |
| --- | --- |
| ready bytes and successful completion | requested bounded reads complete; all handles drop once; table empty |
| pending byte read | wake and resume correctly; all handles drop once; table empty |
| completion error | error result is observed; all handles drop once; table empty |
| cancel before EOF | cancellation reaches live stream/future state; all handles drop once; table empty |
| cancel after EOF before completion | completion state is cancelled or released correctly; all handles drop once; table empty |
| early store drop | no use-after-dispose; host disposal counters are coherent; table is not asserted after store destruction |
| repeated calls | no frame, resource, or result-area cross-call state leaks |

## Admission And Test Plan

Implementation proceeds in these gates:

1. A WIT-derived ABI probe and its drift test establish the exact Core adapter.
2. Compiler semantic tests accept only the fixed `@host_func` locator, member, resource
   mirror, `u64` offset, byte stream item, completion result, and bounded body.
3. Compiler negative fixtures reject a wrong locator/member, `u32` or reordered
   offset, non-byte stream, drifted error mirror, missing completion await,
   repeated completion await, zero or more than three byte reads, and an
   unrelated source body.
4. The dedicated Component emitter and manifest descriptor assemble a component
   from the approved fixture and preserve the measured import snapshot.
5. The Rust lifecycle matrix runs against that component, followed by the
   project regression harness and current-toolchain adapter gates.

## Alternatives Rejected

### Generic filesystem or stream lowering

This would need a shared representation for byte streams, record streams,
producer streams, resources, cancellation, and future result areas. Existing
evidence closes none of those combinations. It expands compiler admission far
beyond this method and would make a local ABI mistake affect unrelated routes.

### Reuse the read-directory emitter without a dedicated byte path

The existing route has no offset and reads a record layout. Reusing it would
hide the required `u64` and byte-result ABI differences behind a misleading
abstraction. Shared low-level helpers can be extracted only after two routes
have matching measured contracts.

## Non-Goals

- filesystem writes, append, or mutation methods;
- public resource ownership or borrowing syntax;
- unbounded byte reading, collection construction, or a general iterator API;
- compatibility adapters for older wasm-tools or Wasmtime versions.
