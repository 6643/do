# Generic Async Lowering Design

**Status:** proposed for the next phase after the WIT binding generator
checkpoint.

## Goal

Replace the generic `AsyncLoweringUnavailable` guard with one verified,
colorless async vertical slice. The first admitted program creates three
`Future<nil>` values with `@async`, suspends at two ordered `@await` sites, and
supports a separate pending Future cancellation through `@cancel`. All other
async shapes remain explicitly rejected until they have their own lowering and
runtime gate.

## Context and Boundary

The frontend already recognizes `Future<T>`, `@async`, `@await`, and
`@cancel`, and performs affine checks for Future and Stream operations. Generic
Core-Wasm emission currently rejects any program requiring resumable lowering
with `AsyncLoweringUnavailable`. Existing descriptor-specific Component
emitters and their Rust/Wasmtime probes are evidence for bounded ABI shapes;
they are not generic source lowering.

Task 8 Step 3 is the runtime baseline for this phase. It must re-run the
already admitted Component/Rust/Wasmtime descriptors and record any pinned
toolchain limitation. It does not require unsupported historical shapes to be
made green, and it does not itself implement generic async lowering.

## Design

### Source contract

The first generic slice accepts an ordinary root function containing the
existing colorless intrinsics:

```do
run() -> nil {
    first Future<nil> = @async(work())
    @await(first)

    second Future<nil> = @async(work())
    @await(second)

    third Future<nil> = @async(work())
    @cancel(third)
}
```

`work()` is a synchronous or admitted host operation that returns `nil`.
The slice has no payload, `Result`, `Stream`, resource, callback, nested async
function, aggregate await, timeout, or arbitrary Future producer. A caller
must consume each Future exactly once. Existing `async name(...) -> T` source
declarations remain guarded until a separate function-frame design is
verified; this phase lowers the colorless intrinsic surface first.

### Compiler data flow

The lowering pipeline is:

```text
Do AST + semantic facts
        -> AsyncPlan (operations, ownership, suspension points)
        -> FrameLayout (state, Future owner, terminal flag)
        -> resumable WAT state machine
        -> existing Core/Component validation and runtime probe
```

`AsyncPlan` is immutable after semantic validation. It records the exact
Future creation, await, cancel, and terminal cleanup actions. The emitter must
reject a plan shape it does not recognize; it must never silently lower async
source as synchronous code.

### Frame and state machine

The minimal frame contains a state id, Future ownership slots for the ordered
operations, a terminal state flag, and the locals required by the synchronous
`work()` call. The state machine has ordered suspend/resume transitions for
both awaits followed by cancellation:

```text
created -> running -> suspended -> ready -> terminal
created -> running -> cancelled -> terminal
```

The ready path resumes exactly once after the Future is available. The cancel
path invokes the existing cancellation ABI, then drops the Future and frame
exactly once. Terminal cleanup is idempotent and is the only path that releases
the frame-owned slot. Cancellation does not roll back external effects that
were already issued.

The first implementation uses the existing single-Store drive-loop contract;
it does not add a new scheduler, task keyword, operation id, or public
ownership/reference type.

### Runtime and ABI

The generated module must validate with the pinned `wasm-tools` and execute in
the pinned Rust/Wasmtime harness for pending, immediately-ready, and cancelled
operations. The probe records state transitions, one terminal cleanup, and no
second callback or double drop. The ABI names and terminal ordering are taken
from the existing admitted async descriptors; no new rollback or cancellation
result value is introduced.

### Diagnostics and admission

`AsyncLoweringUnavailable` remains the fallback for every shape outside the
minimal admission predicate. A new named diagnostic may distinguish an
unsupported generic async shape, but it must retain the same non-silent failure
property. The compiler must reject before WAT emission when it sees a payload,
stream, resource, aggregate await, nested async function, or untracked Future
owner in this first slice.

## Task 8 Step 3 Relationship

Task 8 Step 3 is a prerequisite release gate, not a replacement for this
design. Its order is:

1. Re-run all currently admitted runtime descriptors and record exact results.
2. Freeze the observed task/future/drop ordering as the baseline for the new
   generic probe.
3. Implement and test the minimal generic frame and state machine.
4. Add the generic Rust/Wasmtime probe and only then remove the guard for the
   exact admitted shape.

Design and unit work may start while a long-running baseline probe is in
progress, but no generic shape is promoted until both gates are green.

## Non-Goals

This phase does not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax; raw
pointers, references, callbacks, or `funcref`; arbitrary async function
lowering; `Result<T,E>` payload lowering; `Stream<T>` scheduling; resource
ownership crossing; network fetching; or unrestricted P3 host binding.

## Completion Criteria

- `AsyncLoweringUnavailable` remains for every non-admitted async shape.
- The exact minimal source fixture emits valid WAT instead of the guard.
- Pending, ready, and cancel executions pass the pinned Rust/Wasmtime gate.
- Frame ownership, cancellation, and terminal cleanup are proven exactly once.
- Existing compiler, Wasm, WIT, and release matrices remain green.
- The plan and blocker documents record the admitted shape and all remaining
  capability limits.
