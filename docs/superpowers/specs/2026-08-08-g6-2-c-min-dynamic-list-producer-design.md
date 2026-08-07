# G6.2 Bounded Dynamic List Producer

Status: probe in progress. This document records the private ABI evidence for
`do:g6-2-c-min-dynamic-producer@0.1.0`; it does not add public ownership syntax
to Do.

## Probe evidence

The canonical WIT source hash is
`95f6d2d616e80248a8710e10199fa3674aa80b76247f25c2e71d3d87ea4afe76`.
The hand-authored Core WAT and `wasmtime 47.0.2` runner validate the following
layout facts: list pointer `64`, list length `68`, element stride `4`, ticket
field offset `0`, and stream capacity `1`.

The runner passed the admitted lengths `0/1/2/3`, rejected `4` as
`invalid-mode` with zero ticket creation, and passed pending, sink error, early
drop, partial source creation (`2 created / 2 dropped`), cancellation before
transfer (`3 dropped`), and cancellation after transfer (`3 transferred / 0
guest drops`). Every row ended with an empty `ResourceTable`.

## Boundary

The descriptor exports one async producer:

```wit
produce: async func(count: u32) -> result<_, error-code>
```

`count` is admitted only for `0`, `1`, `2`, and `3`. A value greater than `3`
returns `invalid-mode` before list allocation or source resource creation. An
admitted call allocates one `list<resource-entry>`, creates exactly one ticket
per element with seeds `1..count`, and writes exactly one item to a capacity-one
`stream<list<resource-entry>>`.

The descriptor is intentionally separate from the immutable C-min descriptor
`do:g6-2-c-min-producer@0.1.0`. Its package hash, import names, world, and
runtime-length behavior must be measured from the hand-authored probe rather
than inferred from that earlier probe.

## Ownership transitions

1. Before list creation, the guest owns no ticket and the host `ResourceTable`
   is empty.
2. While list state is guest-owned, every created ticket is held by one list
   slot. Partial source failure releases only already-created tickets and the
   list allocation.
3. On successful stream write, ownership of every ticket transfers to the
   readable stream/host consumer. Guest slots are cleared before guest cleanup;
   the guest must not call the resource drop function for transferred tickets.
4. On sink error, early stream drop, or cancellation before transfer, the guest
   releases each still-owned ticket exactly once, then releases the list.
5. Cancellation after transfer must leave the host table empty after the
   consumer drops or extracts the transferred resources. It must not produce a
   second guest drop.
6. Invalid count has no list, ticket, stream, or host-call side effects.

## Required matrix

| Input/mode | List | Terminal result | Required cleanup |
| ---: | --- | --- | --- |
| `0` | `[]` | `Ok(())` | empty table |
| `1` | `[1]` | `Ok(())` | empty table |
| `2` | `[1, 2]` | `Ok(())` | empty table |
| `3` | `[1, 2, 3]` | `Ok(())` | empty table |
| `4` | `[]` | `Err(invalid-mode)` | zero created tickets |

The runner also exercises a pending sink, sink error, early drop, partial
source creation failure, cancellation before transfer, and cancellation after
transfer. Every terminal row must report whether resources were received,
dropped, or transferred and must end with an empty `ResourceTable`.

## Exclusions and stop conditions

This probe does not admit arbitrary producer expressions, unbounded list lengths,
nested lists, borrowed async payloads, public `own<T>`, `borrow<T>`, or `ref<T>`.
It uses one queue item and one stream capacity slot. Any mismatch in canonical
pointer/length/stride, resource-drop path, or runtime cleanup stops promotion;
the later compiler adapter must consume these measured facts exactly.

Cancellation follows WIT/Wasmtime terminal semantics. It does not roll back an
external host effect already submitted to the sink.
