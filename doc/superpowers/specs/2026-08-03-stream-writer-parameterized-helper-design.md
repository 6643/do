# Parameterized Stream-Writer Helper Design

## Status

Verified complete on 2026-08-03 after the bounded G6.2 checkpoint. This is a
descriptor-specific extension, not general async call lowering. Focused
Component/Rust gates, default and WASM regressions, ReleaseSmall smoke,
formatting, shell syntax, and `git diff --check` all passed. General async
calls, additional helper hops, arbitrary producer expressions, and borrowed or
nested resource fields remain outside the admitted boundary.

## Goal

Allow the registered `do:stream-probe@0.1.0/sink.write-via-stream` producer to
transfer its `StreamWriter<u8>` lease to one private async helper that receives
the same `count u64` and `value u8` parameters as the root. The helper performs
the already-admitted zero-pre-guarded countdown pump, closes the writer, calls
the registered sink, and returns its result to the root.

## Admitted Source Shape

The only new source form is:

```do
async finish_stream(writer StreamWriter<u8>, count u64, value u8)
    -> Result<nil, ProbeError> {
    remaining u64 = count
    loop {
        if @eq(remaining, 0) { break }
        pending Future<Result<nil, StreamError>> = writer(value)
        result Result<nil, StreamError> = await(pending)
        _ = result
        remaining = @sub(remaining, 1)
    }
    defer close(writer)
    pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return await(pending)
}

async produce(count u64, value u8) -> Result<nil, ProbeError> {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
    return await(pending)
}
```

The root must create exactly one capacity-one stream and transfer the writer
once. The helper must have exactly three parameters in the shown order, use
the transferred writer as its only stream endpoint, and contain no other host
call, branch, loop, or writer termination form. The helper's Result type must
match the root and the registered sink descriptor.

## Lowering And Ownership

`StreamWriterPlan` remains the single source of truth. The plan parser records
the helper name and validates the helper's parameter names/types, but the
descriptor emitter still emits one root Component export. It lowers the helper
body directly into the existing `(i64, i32) -> i32` async entry and frame:

- offset `52`: remaining `i64` countdown;
- offset `60`: producer `u8` value stored as an `i32` word;
- root arguments initialize both slots before the sink is started;
- the sink is registered before the first pump, including `count=0`;
- each admitted write is awaited before decrementing remaining;
- terminal callback drops the sink subtask, finalizes the writer, and returns
  the descriptor-defined Result tag exactly once.

The helper is a source-shape adapter only. No public `own<T>`, `borrow<T>`, or
`ref<T>` syntax is added; no arbitrary async call or helper nesting is admitted;
the existing one-hop forwarding and fixed helper gates remain unchanged.

## Rejections

Reject all of the following with the existing unsupported Component lowering:

- helper parameter order or types other than `(StreamWriter<u8>, u64, u8)`;
- root/helper count or value expressions other than direct parameter transfer;
- a helper that creates another stream, calls another helper, writes a literal,
  omits `defer close(writer)`, or calls a different descriptor;
- a third helper hop, arbitrary async call, arbitrary producer expression,
  non-`u8` stream element, or public ownership/reference type.

## Verification Matrix

1. Zig plan tests prove the exact accepted helper shape and reject parameter
   reordering, literal writes, and a second helper hop.
2. Component lowering compares the generated WIT with the existing
   parameterized sidecar and checks the `(i64, i32)` export, frame slots,
   helper-transfer marker, dynamic pump, and absence of a second export.
3. Rust/Wasmtime runs `count=0/1/3`, `value=90` in pending, ready, and
   `Err(pipe)` modes. Each case requires ordered bytes, one sink callback, one
   writer drop, and the same pending-poll behavior as the root producer.
4. The focused gates, default regression, `RUN_WASM=1`, ReleaseSmall smoke,
   formatting, shell syntax, and `git diff --check` must remain green.

## Non-Goals

This checkpoint does not implement general async function calls, arbitrary
producer expressions, borrowed/nested/variant resource fields, payload-bearing
completion errors, or arbitrary filesystem async methods.
