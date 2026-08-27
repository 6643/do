# G5c Bounded Mixed Scalar-List Record Lower Design

## Status

Approved bounded follow-on design. This document defines one additional
manifest-backed synchronous GC/WIT lower slice. It is intentionally narrower
than a general aggregate lowerer.

## Goal

Admit exactly this private host boundary through the ordinary GC/WIT route:

```wit
package demo:marshal-record-mixed-scalar-list-lower@1.0.0;

interface api {
  record writing {
    code: u32,
    label: string,
    payload: list<u8>,
  }

  write: func(value: writing);
}
```

The Do source mirror is:

```do
Writing {
    code u32
    label text
    payload [u8]
}

write = @host_func(
    "demo:marshal-record-mixed-scalar-list-lower/api@1.0.0",
    "write",
    (Writing) -> nil
)
```

The descriptor id is:

```text
demo:marshal-record-mixed-scalar-list-lower/api.write@1.0.0/lower
```

The route is synchronous, private, exact-descriptor based, and manifest
measured. It does not add syntax or change the public ownership model.

## Fixed ABI and measurements

The WIT record uses the following measured root layout:

| Field | Offset | Size | Alignment |
| --- | ---: | ---: | ---: |
| `code` | 0 | 4 | 4 |
| `label.ptr` / `label.len` | 4 / 8 | 8 | 4 |
| `payload.ptr` / `payload.len` | 12 / 16 | 8 | 4 |
| record total | 0 | 20 | 4 |

The text child has pointer offset `0`, length offset `4`, byte size `8`,
alignment `4`, and `cabi_realloc` allocation/free actions.

The byte-list child has pointer offset `0`, length offset `4`, element byte
size `1`, element stride `1`, element alignment `1`, `cabi_realloc`
allocation/free actions, capacity `4`, and accepted lengths `0, 1, 2, 3, 4`.

The canonical Core import is:

```text
(func (param i32 i32 i32 i32 i32))
```

Arguments are emitted in WIT field order:

```text
code, label.ptr, label.len, payload.ptr, payload.len
```

The canonical boundary carries only scalar Core words. No GC reference, array
reference, or linear-memory ownership token crosses the import.

## Admission guards

The ordinary route admits the descriptor only when every guard succeeds:

1. Exactly one matching host declaration exists.
2. The declaration is synchronous `@host_func`, never `@host_async_func`.
3. The locator is exactly
   `demo:marshal-record-mixed-scalar-list-lower/api@1.0.0`.
4. The member is exactly `write`.
5. The declaration has exactly one `Writing` parameter and a `nil` result.
6. `Writing` has exactly three fields in this order and with these Do types:
   `code u32`, `label text`, `payload [u8]`.
7. The resolved WIT source and manifest source hash match the descriptor.
8. The measured root and both child measurements match this document,
   including the byte-list capacity and accepted lengths.

A failed guard rejects before WAT output for the selected descriptor. An
unrelated or unadmitted declaration keeps its existing route; structural
similarity never promotes a descriptor implicitly.

## Lowering and lifetime

The GC value remains a record containing one scalar, one GC text value, and one
GC byte array. The lowerer uses the shared scalar-list facts for the byte array
and a second managed-text operation for the text field. The ordered sequence is:

```mermaid
flowchart LR
    A[GC Writing record] --> B[Read code, label, payload spans]
    B --> C[Validate source and length arithmetic]
    C --> D[Allocate label linear span]
    D --> E[Copy label bytes]
    E --> F[Allocate payload linear span]
    F --> G[Copy payload bytes]
    G --> H[Canonical host call with five i32 values]
    H --> I[Free payload span exactly once]
    I --> J[Free label span exactly once]
```

Each temporary allocation is freed exactly once after the canonical call
returns. The generated code validates source spans, multiplication, and
linear destination ranges before copying. Empty text and empty payload are
valid; their host lengths are zero and the host must not read bytes for a zero
length span. Cancellation, async drop, resources, borrowed values, and
ownership transfer are outside this synchronous slice.

The two allocations are independent. A failure before the host call does not
invoke the host. A failure after either allocation has occurred must release
every allocation already acquired before trapping or returning through the
existing synchronous error path; the route must not leak a partially built
temporary span.

## Evidence gates

The descriptor is complete only after all gates below pass with the pinned
`wasm-tools 1.255.0` toolchain:

1. Manifest-backed Core/WIT host execution observes the fixed code, label, and
   payload values, one callback, two allocations, and two frees.
2. A compiler-generated GC Component and a checked-in linear-memory oracle use
   the same WIT and canonical import. The Rust/Wasmtime runner observes equal
   host results and equal field values from both paths.
3. Negative fixtures reject async declaration, locator drift, member drift,
   reordered fields, wrong text/list types, an extra field, and measured
   layout/capacity drift before WAT; no output artifact remains after failure.
4. The default-build gate includes the positive fixture, emits the GC route
   marker, contains no ARC runtime marker for this descriptor, parses with the
   pinned tool, and increments the admitted-fixture count by one.
5. Existing C16, byte-list, u32-list, residual, full regression, ReleaseSmall,
   release-smoke, and formatting gates remain green. The migration inventory
   remains deliberately `complete_rows=15 pending_rows=15`; this bounded slice
   is not a claim of complete G5c cutover.

## Non-goals and rejection boundary

- No general `list<T>` record inference.
- No general text/list mixture, multiple list fields, multiple text fields,
  nested records, variants, options, results, resources, or producer
  expressions.
- No lift path for this descriptor.
- No async host function, `Future`, `Stream`, cancellation, ownership, or
  borrowed-reference lowering.
- No change to the manifest JSON schema or canonical ABI policy.
- No change to the existing ARC fallback for descriptors that are not admitted.

## Rollback invariant

If any positive, negative, Component, host, equivalence, or cleanup gate fails,
remove only this descriptor's manifest entry, source/WIT fixtures, route
admission, emitter branch, and dedicated tests. Existing descriptors and their
identity, measurements, and fallback behavior must remain unchanged.
