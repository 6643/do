# G5c Bounded Mixed Text + Byte/U32 Lists Record Lower Design

## Status

Approved as the single next synchronous G5c residual slice after the
2026-08-25 capability-matrix review. This admits one exact manifest-backed
descriptor only. It does not generalize record/list inference, close a
migration row, or claim full GC cutover.

## Goal and exact boundary

Admit this fixed lower boundary through the ordinary GC/WIT route:

```wit
package demo:marshal-record-mixed-text-byte-u32-lists-lower@1.0.0;

interface api {
  record writing {
    code: u32,
    label: string,
    bytes: list<u8>,
    values: list<u32>,
  }

  write: func(value: writing);
}
```

The Do declaration is:

```do
Writing {
    code u32
    label text
    bytes [u8]
    values [u32]
}

write = @host_func(
    "demo:marshal-record-mixed-text-byte-u32-lists-lower/api@1.0.0",
    "write",
    (Writing) -> nil
)
```

The descriptor id is:

```text
demo:marshal-record-mixed-text-byte-u32-lists-lower/api.write@1.0.0/lower
```

The manifest source is
`examples/gc-p3-runtime/marshal-record-mixed-text-byte-u32-lists-lower-manifest-source.wit`.
The world source is
`doc/wit/gc_marshal_record_mixed_text_byte_u32_lists_lower_imports.wit`.
The source hash is computed from source bytes, one newline, world bytes, and
one trailing newline:

```text
sha256:2d966dfc68f27f42ba7ce5f44c471907cf2ebe922a9af24d3cfc810847cce9c3
```

The route is synchronous and private. It adds no public language syntax and
no ownership, async, resource, Option, or Result model.

## Why this candidate is admitted

The matrix review found `host_wit_marshalling` to be the only row that can
reuse `LoadedRequest`, the descriptor registry, and `SyncValuePlan` without a
new contract. This shape is the smallest remaining fixed descriptor that
combines the already measured byte-list and u32-list element variants in one
record and exercises heterogeneous span cleanup. It keeps a fixed field order,
capacities, source hash, and canonical boundary.

The following alternatives are explicitly rejected for this slice:

- A fixed scalar-only record would add no managed span or cleanup evidence.
- An arbitrary record/list or dynamic producer would require general element
  metadata and producer-lifetime semantics.
- Async, resource, borrowed payload, `own<T>`, `borrow<T>`, `ref<T>`, Option,
  and Result shapes require contracts outside synchronous G5c.

## Fixed layout and canonical ABI

The measured root is 28 bytes with 4-byte alignment:

| Field | Offset | Size | Alignment |
| --- | ---: | ---: | ---: |
| `code` | 0 | 4 | 4 |
| `label.ptr` / `label.len` | 4 / 8 | 8 | 4 |
| `bytes.ptr` / `bytes.len` | 12 / 16 | 8 | 4 |
| `values.ptr` / `values.len` | 20 / 24 | 8 | 4 |
| record total | 0 | 28 | 4 |

The text child uses pointer/length offsets `0/4`, byte size `8`, alignment
`4`, and `cabi_realloc` allocation/free. Both list children use container
pointer/length offsets `0/4`, byte size/alignment `8/4`, and
`cabi_realloc` allocation/free. `bytes` has element byte size/alignment/stride
`1/1/1` and capacity `4`; `values` has element byte size/alignment/stride
`4/4/4` and capacity `3`. Accepted lengths are `0..4` and `0..3` respectively.

The canonical Core import has seven scalar words:

```wat
(func (param i32 i32 i32 i32 i32 i32 i32))
```

Arguments are emitted in field order:
`code`, `label.ptr`, `label.len`, `bytes.ptr`, `bytes.len`, `values.ptr`,
`values.len`. No GC reference, array reference, or ownership token crosses
the canonical boundary.

## Admission and fail-closed guards

The route is admitted only when all of these facts match the manifest:

1. Exactly one matching synchronous `@host_func` declaration exists.
2. Locator, member, descriptor id, package, world, interface, direction,
   parameter, and result signature match exactly.
3. The Do record is named `Writing` and has exactly the ordered fields
   `code u32`, `label text`, `bytes [u8]`, `values [u32]`.
4. Source/world hash and measured root/child layout match this document,
   including both capacities and accepted lengths.
5. Every source span and multiplication is validated before its first load or
   copy. A failed guard emits no host call and leaves no WAT artifact.

Async declarations, locator/member drift, field reorder, list element
substitution, extra or missing fields, dynamic capacities, arbitrary list
element types, and unknown descriptors remain rejected or on the existing ARC
fallback according to the existing admission boundary. Structural similarity
does not promote them.

## Lowering and cleanup

```mermaid
flowchart LR
    A[GC Writing record] --> B[Read code, label, bytes, values]
    B --> C[Validate spans, lengths, capacity, and arithmetic]
    C --> D[Allocate and copy label]
    D --> E[Allocate and copy bytes]
    E --> F[Allocate and copy values]
    F --> G[Canonical seven-word host call]
    G --> H[Free values]
    H --> I[Free bytes]
    I --> J[Free label]
```

The GC record remains the source value. The lowerer uses `$do_bytes` for
`label` and `bytes`, and `$do_u32` for `values`. Temporary linear allocations
are released exactly once in reverse acquisition order: `values`, `bytes`,
then `label`. If allocation or range validation fails after an earlier
allocation, the cleanup mask releases every acquired span before trapping.

## Required evidence gates

The descriptor is complete only after all of these pass with pinned Zig,
`wasm-tools 1.255.0`, and Wasmtime 47.0.2:

1. Plan and WAT unit tests prove the exact four-field shape, capacities, seven
   scalar parameters, span guards, one byte-list copy, one u32-list copy, one
   text copy, and reverse free order.
2. The manifest-backed Component host gate observes
   `code=7`, `label=hello`, `bytes=[10,20,5]`, `values=[3,4]`, one callback,
   three temporary allocations, and three frees.
3. The fixed ARC oracle and generated GC Component use the same WIT and
   canonical import; equivalence observes the same payload and `3/3`
   cleanup marker/counters.
4. Negative fixtures reject async, locator/member drift, field reorder, list
   element substitution, extra fields, and record-name drift before WAT.
5. Default and explicit routes emit no ARC marker for this exact descriptor,
   and canonical imports remain free of `(ref`.
6. Full regression, ReleaseSmall, release smoke, residual, semantic
   equivalence, inventory, and formatting gates pass. Inventory remains
   intentionally `complete_rows=15 pending_rows=15` with exit code `1`.

## Non-goals and rollback

- No general record/list or arbitrary producer inference.
- No nested aggregates, variants, options, results, resources, async,
  cancellation, `own<T>`, `borrow<T>`, or `ref<T>` lowering.
- No manifest schema or canonical ABI change, ARC fallback removal, or
  migration-row closure.

If any focused or full gate fails, remove only this descriptor's manifest/WIT
inputs, source fixtures, admission entry, fixed emitter variant, and dedicated
tests. Existing descriptors and unrelated dirty-worktree changes remain
untouched.
