# Stream Writer Source Pump Design

**Status:** approved for the next implementation slice on 2026-08-01.

## Goal

Generalize the registered `wasi:cli/stdout.write-via-stream` `stream<u8>` guest
producer path from the current fixed two-item fixture to a bounded source-level
sequence of `writer(value)` operations, while preserving the existing
descriptor-owned Component ABI and ordinary-build guard.

## Scope

- Admit only the existing registry descriptor and `StreamWriter<u8>` shape.
- Accept a bounded linear sequence of `u8` literals or `u8` bindings followed by
  `writer(value)` and `await` of each write Future.
- Preserve explicit capacity, FIFO/backpressure, terminal close, host error, and
  consumer early-drop behavior.
- Keep arbitrary payload layouts, dynamic source iteration, external writable
  endpoints, and WIT `abort` error mapping outside this slice.

## Non-goals

No new public reference, ownership, pointer, or scheduler syntax is added. The
compiler still emits `UnsupportedP3AsyncComponent` for ordinary `do build` and
for unregistered stream shapes.

## Design

`StreamWriterPlan` owns an ordered source sequence rather than a semantic
two-item special case. The parser records each scalar value and the source
position of its write/await pair, rejects missing awaits and more than the
bounded plan capacity, and carries the descriptor's queue capacity into the
emitter. The Component emitter stores the sequence in one data segment and
uses one resumable `$writer-pump-step` state machine. A completed stream-write
event advances exactly once; a blocked write retains the current item and
joins the writable stream handle; a dropped/error status marks the terminal path
without re-promoting the item. The frame initializes all queue/lease fields
before the first write and never drops an endpoint twice.

## Verification

Unit tests assert ordered plan capture, max-sequence rejection, and generated
state markers. Rust/Wasmtime fixtures execute three, zero, and capacity-full
sequences in pending, early-drop, and host-error modes, checking item order and
exactly-once reader/writer cleanup. The full regression must remain green and
ordinary async build rejection must remain unchanged.
