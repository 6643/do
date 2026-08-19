# G6.2 Variant-Owned Ticket Stream Design

**Status:** Canonical ABI probe verified on the pinned toolchain. No compiler
lowering is enabled by this document.

**Goal:** Establish whether one private `stream<event>` shape can carry an
`own<ticket>` in one WIT variant branch while correctly handling the two
non-owning branches, asynchronous completion, and exact-once cleanup. This is
not a proposal for public Do ownership or reference syntax.

**Pinned environment:** Zig `0.16.0`, Rust `1.97.1`, `wasm-tools 1.254.0`, and
Wasmtime `47.0.2`. A toolchain upgrade invalidates all probe evidence.

## Decision And Boundary

The probe uses one hand-written private WIT world:

```wit
package do:variant-resource-stream-canonical@0.1.0;

interface types {
  enum error-code { io }
}

interface source {
  use types.{error-code};
  resource ticket {}

  variant event {
    ticket(own<ticket>),
    idle,
    failed(error-code),
  }

  read-via-stream: func() -> tuple<
    stream<event>,
    future<result<_, error-code>>,
  >;
}

interface probe {
  use types.{error-code};
  run: async func() -> result<_, error-code>;
}

world variant-resource-stream-canonical {
  import types;
  import source;
  export probe;
}
```

`ticket` is the only owning case. `idle` has no payload. `failed(error-code)`
is a source event with an error value, not a substitute for the completion
future's `result`. The guest consumes the one stream event and always reaches a
defined terminal path for both endpoints. A `failed(io)` event is surfaced as
the probe result after its completion endpoint has been closed; a completion
`Err(io)` remains a distinct terminal path.

The first positive slice is deliberately bounded:

- one call to `read-via-stream`;
- at most one stream read and one event;
- one completion future poll sequence;
- one owned ticket in the `ticket` branch only;
- one shared cleanup helper for terminal, error, and early-drop paths.

No public `own<T>`, `borrow<T>`, `ref<T>`, variant declaration syntax,
registry entry, generic variant lowering, or production Do fixture is added.
The existing compiler rejection for unregistered shapes remains authoritative.

## Why This Shape

The existing temporary WIT acceptance check establishes only that the pinned
`wasm-tools component embed` accepts an `own<ticket>` variant payload. Its two
cases, `ticket` and `empty`, do not establish canonical layout, runtime
ownership transfer, branch-specific release, or failure behavior.

Three alternatives were considered:

| Approach | Decision | Reason |
| --- | --- | --- |
| `stream<event>` with owned, empty, and error-payload cases | chosen | Exercises the actual stream/future lifetime and all three variant payload classes with one bounded resource owner. |
| Synchronous `func() -> event` | rejected | Cheaper, but cannot establish stream drop, pending completion, early cleanup, or the interaction between a transferred resource and an async terminal. |
| Add descriptor metadata and compile Do first | rejected | Would turn unknown canonical ABI and cleanup behavior into compiler surface area before there is runtime evidence. |

The WIT definition order supplies a stable logical case order, but this design
does not assume the Core discriminant encoding, payload offset, result area, or
alignment. Those are probe outputs, not inputs.

## Ownership And Terminal Rules

On a `ticket` event, the guest validates the decoded handle, moves it to a
frame-owned slot, clears its raw transfer location, and treats the frame slot as
the sole owner. The common cleanup helper clears that slot before invoking
`[resource-drop]ticket`; no branch may retain a second live owner.

On `idle` or `failed(error-code)`, the guest must not load, store, or drop a
ticket payload. `failed(io)` closes the stream and completion endpoints and
returns `Err(io)` from `probe.run`. A completion `Err(io)` after `ticket` is
handled separately: the ticket is released before that error is returned.

Early cleanup is intentionally placed after a valid `ticket` has become
frame-owned and before the completion future is polled. It must release the
ticket, stream, and future exactly once. This is the relevant cancellation-like
ownership boundary; it neither rolls back host side effects nor introduces
general cancellation semantics.

## Canonical ABI Questions

The hand-written WAT and Rust runner must jointly measure and pin all of these
facts before any lowering discussion:

1. stream-read result representation and the location of the event value;
2. discriminant encoding for `ticket`, `idle`, and `failed`;
3. payload storage location, width, and alignment for `own<ticket>` and
   `error-code`;
4. whether a ticket handle has moved to the guest before its cleanup helper;
5. exact stream/future drop imports and their required order; and
6. behavior of an invalid discriminant before a raw payload is made owned.

The WAT exposes a stable marker for each measured field. The shell gate extracts
the marker values and requires the Rust runner's observations to agree. No
offset, tag, allocation, or release behavior from the list-owned-resource or
`Result<own<Resource>, E>` probes may be copied into this probe without direct
measurement.

## Verified Canonical ABI

`test_variant_resource_stream_abi.sh` parses the hand-written Core WAT,
embeds and validates the private Component, then runs it through Wasmtime
`47.0.2`. The green gate fixes these `cm32` facts:

| Item | Measured value | Evidence |
| --- | --- | --- |
| event result buffer | frame `+64` | `event-result-pointer` marker and all runtime modes |
| variant tag | buffer `+0` | `ticket`, `idle`, and `failed(io)` each decode through the Rust host type |
| variant payload | buffer `+4` | `ticket` handle and `failed(io)` error code decode independently |
| event size and alignment | `8` bytes, alignment `4` | `event-size` / `event-alignment` markers and Component validation |
| tag mapping | `0=ticket`, `1=idle`, `2=failed` | all three tag branches pass the runtime matrix |
| ticket transfer | raw payload is cleared after copy to frame `+16` | ticket path drops exactly once; duplicate release traps |
| allocation | no `cabi_realloc` request | this scalar variant shape has no list or string payload; exported allocator traps |

The normal matrix proves `ticket` (one create/drop), `idle` and `failed(io)`
(zero create/drop), a pending-once completion (two polls), and a completion
`Err(io)` after ticket transfer. Early cleanup releases a transferred ticket,
stream, and future with zero completion polls. A raw tag `3` traps before
ticket ownership, leaving the host table nonempty and ticket drops at zero. A
second frame release traps after one ticket drop and an empty table.

## Acceptance Matrix

| Case | Required evidence |
| --- | --- |
| WIT embed and Component validation | private world parses, embeds, creates, and validates with `cm-async` and `cm-more-async-builtins` |
| `ticket(111)` plus ready completion | one ticket create and one drop; stream/future each drop once; result `Ok`; table empty |
| `idle` plus ready completion | zero ticket create/drop; stream/future each drop once; result `Ok`; table empty |
| `failed(io)` plus ready completion | zero ticket create/drop; stream/future each drop once; result `Err(io)`; table empty |
| `ticket(111)` plus pending-once completion | two completion polls; one ticket and both endpoints drop once; table empty |
| `ticket(111)` plus completion `Err(io)` | one ticket and both endpoints drop once; completion error is preserved; table empty |
| early cleanup after ticket transfer | completion unpolled; ticket, stream, and future each drop once; table empty |
| malformed tag below WIT boundary | trap before payload ownership; zero ticket drops; table remains nonempty when the host created a ticket |
| duplicate frame release | first release drops the ticket once; second release traps; table empty |

`idle` and `failed` must have no hidden resource-drop call. The malformed and
duplicate cases are Core-only mutations, not values accepted from WIT or
exposed in any public API.

## Probe Structure And Verification

The implementation adds only private probe assets:

- `examples/p3-runtime/wit/variant-resource-stream-canonical.wit`;
- `examples/p3-runtime/variant-resource-stream-canonical.wat`;
- `examples/p3-runtime/rust-host-runner/src/bin/variant_resource_stream_abi.rs`;
- `examples/p3-runtime/test_variant_resource_stream_abi.sh`.

The shell gate must run `wasm-tools parse`, Component embed/new/validate, and
the dedicated Wasmtime runner. The runner must create tickets through
`ResourceTable`, count ticket/stream/future creation and destruction, count
completion polls, report decoded branch observations, and assert final table
emptiness where required. It uses the low-level `Linker` API if the pinned
`wasmtime::component::bindgen!` still cannot generate the private `do:...`
package name; the WIT package is not renamed for a host macro limitation.

The canonical and negative gates pass, but this does not authorize a
descriptor-specific lowering. Generic variant lowering, nested variants,
multiple owned fields, multiple stream reads, borrowed payloads, and public
language features remain out of scope.

## Stop Conditions

Stop with compiler behavior unchanged if any required tag or payload layout is
ambiguous, ownership transfer cannot be made exact-once, either non-owning case
can cause a ticket drop, an invalid tag reaches payload decoding, or the pinned
toolchain rejects the WIT shape. Record measured evidence and retain explicit
rejection rather than adding a compatibility path.
