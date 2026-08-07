# `future<own<T>>` Canonical ABI Runtime Probe

## Decision

Prove one private WIT/Component runtime shape:

```wit
resource ticket {}
read: func() -> future<own<ticket>>;
```

The probe is evidence for the pinned Component ABI and Wasmtime runtime only.
It does not add `own<T>`, `borrow<T>`, `ref<T>`, a pointer, or a reference to Do
source syntax, and it does not add a compiler registry descriptor.

## Pinned boundary

- WIT toolchain: `wasm-tools 1.255.0 (76e20611d 2026-07-30)`.
- Runtime: Wasmtime `47.0.2` through the existing Rust host runner.
- Positive shape: `future<own<ticket>>`.
- Still rejected: `future<borrow<ticket>>` and
  `stream<record { ticket: borrow<ticket> }>` in the pinned capability matrix.

## Canonical frame

The hand-authored Core module uses a 32-byte frame:

| Offset | Value | Rule |
| ---: | --- | --- |
| `+0` | waitable set | dropped at terminal cleanup |
| `+4` | readable future | dropped at terminal cleanup |
| `+8` | mode | probe control only |
| `+12` | future payload | canonical destination for the owned resource representation |
| `+16` | ticket representation | transferred from payload and cleared before drop |
| `+20` | ticket-present | independent ownership bit; `0` is a valid resource representation |

The independent presence bit is required because Wasmtime's empty
`ResourceTable` assigns its first resource representation `0`. A handle value
must never be used as an absence sentinel.

## Async callback rule

For Wasmtime's async callback ABI, the three callback parameters are event
ordinal, waitable handle, and encoded `ReturnCode`. The completed future has
code `0`; cancellation has code `2`. The payload itself has already been
lowered into the destination at frame `+12`, so the callback path decodes that
frame slot rather than treating the callback code as a pointer.

## Ownership and cleanup

The ready path transfers the representation from `+12` to `+16`, sets
`ticket-present`, and clears `+12`. Terminal cleanup drops the readable future,
checks and clears `ticket-present`, clears `+16`, then invokes
`[resource-drop]ticket` exactly once. The cancellation path never sets the
presence bit and therefore never drops a resource that was not created.

## Acceptance matrix

The Rust/Wasmtime runner executes three modes:

| Mode | Host behavior | Required result |
| --- | --- | --- |
| ready | one immediate poll creates a ticket | one resource create/drop |
| pending | one pending poll, wake, then ready | two polls and one resource create/drop |
| cancel | pending once, then cancellation | one cancel call, no resource create/drop |

Every mode requires one host call, one future drop, and an empty host
`ResourceTable` after the guest export returns.

## Non-goals

This probe does not establish generic `Future<T>` lowering, owned streams,
borrowed async values, arbitrary resource records, producer leases, compiler
source admission, or complete WASI support. Each future shape still needs its
own descriptor, lowering, negative fixtures, and runtime cleanup gate before
promotion.
