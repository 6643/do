# G6.2 Private Nested-Owned-Resource Record Producer Design

> Status: approved bounded probe (2026-08-30). This document authorizes one
> private, fixed-shape evidence route only. It does not open public ownership
> syntax or general producer/resource lowering.

## Goal

Measure and, if the measured contract is stable, admit exactly one producer
shape whose stream element is an outer record containing one nested record with
one owned `ticket` resource:

```text
Outer {
    inner: Inner
}

Inner {
    ticket: Ticket
}
```

The corresponding WIT field is `inner.ticket: own<ticket>`. The probe is the
next bounded step after the closed direct `ResourceTriple` producer route. It
must establish nested canonical layout, recursive ownership cleanup, and the
transfer boundary before any broader nested producer work is considered.

## Scope and non-goals

The probe includes only:

- one new private `do:` descriptor and one pinned WIT world;
- two WIT record declarations, `inner` and `outer`;
- one `ticket` resource owned at the leaf `inner.ticket`;
- one source `make-ticket(seed: u32) -> own<ticket>` import;
- one asynchronous sink consuming `stream<outer>`;
- one capacity-one stream and at most one record write per invocation;
- finite ready, pending, error, cancellation, early-drop, repeat, and invalid
  lifecycle modes;
- compiler admission only behind the existing opt-in P3 Component route.

This probe does not:

- add public `own<T>`, `borrow<T>`, `ref<T>`, `Option`, or `Result` syntax;
- add generic producer IR, arbitrary producer expressions, or general async
  lowering;
- admit borrowed, list, variant, mixed, multiple-owned, or deeper nested
  resource payloads;
- change the existing direct, pair, parameterized-pair, or triple descriptors;
- change the default route or the GC migration inventory;
- claim full GC cutover or ARC/GC semantic-equivalence completion.

## Pinned WIT surface

The probe source must contain this exact WIT text, including the final newline.
The implementation gate computes its SHA-256 and stores that value in the new
manifest row; any source or hash drift rejects admission.

```wit
package do:g6-2-owned-record-nested-producer@0.1.0;

interface types {
  enum error-code { io, pipe, invalid-mode }
  resource ticket {}
  record inner {
    ticket: own<ticket>,
  }
  record outer {
    inner: inner,
  }
}

interface source {
  use types.{ticket};
  make-ticket: func(seed: u32) -> own<ticket>;
}

interface sink {
  use types.{error-code, outer};
  consume-via-stream: async func(
    data: stream<outer>
  ) -> result<_, error-code>;
}

world owned-record-nested-producer {
  use types.{error-code};
  import source;
  import sink;
  export produce: async func(mode: u32) -> result<_, error-code>;
}
```

The contract identifiers are fixed:

| Item | Exact value |
| --- | --- |
| package | `do:g6-2-owned-record-nested-producer@0.1.0` |
| source instance | `do:g6-2-owned-record-nested-producer/source@0.1.0` |
| sink instance | `do:g6-2-owned-record-nested-producer/sink@0.1.0` |
| world | `owned-record-nested-producer` |
| source member | `make-ticket` |
| sink member | `consume-via-stream` |
| export member | `produce` |
| descriptor effect | `record-resource-nested-stream-producer` |

## Exact Do adapter shape

The compiler fixture is intentionally an adapter sentinel. The accepted source
topology is:

```do
make_ticket = @host_func("do:g6-2-owned-record-nested-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
consume = @host_async_func("do:g6-2-owned-record-nested-producer@0.1.0", "consume-via-stream", (StreamWriter<Outer>) -> Result<nil, ProducerError>)
Ticket = @wasi_resource("do:g6-2-owned-record-nested-producer/source/ticket", { .id i64 })
Inner {
    .ticket Ticket
}
Outer {
    .inner Inner
}
ProducerError error = Io | Pipe | InvalidMode
produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
start() {}
```

The matcher must require exactly two host bindings, one resource declaration,
two record declarations, one error declaration, one `produce`, one `start`, and
no `async` token or `@async`, `@await`, or `@cancel` intrinsic in the fixture.
The private template supplies the async Component export; the sentinel body is
not general Do async lowering.

## Canonical ABI hypothesis to measure

The independent hand-authored WAT/WIT probe must measure every value below and
fail closed on any difference. The expected values are based on the existing
two-level nested record-stream evidence, but this producer route gets its own
hash and gate.

| Property | Required measured value |
| --- | --- |
| stream element | `outer` |
| outer record alignment | 4 bytes |
| outer record byte size | 4 bytes |
| flattened leaf core field | `i32` at offset 0 |
| source ownership path | `inner.ticket` |
| leaf ownership | `own` |
| leaf resource | `ticket` |
| resource drop import | `[resource-drop]ticket` |
| stream capacity | 1 |
| source core signature | `(i32) -> (i32)` |
| producer input words | `(i32 mode)` |
| canonical boundary | no Wasm GC reference type |

The nested record names and field path are semantic metadata. If the canonical
ABI flattens `inner.ticket` to the outer record slot at offset `0`, the emitter
must still preserve and validate the nested path; it may not treat the source
as a direct `outer.ticket` field.

## Ownership and transfer contract

The frame has one guest-owned leaf bit and one transfer bit:

```text
bit 0: inner.ticket guest-owned
bit 1: nested record transferred
```

Required invariants:

1. `mode = 255` is rejected before stream, task, or ticket allocation.
2. Valid modes call `make-ticket(111)` exactly once.
3. The leaf handle is stored in the measured canonical slot before bit 0 is
   set. Handle value `0` is valid when bit 0 is set.
4. A pending or failed stream write transfers no ownership.
5. A successful complete-record write clears bit 0 and sets bit 1 as one
   transfer transition.
6. Before transfer, cleanup walks the nested path and drops `inner.ticket`
   exactly once.
7. After transfer, guest cleanup performs no ticket drop; the host drops the
   lifted ticket exactly once.
8. Stream, task/future, waitable, and frame cleanup remains exactly once on all
   terminal paths.

The nested container is not independently owned. It is a value container whose
only transitive owned leaf is `inner.ticket`; no extra resource drop may be
invented for `inner` or `outer`.

## Lifecycle matrix

The Rust/Wasmtime runner uses one `Store` per mode except `repeat`, which runs
two invocations in one store and resource table.

| Mode | Sink behavior | Expected ticket observation |
| --- | --- | --- |
| `ready` (`0`) | read outer and complete `Ok` | `[111]` |
| `pending` (`1`) | remain pending once, then read and complete | `[111]` |
| `sink-error-before` (`2`) | return `Err(io)` without reading | `[]` |
| `sink-error-after` (`3`) | read outer, then return `Err(pipe)` | `[111]` |
| `cancel-before-transfer` (`4`) | remain pending; cancel before write acceptance | `[]` |
| `cancel-after-transfer` (`5`) | accept outer; cancel after transfer | `[111]` |
| `early-drop-before-transfer` (`6`) | drop task/future before write acceptance | `[]` |
| `early-drop-after-transfer` (`7`) | accept outer; drop task/future after transfer | `[111]` |
| `repeat` (`8`) | run ready twice in one store | `[111, 111]` |
| `invalid` (`255`) | reject before setup | `[]` |

Every valid invocation must observe one ticket creation and exactly one ticket
drop, one stream cleanup, one task/future cleanup, and `table-empty=true`.
The four cancellation/early-drop modes must record one pending-future drop and
one host-task cancel with zero completion calls. `repeat` must prove that the
same store can be reused without a leaked nested handle.

## Negative boundary

The focused negative gate must reject one contract fact per fixture, including:

- direct `Outer.ticket` instead of nested `Outer.inner.ticket`;
- renamed or reordered `inner`/`ticket` fields;
- an extra field in either record;
- a third nested record level;
- `borrow<ticket>` or a non-resource leaf;
- list, variant, or mixed payload in `Inner`;
- wrong stream element, marker, descriptor, result, or host marker;
- changed WIT hash, package, world, or source module;
- wrong source arity, seed behavior, or async intrinsic in the sentinel body.

Each mutation must be rejected before WAT emission and must not widen an
existing descriptor.

## Admission gate and stop conditions

Admission requires all of the following independent evidence:

- exact WIT source and pinned SHA-256;
- canonical WAT parse/embed/Component validation with `wasm-tools 1.255.0`;
- exact nested source matcher and fail-closed negative fixtures;
- measured `outer` layout and `inner.ticket` path markers;
- no `__arc_` marker and no GC reference crossing the canonical boundary;
- all lifecycle rows, exactly-once cleanup, and empty `ResourceTable`;
- canonical/generated WAT and WIT parity;
- unchanged existing direct/pair/parameterized-pair/triple route evidence;
- unchanged migration inventory `complete_rows=15 pending_rows=15` with exit 1.

Any mismatch leaves this shape pending, removes only its uncommitted probe
artifacts, and preserves the already closed routes. A green probe permits a
separate bounded compiler admission, but does not authorize general nested
producer lowering or public ownership syntax.
