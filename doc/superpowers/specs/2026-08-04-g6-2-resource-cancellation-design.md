# G6.2 Private Resource Result Cancellation Design

**Status:** source-shape decision, pinned ABI probe, and bounded private lowering
implemented.

## Goal

Define the cancellation source shape for a private async resource Result call
without changing the public ownership model or promising rollback of external
effects.

## Source Shape

The selected source form is:

```do
async cancel_request(request HttpRequest) -> nil {
    completion Future<Result<HttpResponse, HttpError>> = send(request)
    @cancel(completion)
}
```

`@cancel(completion)` is an explicit affine consumer of the named Future. It is
valid only in an async body, and it consumes the Future exactly once. The
resource Result value is not exposed as a cancellation Result branch.

## Alternatives

### A. Explicit cancellation (selected)

The source names the completion being cancelled. The emitter lowers the
registered Component subtask handle directly through `subtask.cancel`, waits
for the ABI terminal status, drops the subtask, and returns the nil task result.
This is observable, testable, and does not require an implicit reference or
borrow lifetime model.

### B. Implicit cancellation on scope exit (rejected)

Dropping a Future binding at scope exit would make a hidden control-flow edge
perform host-visible cleanup. Do has no implicit reference/borrow lifetime
semantics, so this would make ownership and cancellation order ambiguous. It
also conflicts with the existing affine diagnostics for dropped or reused
Futures.

## ABI Contract

The pinned legacy Component async profile is authoritative:

1. `send` consumes the request resource before returning its subtask handle.
2. A pending subtask handle is converted to its subtask index and passed to
   `subtask.cancel`.
3. Cancellation must return the pinned terminal status `4`; any other status is
   a runtime failure for this probe.
4. The same subtask index is then passed to `subtask.drop` exactly once.
5. The guest task returns nil through its task-return import. This no-`await`
   cancellation source does not allocate a result frame or canonical result
   buffer; the pending subtask is the only live child handle.
6. A pending host future is dropped; no response resource is created or
   dropped; the resource table is empty after the call.

Cancellation does not undo a request already handed to the host. Database,
network, and other external side effects remain the responsibility of the host
API and its business protocol. No operation ID, cancellation acknowledgement,
rollback callback, or compensation transaction is introduced.

## Probe Boundary

The positive probe is both a generated Core module and a hand-written Core module
paired with the pinned WIT world. The generated path proves that the private
resource-result emitter produces the same ABI sequence; the hand-written path
keeps an independent ABI baseline for the Wasmtime host observation.

The probe does not claim:

- general Future/Stream cancellation lowering;
- implicit Future scope-drop cancellation;
- double cancellation or cancellation after a terminal completion as valid
  operations;
- arbitrary async calls, producer leases, or public `own<T>`/`borrow<T>`/`ref<T>`
  syntax;
- rollback or compensation for already-issued external effects.

## Verification

- `test_do_resource_cancellation_shape.sh` validates generated Do WAT/WIT,
  pinned `wasm-tools 1.254.0` assembly, and negative source boundaries for
  implicit scope-drop, double cancellation, and cancellation after terminal
  consumption.
- `test_rust_resource_cancellation_shape.sh` runs the resulting Component under
  Wasmtime `47.0.2` and checks request consumption, pending-future drop,
  response create/drop counters, and an empty `ResourceTable`.
- Existing scalar/clock cancellation fixtures remain the evidence for the
  already-supported non-resource cancellation path.
