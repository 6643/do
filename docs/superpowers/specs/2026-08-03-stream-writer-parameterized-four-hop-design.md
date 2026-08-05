# Parameterized Stream-Writer Four-Hop Design

## Status

This is a bounded G6.2 descriptor-specific extension. It does not add public
`own<T>`, `borrow<T>`, or `ref<T>` syntax and does not implement general async
call lowering.

## Admitted Shape

The registered `do:stream-probe@0.1.0` producer admits exactly four private
forwarding helpers:

`produce -> outer_stream -> entry_stream -> forward_stream -> middle_stream -> finish_stream`

Every forwarding helper passes `(writer, count, value)` unchanged and awaits one
same-typed result. `finish_stream` retains the existing `u64` countdown,
`StreamWriter<u8>` pump, sink callback, and `defer close(writer)` cleanup.

Component lowering still emits only `produce`, and frame offsets remain 52 and
60. Pending, ready, and `Err(pipe)` runtime gates cover counts `0/1/3` and value
`90`, with one host callback and one stream drop per run.

## Rejection Boundary

The fifth forwarding edge remains rejected, as do crossed/literal arguments,
arbitrary async calls, arbitrary producer expressions, non-`u8` elements,
borrowed/list/variant resource fields, and broader filesystem async methods.
