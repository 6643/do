# Dynamic Stream Writer Producer Design

## Status

G6.2 bounded gate. This design does not enable general async function-call or
arbitrary producer lowering.

## Goal

Admit one descriptor-specific dynamic producer shape where the exported async
root receives a `u64` count, writes the fixed byte `65` exactly `count` times to
a capacity-one `StreamWriter<u8>`, awaits each write, then calls the registered
sink and finalizes the writer.

## Source Contract

```do
async produce(count u64) -> Result<nil, ProbeError> {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    remaining u64 = count
    loop {
        if @eq(remaining, 0) {
            break
        }
        pending Future<Result<nil, StreamError>> = writer(65)
        result Result<nil, StreamError> = await(pending)
        _ = result
        remaining = @sub(remaining, 1)
    }
    defer close(writer)
    pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return await(pending)
}
```

The parser accepts only a root `u64` parameter, `remaining u64 = count`, one
countdown loop with a zero pre-guard, literal `writer(65)`, one await/discard
per iteration, one decrement, one finalizer, and the registered sink. A second
loop, branch, dynamic byte, helper transfer, or non-pinned descriptor remains
unsupported.

## Lowering

The Component emitter keeps the existing 64-byte writer frame and uses the
existing producer-index slot at offset 52 as an `i64` remaining counter for
dynamic mode. A separate `$async-run-i64` type carries the WIT `u64` root
argument. The dynamic entry starts the sink task before pumping, so zero-count
producers can close immediately and still deliver an empty stream. The pump
decrements the remaining counter only after a write is admitted; pending
backpressure resumes through the existing write callback.

## Verification

The gate must assemble and validate a Component, then run count `0`, `1`, and
`3` through Rust/Wasmtime in pending, immediately-ready, and `Err(pipe)` sink
modes. Assertions cover byte count/order, one sink callback, and exactly-once
stream drop. Existing fixed-sequence and helper lease gates must remain green.
