# G6.2 HTTP Payload Cancellation Design

**Status:** Bounded private slice green (2026-08-04); broader HTTP async
cancellation remains blocked.

## Scope

This slice covers only the explicit source shape:

```do
async cancel_request(request HttpRequest) -> nil {
    completion Future<Result<HttpResponse, HttpError>> = send(request)
    @cancel(completion)
}
```

It does not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference
syntax. It does not change cancellation into rollback or compensation: an
external HTTP effect already issued by `send` remains unchanged.

## Reuse Boundary

The existing private resource cancellation lowering provides the control-flow
pattern: call the async-lowered operation, distinguish immediate completion
from a pending subtask, cancel the pending subtask, drop it exactly once after
the terminal status, and return the nil task result. It cannot be copied as a
whole because the HTTP descriptor has an eight-word payload Result completion
ABI and its pinned `wasi:http/service` world only exports `handler.handle`.

The HTTP slice therefore needs a private cancellation world which imports the
pinned `wasi:http/client` interface and refers to the pinned
`wasi:http/types` request resource. The source shape must remain separate from
the public `wasi:http/service` world until that world has a matching operation.

## Gates

1. The private WIT world must assemble against the pinned `wasi:http` package
   without changing the pinned package files.
2. The generated core module must import the exact HTTP `[async-lower]send`
   and request drop symbols, and must pass the fixed private result scratch
   range `[64,128)` for this nil-returning cancellation path.
3. Pending and admitted immediate Component/Rust/Wasmtime runs must observe
   exactly-once request/future/resource cleanup and an empty resource table.
4. Cancellation after terminal completion, implicit scope-drop, double
   cancellation, and unrelated arbitrary async calls remain outside this
   bounded lowering and require explicit negative fixtures.

## Verification

The pinned service-world fragment assembles without modifying the checked-in
WASI package. The generated Core module imports the exact versioned HTTP
`[async-lower]send` and request/response drop symbols, and the nil-returning
path uses the fixed `[64,128)` result scratch. The compiler-generated Component
and the hand-written WIT/Rust/Wasmtime probe both pass for pending and the
admitted immediate modes:

```text
Rust P3 HTTP payload cancellation probe passed
request consumed=1
pending polls=1
pending future drops=1
response create=0
response drop=0
table-empty=true
WASI HTTP payload cancellation runtime passed
```

The runtime gate additionally performs two sequential admitted nonempty payload
calls in one component instance; each call consumes one request and releases
one canonical string, with no response resource left in the table.
It does not establish concurrent-call safety for the fixed private scratch area.

The accepted source shape is therefore limited to this registered HTTP
descriptor and an explicit `@cancel(completion)` call. Cancel-after-terminal,
double cancellation, implicit scope-drop cancellation, and unrelated arbitrary
async calls remain negative boundaries; payload lifting outside the registered
HTTP error shapes and general HTTP resource methods remain unsupported.
