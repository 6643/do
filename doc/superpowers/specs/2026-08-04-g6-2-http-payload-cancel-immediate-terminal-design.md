# G6.2 HTTP Payload Cancellation Immediate Terminal Design

**Status:** Verified on the pinned Component/Rust/Wasmtime runtime for
`pending`, immediate `Ok(response)`, immediate `Err(DnsTimeout)`, and the
registered optional-string error discard slice.

## Decision

Keep `Future<T>` affine and keep cancellation explicit. The one newly admitted
state is an immediate completion returned by the registered
`wasi:http/client.send` descriptor before `@cancel(completion)` executes.

```do
async cancel_request(request HttpRequest) -> nil {
    completion Future<Result<HttpResponse, HttpError>> = send(request)
    @cancel(completion)
}
```

For this one source shape, `@cancel` consumes the already-terminal completion,
discards its Result, releases every owned resource in an `Ok` payload exactly
once, and returns `nil`. It does not invoke `subtask.cancel` or `subtask.drop`,
because the async-lower operation did not create a pending subtask.

The following source behavior remains intentionally unchanged:

| Case | Required behavior |
| --- | --- |
| `await(completion)` then `@cancel(completion)` | `FutureAlreadyConsumed` |
| `@cancel(completion)` twice | `FutureAlreadyConsumed` |
| completion leaves async scope unconsumed | `FutureDropped` |
| completion is pending | existing `subtask.cancel` -> terminal -> one `subtask.drop` path |

No implicit scope cancellation, idempotent cancellation, public
`own<T>`/`borrow<T>`/`ref<T>` syntax, rollback, or general async cancellation is
introduced.

## Problem Boundary

The previous private HTTP cancellation template recognized the immediate
`Status::Returned` sentinel and returned from the nil root with result-area
pointer `0`. It therefore had neither a canonical Result buffer nor a proven
response-drop path, and an immediate `Ok(response)` leaked.

The cancellation template now reserves the fixed in-module scratch range
`[64,128)`. It decodes the pinned Result discriminant at `64`, releases an
`Ok(response)` handle at `64 + 8`, accepts `Err(DnsTimeout)` (error tag `0`),
and admits the registered `DNS-error` / `InternalError` optional-string shapes.
For `Some(nonempty)`, the canonical string is released exactly once; for
`None`, the option discriminant is validated and pointer/length fields are not
read. The private allocator permits one live string at a time, and an exact
release returns its slot to idle for a later sequential invocation in the same
component instance. Other immediate errors still trap. The ordinary HTTP
service emitter remains separate because it returns the Result to a handler
rather than discarding it.

## Implementation Shape

1. Add a red compiler and Rust/Wasmtime fixture where the HTTP host returns
   immediate `Ok(response)` from `send`.
2. The probe must establish the exact canonical result-area layout and whether
   Wasmtime polls/drops the ready host Future. It must expose request consumed,
   response create/drop, host-future poll/drop, and `ResourceTable` state.
3. Allocate a valid 64-byte canonical Result buffer before calling the HTTP
   async-lower import. The cancellation template owns the fixed scratch area;
   it must not write the result to address zero or use an unproven allocation
   protocol.
4. On `Status::Returned`, decode only the pinned Result discriminant. For
   `Ok(response)`, load the owned response handle at canonical offset `8` and
   call the pinned response drop exactly once. For `DnsTimeout`, discard the
   value and return. For the registered optional-string error arms, validate
   each option discriminant and release only nonempty `Some` strings through
   the proven canonical protocol; never guess a generic `free` path.
5. Leave the pending cancellation control flow unchanged. It must not acquire
   an immediate Result payload, and it must retain one cancellation and one
   subtask drop.
6. Keep the existing semantic negative fixtures. Add no dynamic source rule:
   `await`-then-cancel and cancel-twice stay `FutureAlreadyConsumed`, while an
   unconsumed completion stays `FutureDropped`.

## Acceptance Matrix

| Mode | Expected ownership result |
| --- | --- |
| pending cancellation | request consumed once; pending Future dropped once; response create/drop zero; one subtask cancellation/drop; table empty |
| immediate `Ok(response)` cancellation | request consumed once; response created and dropped once; no subtask cancellation/drop; table empty |
| immediate `Err(DnsTimeout)` cancellation | request consumed once; response create/drop zero; no resource cleanup required; table empty |
| immediate registered payload-bearing `Err` cancellation | exact optional-string discard; `None` does not read/free payload fields |
| two sequential registered payload-bearing cancellations in one instance | each nonempty string is released exactly once; the second call reuses the released private slot |
| immediate unregistered payload-bearing `Err` cancellation | explicit trap; no fabricated payload cleanup |
| after-await / double cancel / implicit scope drop | rejected by the existing stable diagnostics |

The pinned probe records exactly one host Future poll/drop in each ready mode;
pending records at least one poll and exactly one host Future drop.

## Out Of Scope

- cancel-after-terminal without a Future owner;
- idempotent or implicit cancellation;
- arbitrary HTTP descriptors, body/trailer shapes, or error variants;
- general `Future<T>`/resource cancellation;
- external-effect rollback or compensation.

## Verification

The implementation gate must include, at minimum:

```bash
cd src && zig test build/codegen_component_wasi_http.zig
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_do_http_payload_cancellation.sh
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_rust_resource_cancellation_shape.sh
./src/build/test/run_tests.sh
git diff --check
```
