# G6.2 Bounded Stream-Mirror Producer Design

**Status:** approved for the next design/implementation gate on 2026-08-03.

## Goal

Add one descriptor-bounded producer composition that mirrors a host-provided
`Stream<u8>` into a guest-created `StreamWriter<u8>`, then transfers the
readable endpoint to the already admitted sink descriptor. This proves
reader-to-writer backpressure and terminal cleanup without opening general
async-call lowering or public ownership syntax.

## Current Boundary

The existing producer emitter admits only a guest-created capacity-one
`StreamWriter<u8>` pump whose values are literals or direct `u8` parameters.
The source and sink descriptors already exist independently in the private
`do:stream-probe@0.1.0` registry. The missing composition is a single async
body that owns both a source reader/completion future and a guest writer/sink
future. The existing path-sensitive lease analysis remains the semantic
authority for the writer.

## Admitted Source Shape

The new private fixture uses the following fixed shape:

```do
probe_read = @host(
    "do:stream-probe@0.1.0",
    "read-via-stream",
    () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>
)
sink_write = @host_func(
    "do:stream-probe@0.1.0",
    "write-via-stream",
    (StreamWriter<u8>) -> Result<nil, ProbeError>
)

StreamError error = StreamClosed | StreamWriteFailed

async produce() -> Result<nil, ProbeError> {
    source Tuple<Stream<u8>, Future<Result<nil, ProbeError>>> = probe_read()
    input Stream<u8> = @get(source, 0)
    source_done Future<Result<nil, ProbeError>> = @get(source, 1)
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    defer close(writer)
    remaining u64 = 3
    loop {
        if @eq(remaining, 0) {
            break
        }
        read_pending Future<Result<u8, nil>> = @next(input)
        item Result<u8, nil> = await(read_pending)
        if @is(item, Ok) {
            value u8 = item
            write_pending Future<Result<nil, StreamError>> = writer(value)
            write_result Result<nil, StreamError> = await(write_pending)
            _ = write_result
            remaining = @sub(remaining, 1)
        } else {
            break
        }
    }
    @cancel(source_done)
    pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return await(pending)
}
```

The parser accepts only this private descriptor pair, `Stream<u8>`, capacity
one, one zero-pre-guarded loop with a literal upper bound of three reads, one
`@next` and one writer await per iteration, direct `Ok` payload binding, one
source completion cancellation, one deferred close, and one sink await. The
loop may end by reaching zero or by receiving `Err(nil)`. No second source,
second writer, nested loop, arbitrary expression, helper call, or payload
error is admitted.

## Ownership And Terminal Contract

- `input` remains the source reader owner until scope cleanup. It is never
  copied or converted to `own<T>`/`borrow<T>`.
- `source_done` is a distinct future and `@cancel(source_done)` finalizes it
  exactly once after the bounded read loop, including early EOF and sink error
  paths. For this registered descriptor the manifest exposes only
  `future-drop-readable`, so the Component lowering performs the registered
  future drop; it does not synthesize a missing future-cancel import.
- `writer` is one affine lease. `defer close(writer)` is installed before the
  first read; no path may transfer it after that defer is active.
- `reader` is transferred exactly once to `sink_write` after the source loop.
- An admitted write advances `remaining`; a pending write keeps the current
  payload in the frame until the callback reports completion.
- Sink success, sink error, source EOF, cancellation, and early consumer drop
  all release the source reader, source completion future, sink subtask,
  writer endpoint, and frame at most once. Cancellation does not roll back
  source or sink side effects.

## Lowering Architecture

Introduce a descriptor-specific `StreamMirrorPlan` beside the existing
`StreamWriterPlan`. It composes the existing stream-reader metadata with the
writer queue ABI but does not introduce a general async-call IR.

The frame extends the current writer layout with explicit source state:

- source reader handle;
- source completion future/subtask handle and its registered drop operation;
- source read pending state and result tag/payload;
- mirror loop counter;
- existing writer queue, pending payload, terminal state, and error slots.

The callback dispatcher has separate source-read, writer-write, sink-result,
and cancellation/finalization branches. Each branch transitions one state and returns to
the same waitable set. The generated Component world imports the private source
and sink interfaces and exports only `produce`; no helper is exported.

## Rejection And Compatibility Rules

The implementation must continue rejecting:

- public `own<T>`, `borrow<T>`, `ref<T>`, pointers, and references;
- arbitrary async calls or producer expressions;
- a sixth forwarding edge or any additional helper;
- dynamic loop bounds, nested loops, multiple streams, lists, variants, or
  resource-valued stream elements;
- borrowed resource fields, which the pinned Component validator rejects;
- ordinary `do build` async lowering outside the explicit Component target.

Existing fixed/parameterized producer, helper, HTTP body producer, stream
reader, and record-stream gates must remain unchanged.

## Verification Matrix

1. Plan tests accept the exact three-read mirror and reject every relaxed
   shape listed above.
2. Component lowering validates the private WIT world, emits one root export,
   records source/writer frame offsets, and contains distinct read/write
   callback states.
3. Rust/Wasmtime runs source values `[65, 66, 67]` through pending, immediate,
   source-EOF, sink `Err(pipe)`, cancellation, and consumer early-drop modes.
4. Every applicable mode observes ordered output, one source completion cancel,
   one sink callback, one source-reader drop, one writer close, one sink stream
   drop, and an empty resource table.
5. Focused Zig tests, default and `RUN_WASM=1` regressions, ReleaseSmall,
   WIT/JSON parsing, Rustfmt, shell syntax, and `git diff --check` pass.

## Non-Goals

This slice does not claim a general producer runtime, general stream
transformation, arbitrary resumable composition, a scheduler API, or complete
WASI/Component runtime support. Those require a separate ownership-state and
resumable-call design after this gate is verified.
