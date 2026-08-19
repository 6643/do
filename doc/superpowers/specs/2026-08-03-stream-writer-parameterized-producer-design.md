# Parameterized Dynamic Stream Writer Producer

## Status

Implemented as a bounded G6.2 checkpoint on 2026-08-03.

## Scope

The registered `do:stream-probe@0.1.0` sink admits one additional guest producer
shape:

```do
async produce(count u64, value u8) -> Result<nil, ProbeError>
```

The producer creates a capacity-one `StreamWriter<u8>`, uses one zero-guarded
countdown loop, writes the same `value` parameter each iteration, awaits and
discards the write result, decrements only after admission, then calls the
registered sink once and closes the writer once. The Component export uses the
core `(i64, i32) -> i32` async entry shape; the value is retained in the writer
frame at offset 60 and copied to the one-byte source buffer immediately before
each enqueue.

## Safety Boundary

This does not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax, general
async-call lowering, arbitrary producer expressions, or arbitrary WIT stream
descriptors. The existing literal countdown, fixed sequence, and helper lease
gates remain unchanged. Unsupported shapes continue to fail plan analysis.

## Verification

The Component gate checks the generated WIT, async entry type, frame value
offset, byte store/load, and Component validation. The Rust/Wasmtime gate runs
`count=0/1/3` with `value=90` in pending, ready, and `Err(pipe)` modes and
asserts ordered bytes, one sink callback, and one stream drop per call.
