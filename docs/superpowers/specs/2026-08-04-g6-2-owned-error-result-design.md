# G6.2 Owned-Error Result Design

## Status

Implemented and verified as a private descriptor-bound slice. The pinned
Component assembly, generated Do lowering, hand-written Component, and
Rust/Wasmtime ownership matrix all pass for pending/immediate `Ok`, ready
`Err(error-resource)`, and explicit cancellation. This spec is closed for the
registered shape; it does not authorize arbitrary resource Result payloads.

## Fixed shape

The new descriptor is private and separate from the existing
`do:resource-probe/http@0.1.0` descriptor:

```wit
package do:resource-probe-owned-error@0.1.0;

interface http {
  resource request {}
  resource response {}
  resource error-resource {}

  send: async func(request: request) -> result<response, error-resource>;
}
```

The `Ok` arm owns a response handle. The `Err` arm owns an error-resource
handle. The guest must release whichever arm it receives; the host must not
drop a result resource before the transfer is complete.

## Required runtime observations

| Mode | Request | Result resource | Other result resource | Table |
| --- | ---: | ---: | ---: | --- |
| pending `Ok` | consumed once | response created/dropped once | error-resource zero | empty |
| immediate `Ok` | consumed once | response created/dropped once | error-resource zero | empty |
| ready `Err` | consumed once | error-resource created/dropped once | response zero | empty |
| explicit cancel | consumed once | no result resource | no response | empty |

Explicit `@cancel(completion)` consumes the pending completion and drops its
subtask exactly once. It never rolls back an external effect.

## Boundaries

This probe does not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax. It does
not generalize arbitrary result payloads, producer leases, lists, variants,
forwarding depth, or filesystem async methods. A pinned toolchain rejection is a
no-go for this slice and must not be bypassed with a fake lowering.
