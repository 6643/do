# G6.2 Bounded List-Owned Resource Stream Design

**Status:** Canonical ABI probe verified on the pinned toolchain. No compiler
lowering is enabled by this document.

**Goal:** Establish whether a registered `stream<list<resource-entry>>` shape
can be lowered safely when each list element owns one resource, without adding
public ownership syntax or generic list/resource support.

**Pinned environment:** Zig `0.16.0`, Rust `1.97.1`, `wasm-tools 1.254.0`, and
Wasmtime `47.0.2`. A toolchain upgrade invalidates this proposal's evidence.

## Source Shape

The probe uses one private WIT descriptor:

```wit
package do:record-resource-list-stream-canonical@0.1.0;

interface types {
  enum error-code { io }
}

interface source {
  use types.{error-code};
  resource ticket {}

  record resource-entry {
    ticket: own<ticket>,
  }

  read-via-stream: func() -> tuple<
    stream<list<resource-entry>>,
    future<result<_, error-code>>,
  >;
}

interface probe {
  use types.{error-code};
  run: async func() -> result<_, error-code>;
}

world record-resource-list-stream-canonical {
  import types;
  import source;
  export probe;
}
```

The first positive slice is deliberately bounded:

- acquire one registered stream;
- perform at most one stream read;
- accept one list item whose length is `0`, `1`, or `3`;
- await the registered completion future;
- release every transferred `ticket` exactly once and leave the resource table
  empty.

The Do source remains descriptor-specific. It does not expose `own<T>`,
`borrow<T>`, `ref<T>`, `list<resource-entry>` as a general type, or arbitrary
list expressions.

## Verified Evidence

The pinned `wasm-tools component embed` command accepts the private WIT shape.
`test_record_resource_list_stream_abi.sh` additionally parses the hand-written
Core WAT, embeds/validates a component, and executes a Wasmtime runner. The
runner proves one list item of length `0`, `1`, or `3`; a pending-once and an
error completion; a private early-cleanup Core variant; and malformed/duplicate
raw-ABI variants.

The measured result layout is `ptr@64,len@68`; each `resource-entry` is one
four-byte handle at offset zero, with alignment four. Nonempty list allocation
is restricted to `cabi_realloc(0,0,4,4|12)` and release to
`cabi_realloc(ptr,len*4,4,0)`. The raw handle word is cleared before the
frame-owned release helper calls `[resource-drop]ticket`.

The current Do registry still has no matching descriptor metadata. Its private
source fixture fails with `UnknownP3AsyncHostDescriptor`, and the compiler must
continue rejecting the shape until a separate lowering plan is approved.

The nearby `borrow<ticket>` shape remains a hard toolchain rejection: the same
pinned embed command exits `1` with `contains a \`borrow<T>\` which is not
supported`. This proposal does not attempt to work around that boundary.

## Canonical ABI Probe

Before production lowering, a hand-written Core/WIT/Rust probe must establish:

1. the list pointer and length locations in the stream item result;
2. the element stride and the `own<ticket>` handle word location;
3. the allocation and release calls for list storage;
4. whether ownership is transferred before the guest cleanup path;
5. cleanup behavior for list lengths `0`, `1`, and `3`;
6. rejection behavior for length `4`, malformed pointer/length pairs, and a
   duplicate release.

The Rust/Wasmtime runner must record the list length, element handles, stream
and completion future polls/drops, every ticket drop, and final
`ResourceTable` emptiness. The probe is not complete if it only validates WIT
embedding or generated text.

## Proposed Lowering Boundary

If the canonical probe passes, the implementation should add one registered
descriptor shape rather than a generic container path:

- manifest metadata names the list element record and its single owned resource
  field;
- the emitter reserves a bounded frame area for up to three handles;
- decoding copies only the validated handle words into frame-owned slots;
- terminal, error, cancellation, and early-drop paths share one exactly-once
  release helper;
- a second stream read, list length above `3`, an unsupported nested container,
  a borrowed element, or an unregistered descriptor traps with the existing
  unsupported-lowering diagnostic.

The probe fixed the offsets, allocator calls, and release order above. No
constant is raised merely to make an existing generic path accept the shape.

## Acceptance Matrix

| Case | Required evidence |
| --- | --- |
| WIT embed | passed for the private world |
| list length `0` | ready completion; zero ticket drops; empty table |
| list length `1` | one handle is consumed and dropped exactly once; empty table |
| list length `3` | three handles are consumed and dropped exactly once; empty table |
| pending completion | two polls, then stream/future and all three tickets release once |
| completion `Err(io)` | one poll; stream/future and all three tickets release once; result is preserved |
| early cleanup | completion unpolled; live stream, future, and all three tickets release once |
| length `4` / malformed ABI | explicit trap before handle ownership; zero ticket drops; table remains nonempty |
| duplicate release | second release traps after exactly three drops and an empty table |
| borrowed/list/variant/unregistered shape | `borrow` remains tool-rejected; private Do descriptor is rejected; generic list/variant lowering remains absent |

## Alternatives and Decision

`variant<own<ticket>>` is deferred: it requires a separate discriminant and
payload layout plus branch-specific cleanup, with no current descriptor metadata.
Increasing nested depth or forwarding-hop limits is rejected as a low-value
constant change without a general layout contract. Public `borrow<T>` remains
blocked by the pinned Component toolchain.

The recommended next action is therefore the canonical list ABI probe only.
Production lowering requires a separate approved implementation plan after the
probe and its negative cases are reviewed.

## Stop Conditions

Stop without changing compiler lowering if the toolchain changes the list
layout, ownership is not transferred in a deterministic way, any admitted path
leaks a ticket, or any unsupported shape can bypass the explicit boundary.
