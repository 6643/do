# G6.2 Private Resource Result Terminal Design

**Status:** approved for the current continuation by the existing bounded-slice decision.

## Goal

Extend the already implemented private `do:resource-probe/http` async resource
Result probe with a no-payload `Err(failed)` completion. Preserve the existing
`Ok(own<response>)` pending/immediate paths and prove that request consumption,
response creation/drop, and result-buffer release happen exactly once.

## Scope

The WIT package, world, resource declarations, and Core ABI remain fixed:

```wit
send: async func(request: request) -> result<response, error-code>;
```

The Do source remains value-based:

```do
send = @host_func("do:resource-probe/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
```

This slice adds only:

- a host-completed `Err(failed)` branch;
- a Rust/Wasmtime assertion for a ready error completion.

It does not add payload-bearing errors, arbitrary resource Result shapes,
general async-call composition, public `own<T>`/`borrow<T>`/`ref<T>`, or a
generic scheduler.

## Alternatives

### A. Shared fixed resource-result terminal path (selected)

Use one emitter helper for success and error cleanup. On a ready error callback,
store zero in the response payload word and the received error tag in the
result tag word, then invoke the existing task-return and frame cleanup path.
This keeps the fixed two-word result buffer and adds only the missing terminal
branch.

### B. Add a second resource-result descriptor

This would exercise registry selection but duplicate the fixed emitter and
runtime proof. It adds no ownership invariant, so it is rejected.

### C. Generalize resource Result payloads

This would require canonical layouts for arbitrary resource/list/variant/error
payloads and a new ownership contract. It is outside this slice and remains
blocked.

## State and cleanup contract

| Event | Required result | Required cleanup |
| --- | --- | --- |
| pending then `Ok(response)` | return owned response | request consumed once; response created and caller-dropped once; result buffer released once |
| immediate `Ok(response)` | return owned response | same as pending path |
| ready `Err(failed)` | return error tag, zero response payload | request consumed once; no response create/drop; result buffer released once |
Cancellation is a separate source-shape decision. The current resource-result
source has no `@cancel` operation, so this slice does not claim cancellation
support for the resource-result emitter.

## Core callback rule

The existing callback treats ready tag `2` as `Ok`. The new branch treats any
registered error tag (`1` for `failed`) as terminal too. It writes:

```text
result_area[0] = 0          // no response handle on Err
result_area[1] = error_tag
task-return(result_area[0], result_area[1])
```

Both branches then release the canonical buffer, clear the context, and free
the frame exactly once. A non-ready callback still returns the waitable token
without touching result storage.

## Verification gates

1. A Zig emitter test requires the error terminal branch and zero-payload store.
2. The Do lowering gate validates the unchanged WIT, resource-drop imports, and
   error terminal marker.
3. Rust/Wasmtime runs pending success, immediate success, and ready error. It
   observes request consumption, response create/drop, and an empty
   `ResourceTable`.
4. Existing G6.2 matrix, negative gates, default/WASM regression, ReleaseSmall,
   Rustfmt, Cargo, JSON, and diff checks remain green.

## Explicit non-goals

- no public ownership or reference syntax;
- no payload-bearing completion error;
- no resource-result cancellation without an explicit `@cancel` source shape;
- no arbitrary producer or async-call lowering;
- no sixth forwarding or seventh nested resource level;
- no real WASI/HTTP host integration beyond the private probe.
