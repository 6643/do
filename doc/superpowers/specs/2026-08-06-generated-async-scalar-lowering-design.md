# Generated Async Scalar Lowering Design

## Status

Bounded design for the next generated-WIT async capability. This document
admits exactly one private `Future<u32>` shape and does not change the public
ownership or general async model.

## Goal

Allow one generated WIT binding with the source signature:

```text
completion: func() -> future<u32>
```

to be consumed through the colorless Do surface:

```do
run() -> nil {
    ready Future<u32> = completion()
    value u32 = @await(ready)
    _ = value

    pending Future<u32> = completion()
    @cancel(pending)
}
```

The generated binding must already provide `Future<u32>`; callers must not
wrap it in `@async`. The admitted root remains an ordinary `run() -> nil`
function. Existing `Future<nil>` behavior remains unchanged.

## Non-goals

- No public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- No generic `Future<T>` lowering, text/list/record/resource payloads, or
  `Stream<T>` lowering.
- No aggregate await, timeout, branch/loop scheduling, multiple root tasks, or
  concurrent cancellation.
- No changes to ordinary public Result policy (`T | E`).
- No inference of canonical ABI facts from a locator or function name.

## Recommended Architecture

Use a new private pinned WIT package/world rather than widening the existing
unit capability. The package contains one host interface member and one async
export world. The exact WIT source, package revision, generated module hash,
canonical async import names, completion operation, and payload layout are
measured by an independent WAT plus Rust/Wasmtime probe before compiler
admission.

The generated manifest emits schema 2 with a new capability name,
`component-async-scalar-u32-v1`. Its descriptor records the source signature
`() -> Future<u32>`, WIT identity, WIT hash, async import module/name,
completion operation, and measured scalar payload facts. Import resolution
validates every field and exposes an immutable descriptor to the generic async
analyzer. Any drift fails before WAT emission.

The generic analyzer gains a separate scalar source mode. It accepts only one
generated `Future<u32>` await followed by one separate terminal `Future<u32>`
cancel in an ordinary root function; the generated descriptor is the only
producer. The frame owns one `u32` payload slot. On a ready callback the
payload is copied into that slot before the callback resumes the frame; the
await expression reads the slot exactly once. A pending callback keeps the
frame and subtask alive. Cancellation follows the existing completion-oriented
semantics: it ends the task and drops the subtask exactly once without rolling
back external effects.

The emitter must consume the descriptor's measured payload metadata. It may
not assume that a Component task-return payload is a raw i32 merely because
the source type is `u32`; the probe defines the canonical result-area or
callback word layout. The unit `Future<nil>` template remains a separate
template or explicit mode so its no-payload task-return contract cannot be
silently changed.

## ABI Probe and Runtime Contract

The probe is a private package/world with one `completion` operation and a
`run` export. Its host runner provides three modes:

- `ready`: completion returns `42` immediately; the guest observes `42`, and
  the host observes one poll, one completion, and one cleanup.
- `pending`: completion wakes once and then returns `42`; the guest observes
  `42`, with exactly one external wake, one completion, and one cleanup.
- `cancel`: completion remains pending; cancellation occurs before completion,
  with zero completion callbacks and one pending-future/subtask cleanup.

The runner uses one Component and one Wasmtime Store per invocation and checks
an empty resource table at termination. A second completion, a missing drop,
an early frame free, a mismatched payload offset/width, or a non-empty table is
a failure.

## Admission and Negative Boundaries

Positive generated binding and caller fixtures must pass manifest validation,
ordinary `do check`, Component assembly, and the Rust/Wasmtime matrix. Drift
mutations must reject changed package/world/member, source signature, WIT hash,
async import, completion operation, payload offset, payload width, and payload
encoding.

The following remain explicit negative fixtures and must continue to return a
named unsupported diagnostic before WAT emission:

- `Future<u32>` from unregistered or mismatched locators;
- `Future<i64>`, `Future<text>`, `Future<Stream<u8>>`, and resource payloads;
- generated async `send` with a resource Result payload;
- an `async` function declaration or an implicit Future producer;
- a second await, timeout, aggregate await, branch/loop await, or concurrent
  root operation outside the admitted bounded shape.

## Verification Gates

1. WIT source hash and canonical WAT probe assemble with the pinned
   `wasm-tools 1.254.0` and validate with Component async feature flags.
2. WIT manifest schema 2 emits and validates the scalar capability; schema 1
   remains unchanged for non-capability bindings.
3. Generated module import resolution rejects every descriptor drift before
   codegen.
4. Focused analyzer/emitter tests cover positive `42`, pending, immediate,
   cancel, and all negative shapes above.
5. Generated Component/Rust/Wasmtime runtime gate passes all three modes with
   exact payload and cleanup markers.
6. Existing unit async, G6.2, Result, ordinary compiler, Wasm, and ReleaseSmall
   matrices remain green.

## Failure Policy

If the pinned probe cannot establish a stable scalar payload ABI, do not add
the capability or weaken the existing `AsyncLoweringUnavailable` guard. Record
the exact toolchain/probe failure and leave this shape pending. A passing unit
async probe is not evidence for scalar payload lowering.
