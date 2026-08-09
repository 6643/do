# Private Async Host Scalar-Argument Promotion

Date: 2026-08-09
Status: design frozen for M1; compiler promotion is not implemented

## Decision

M1 admits one private, opt-in source shape that passes a single `u32` from a
colorless Do helper into one registered asynchronous host operation. The
capability is identified by the private descriptor effect
`async-host-scalar-argument` and is selected only by the future
`--p3-async-host-arg-component` target. It does not alter default, v1, or v2
dispatch, and it does not add public ownership or lifetime syntax.

Ordinary functions remain colorless. `@async(call)` is the only source-level
creation of a user-function `Future`; the registered `@host_async_func` member
is the only direct host operation that produces this private future shape.

## Exact Accepted Source Shape

The positive source contract is exact, including names, types, operation count,
and the root literal:

```do
work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)

helper(value u32) -> nil {
    pending Future<nil> = work(value)
    @await(pending)
}

run() -> nil {
    child Future<nil> = @async(helper(7))
    @await(child)
}
```

The analyzer must match this source shape by tokens and descriptor data. The
helper is an internal continuation: it has no independent task-return,
async-lift, WIT export, or child task endpoint. `run` is a normal `() -> nil`
function with one explicit child and one await. The host call, helper await,
root child creation, and root await are each singular; an implementation must
reject additional operations before WAT emission.

The `7` argument is a literal admission requirement. A variable, call,
arithmetic expression, or any other dynamic root expression is outside M1.
The helper parameter is named and typed `u32`; its value is passed to `work`
without conversion or inference. The host binding must use the
`@host_async_func` marker. A synchronous `@host_func` declaration with the
same locator is not an async binding.

## Pinned Descriptor And WIT Identity

The registry entry consumed by the future implementation is private and must
validate all of the following fields before source admission:

| Field | Required value |
| --- | --- |
| locator | `do:async-call-arg-probe/host@0.1.0` |
| member | `work` |
| effect | `async-host-scalar-argument` |
| params | `[u32]` |
| result | `nil` |
| WIT package | `do:async-call-arg-probe@0.1.0` |
| WIT world | `probe` |
| WIT interface/member | `host.work` |
| WIT SHA-256 | `b9f5f8355e87231317ec05cccf692ee465c6f339bd509640aedc196e58f81e61` |
| canonical core params/results | `[i32]` / `[]` |
| completion | `task-return` with no completion parameters |
| async import | module `do:async-call-arg-probe/host@0.1.0`, name `[async-lower]work` |

The source WIT is the checked-in `examples/p3-runtime/wit/async-call-arg-probe.wit`:

```wit
package do:async-call-arg-probe@0.1.0;

interface host {
  work: async func(value: u32);
}

world probe {
  import host;
  export run: async func();
}
```

The registry is the source of truth for admission. Locator/member names must
not be used to infer an ABI, and a changed WIT hash, signature, completion
shape, or import name is a fail-closed mismatch.

## Root Frame And Canonical ABI

The hand-authored canonical module
`examples/p3-runtime/async-call-arg-probe-canonical.wat` measures one
root-owned frame with 4-byte alignment and 20 bytes of storage:

| Offset | Slot | Contract |
| ---: | --- | --- |
| `@0` | waitable-set | one root waitable-set handle |
| `@4` | active host subtask | encoded Component subtask/future handle; sentinel means none |
| `@8` | helper phase | continuation state used by the root callback |
| `@12` | argument | one flat `u32` represented as Core `i32` |
| `@16` | reserved tail | padding/unused tail required by the measured 20-byte frame |

The emitter must preserve this measured layout and its marker words. It must
not treat `@12` as a general argument area, infer other scalar types, or reuse
this frame for payload/resource/list/stream futures without a new probe.
The root context points to the frame while the operation is live. Only the
root `run` async-lift and callback endpoints are emitted.

## Lifecycle And Cleanup

The host call stores the argument at `frame + 12` before invoking
`[async-lower]work` with one `i32` parameter. The callback resumes the helper
from the root context and may load the same slot to establish continuation
state. The host observes the value `7`.

Normal completion is ordered and exactly once:

1. drop the completed active subtask;
2. drop the waitable set after no callback can use the frame;
3. clear the root context;
4. free the root-owned frame;
5. call root `task-return` for `run`.

External cancellation (callback event `6`) first cancels the active subtask,
then drops that subtask, and performs the same waitable-set, context, and frame
cleanup before calling root `task-cancel`. A sentinel/no-subtask path must not
double-cancel or double-drop. Cancellation does not roll back a host effect
that was already issued. Every terminal path therefore reaches a verifiable
state with no live subtask, waitable set, context, or frame owned by the root.

## Fail-Closed Red Boundaries

The planner exposes one public target error,
`UnsupportedP3AsyncHostArgComponent`, for every rejected source shape. For
diagnostic stability and future tests, it also assigns the following stable
reason identifiers before mapping to that umbrella error:

| Boundary | Stable reason identifier | Required behavior |
| --- | --- | --- |
| locator/member absent from the pinned registry | `UnknownP3AsyncHostDescriptor` | reject before WAT; never infer a host ABI |
| `@host_func` marker or synchronous effect | `P3AsyncHostArgMarkerMismatch` | reject; do not reinterpret as async |
| host parameter is not exactly `u32` | `P3AsyncHostArgTypeUnsupported` | reject any conversion or inferred flat type |
| host has two or more arguments | `P3AsyncHostArgArityUnsupported` | reject; M1 has one argument only |
| root argument is dynamic/non-literal | `P3AsyncHostArgDynamicRoot` | reject before frame materialization |
| helper returns a payload or non-`nil` result | `P3AsyncHostArgHelperPayload` | reject; helper remains unit-only |
| nested helper/async helper topology | `P3AsyncHostArgNestedHelper` | reject; only one internal helper continuation |
| second child or second live host operation | `P3AsyncHostArgMultipleChildren` | reject; no overlap or fan-out |
| resource, list, or stream payload (including nested forms) | `P3AsyncHostArgPayloadUnsupported` | reject before WAT; requires a separate canonical ownership design |
| legacy `async` declaration | `P3AsyncHostArgLegacyAsyncDecl` (front-end `InvalidAsyncReturn`) | reject; ordinary declarations stay colorless |

The same fail-closed rule applies to extra awaits, an independent helper task
endpoint, public `own<T>`/`borrow<T>`/`ref<T>`/pointer/reference/lifetime
syntax, branches/loops/recursion, arbitrary producer expressions, changed
descriptor metadata, and any default-target invocation. Those conditions map
to `UnsupportedP3AsyncHostArgComponent` (or the existing front-end diagnostic
where parsing/sema owns the boundary) and must not produce partial WAT.

## Implementation Interfaces

Later registry work consumes the exact descriptor table above and validates
WIT/package/member/hash/core import drift. Later sema/planner work produces an
immutable plan containing the matched host binding, helper/root names, literal
`u32`, and fixed continuation states. Later codegen consumes only that plan and
emits the measured 20-byte frame, argument-store/load markers, root callback,
and ordered cleanup. None of these layers may parse arbitrary WIT or infer
generic `Future<T>` lowering from this descriptor.

The target is opt-in and mutually exclusive with other Component targets. The
normal compiler, default `do build`, v1/v2 dispatch, public syntax, and all
existing probe artifacts remain unchanged.

## Evidence And Promotion Gate

The probe evidence is recorded in `doc/roadmap_status.md:49-67` and the
canonical artifacts named above. It reports the pinned WIT hash, a 20-byte
4-byte-aligned frame with the argument at `@12`, host observation `7`, and
ready/pending/cancel cleanup with an empty `ResourceTable`. Current and legacy
`wasm-tools` routes assemble and validate the hand-authored Component. This is
ABI evidence only; it does not authorize general async-call lowering.

Compiler promotion may begin only after the registry, strict planner,
generated WIT/Core WAT, negative fixtures for every red boundary, and the
Rust/Wasmtime ready/pending/cancel gate all pass, followed by the full
regression suite. A failed gate leaves this design and all existing probes
unchanged and records the exact failure.
