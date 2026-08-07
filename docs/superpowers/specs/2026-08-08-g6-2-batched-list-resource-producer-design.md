# G6.2 Batched List-Resource Producer Design

**Status:** Tasks 1-2 design, canonical ABI, and ownership probe are green;
compiler manifest/sema admission and generated lowering are not admitted yet.

**Date:** 2026-08-08

## Decision

Add one private, descriptor-bounded producer shape that sends exactly two
`list<resource-entry>` values through a capacity-one stream. The first list has
ticket seeds `[111, 222]`; the second has `[333]`. The package, world, WIT hash,
canonical imports, and source declaration are distinct from the existing C-min
and dynamic-count producers.

This is an ownership/cleanup probe, not generic list or producer lowering. The
Do compiler may recognize only the exact declaration topology in this document
and may emit only a hand-authored two-batch template. It must not inspect or
lower arbitrary list expressions.

## Scope Boundary

The shape uses WIT `own<ticket>` only as private Component ABI metadata. It does
not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, or lifetime
syntax. Borrowed stream/future payloads, generic or unbounded lists, arbitrary
producer expressions, independent guest child tasks, root hard-cancel, and D2
filesystem/HTTP async remain rejected or pending.

## WIT Contract

The pinned WIT source is:

```wit
package do:g6-2-batched-list-producer@0.1.0;

interface types {
  enum error-code { io, pipe, invalid-mode }
  resource ticket {}
  record resource-entry { ticket: own<ticket> }
}

interface source {
  use types.{ticket};
  make-ticket: func(seed: u32) -> own<ticket>;
}

interface sink {
  use types.{error-code, resource-entry};
  consume-via-stream: async func(
    data: stream<list<resource-entry>>
  ) -> result<_, error-code>;
}

world batched-list-producer {
  use types.{error-code};
  import source;
  import sink;
  export produce: async func(mode: u32) -> result<_, error-code>;
}
```

The WIT file is stored under `examples/p3-runtime/wit/`, matching the existing
P3 fixture layout. Its SHA-256 and canonical import names become registry facts
only after the pinned probe succeeds.

## Do Admission

The only source accepted by the future private adapter is:

```do
make_ticket = @host("do:g6-2-batched-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
consume = @host_func("do:g6-2-batched-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
Ticket = @wasi_resource("do:g6-2-batched-list-producer/source/ticket", { .id i64 })
ResourceEntry { .ticket Ticket }
ProducerError error = Io | Pipe | InvalidMode
produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
start() {}
```

The producer body is intentionally empty because the private adapter supplies
the measured template. Any additional declaration, host binding, parameter,
async intrinsic, or executable body statement must fail before WAT emission.

## Ownership State Machine

Both list areas and all three tickets are prepared before the first transfer
decision. Each resource is held by one list slot until the corresponding stream
write succeeds.

```text
GuestBatch0Owned -> Batch0Transferred -> HostBatch0Owned
GuestBatch1Owned -> Batch1Transferred -> HostBatch1Owned
GuestBatch0Owned/GuestBatch1Owned -> GuestDropOnFailure
Batch0Transferred + failure/cancel before batch 1 -> HostDropBatch0 + GuestDropBatch1
Batch0Transferred + Batch1Transferred -> HostDropBatch0/Batch1
```

The guest clears transferred slots before cleanup and never calls the ticket
drop import for a transferred handle. Each list allocation is released exactly
once. A cancellation terminates guest work and releases live resources; it does
not compensate an external effect already delivered to the sink.

## Probe Matrix

The hand-authored Core WAT/Rust probe must measure and assert:

| Mode | Sink receives | Required ownership result |
| --- | --- | --- |
| `ready` | `[111,222]`, `[333]` | both batches transfer; host drops all three exactly once |
| `pending` | `[111,222]`, `[333]` | one pending wake; same cleanup as ready |
| `sink-error-first` | `[111,222]` | batch 0 host-owned; batch 1 guest-owned and dropped once |
| `sink-error-second` | `[111,222]`, `[333]` | both batches host-owned and dropped once |
| `cancel-before-first` | `[]` | all three remain guest-owned and drop once |
| `cancel-after-first` | `[111,222]` | batch 0 host-owned; batch 1 guest-owned and drop once |

Every row must report two list allocations and two list releases, one stream
drop, one future drop, three created tickets, exactly-once resource cleanup, and
an empty `ResourceTable`. The probe must also reject a third list item or a
malformed list length.

## Toolchain and Stop Conditions

- Capability assembly uses `wasm-tools 1.255.0`.
- Legacy async assembly, if required by the existing runner, uses pinned
  `wasm-tools 1.254.0`.
- Runtime evidence uses Rust/Cargo `1.97.1` and Wasmtime `47.0.2`.
- Zig compiler changes are forbidden until the probe has a pinned WIT hash,
  canonical layout, and green ownership matrix.
- A Component embed/validation rejection is recorded verbatim and stops the
  promotion; no compatibility workaround or public syntax is added.

## Canonical Probe Evidence

The pinned probe passed parse, Core validation, WIT embed, Component validation,
and all six Rust/Wasmtime modes with `wasm-tools 1.255.0`, `rustc 1.97.1`, and
`cargo 1.97.1`:

```text
WIT SHA-256:  a0717b2ac8525c4b1f684a4222f66939312a19c959c66b0ace5ebca16f45299f
WAT SHA-256:  1114696249c4fd9142005ed3b7703c2642741e22e4832494df05bfc635cbd71c
```

The runtime matrix observed ordered batches `[111,222]` and `[333]` for
`ready`/`pending`, only `[111,222]` for `sink-error-first` and
`cancel-after-first`, no batch for `cancel-before-first`, and an empty resource
table with exactly three resource drops in every mode. The probe reports two
list allocations/releases, one stream drop, and one future drop per terminal.
No registry or compiler admission is implied by this evidence.

## Execution Order

1. Run the unregistered Do boundary and keep it red.
2. Assemble the hand-authored WIT/Core-WAT and run the six-mode Rust probe.
3. Only after the probe is green, add a private manifest row and exact sema
   admission.
4. Add the isolated adapter, negative fixtures, compiler Component gate, and
   full regression evidence.
