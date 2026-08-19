# Parameterized Stream-Writer Forwarding Helper Design

## Status

Verified complete on 2026-08-03. This is a descriptor-specific extension of
the verified parameterized helper producer, not general async call lowering or
public ownership syntax. Focused parser/emitter tests, Component/Rust/Wasmtime
gates, default/WASM regressions, ReleaseSmall smoke, formatting, shell syntax,
and diff checks all passed; general async/resource boundaries remain pending.

## Goal

Allow one private async forwarding helper to pass a guest
`StreamWriter<u8>` lease and the root's `count u64` and `value u8` parameters
to the already-admitted final countdown helper. The Component emitter still
exports only `produce` and reuses the existing `(i64, i32)` frame.

## Admitted Source Shape

```do
async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
    remaining u64 = count
    loop {
        if @eq(remaining, 0) { break }
        write_pending Future<Result<nil, StreamError>> = writer(value)
        write_result Result<nil, StreamError> = await(write_pending)
        _ = write_result
        remaining = @sub(remaining, 1)
    }
    defer close(writer)
    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return await(sink_pending)
}

async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
    return await(pending)
}

async produce(count u64, value u8) -> Result<nil, ProbeError> {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
    return await(pending)
}
```

The root and forwarding helper must transfer all three arguments directly and
in order. The forwarding helper has no writer write, close, abort, sink call,
stream creation, branch, or second call. The final helper remains exactly the
verified zero-pre-guarded countdown shape.

## Lowering And Rejections

`StreamWriterPlan` records the root's direct transfer and marks the immediate
helper as the producer helper. The existing countdown emitter emits one
`[async-lift]produce` export, stores `count` at frame offset `52` and `value`
at offset `60`, and keeps the same callback/drop protocol. No helper function
is exported and no general async call IR is introduced.

Reject reordered or renamed arguments, literals, missing root/forward await,
forwarder writes or finalization, a helper-created stream, a third helper hop,
an altered Result type, a non-`u8` element, and any other async call. Public
`own<T>`, `borrow<T>`, `ref<T>`, pointer, and reference syntax remain absent.

## Verification Matrix

1. Async-plan tests accept the exact three-function shape and reject argument
   reordering plus a third forwarding hop.
2. Component lowering validates the existing parameterized WIT sidecar,
   offsets `52`/`60`, one root export, and no helper export.
3. Rust/Wasmtime runs `count=0/1/3`, `value=90`, pending/ready/`Err(pipe)`;
   each case observes ordered bytes, one host callback, and one stream drop.
4. Default regression, `RUN_WASM=1`, ReleaseSmall smoke, formatting, shell
   syntax, and `git diff --check` remain green.

## Non-Goals

This checkpoint does not implement general async calls, arbitrary producer
expressions, more than one forwarding hop, borrowed/nested/variant resource
fields, payload-bearing completion errors, or arbitrary filesystem async
methods.
