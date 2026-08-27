# G5c Bounded Mixed Text + Two `list<u32>` Record Lower Design

## Status

Approved bounded continuation of the synchronous G5c host/WIT route. This
document admits one exact manifest-backed descriptor only; it does not
generalize record/list inference or close the full GC migration.

## Goal and exact boundary

Admit this synchronous lower boundary through the ordinary GC/WIT route:

```wit
package demo:marshal-record-mixed-text-two-u32-lists-lower@1.0.0;

interface api {
  record writing {
    code: u32,
    label: string,
    first: list<u32>,
    second: list<u32>,
  }

  write: func(value: writing);
}
```

The Do declaration is:

```do
Writing {
    code u32
    label text
    first [u32]
    second [u32]
}

write = @host_func(
    "demo:marshal-record-mixed-text-two-u32-lists-lower/api@1.0.0",
    "write",
    (Writing) -> nil
)
```

The descriptor id is:

```text
demo:marshal-record-mixed-text-two-u32-lists-lower/api.write@1.0.0/lower
```

The manifest source is
`examples/gc-p3-runtime/marshal-record-mixed-text-two-u32-lists-lower-manifest-source.wit`.
The world source is
`doc/wit/gc_marshal_record_mixed_text_two_u32_lists_lower_imports.wit`.
The source hash is the SHA-256 of source bytes, one newline, world bytes, and
one trailing newline:

```text
sha256:e37e68ef2b8509c78a80ab74b05a0512e4fe19bfaef5fc3cb26faad430000882
```

The probe was accepted by `./bin/do wit check` and by pinned
`wasm-tools 1.255.0 component embed --dummy --world probe`. The route remains
synchronous and private; it adds no public language syntax and no ownership
model.

## Fixed layout and canonical ABI

The measured root is 28 bytes with 4-byte alignment:

| Field | Offset | Size | Alignment |
| --- | ---: | ---: | ---: |
| `code` | 0 | 4 | 4 |
| `label.ptr` / `label.len` | 4 / 8 | 8 | 4 |
| `first.ptr` / `first.len` | 12 / 16 | 8 | 4 |
| `second.ptr` / `second.len` | 20 / 24 | 8 | 4 |
| record total | 0 | 28 | 4 |

The text child uses pointer/length offsets `0/4`, byte size `8`, alignment
`4`, and `cabi_realloc` allocation/free. Both list children use container
pointer/length offsets `0/4`, byte size/alignment `8/4`, element byte
size/alignment/stride `4/4/4`, and `cabi_realloc` allocation/free.

The fixed accepted bounds are:

| Field | Capacity | Accepted lengths |
| --- | ---: | --- |
| `first` | 3 | `0, 1, 2, 3` |
| `second` | 2 | `0, 1, 2` |

The canonical Core import has seven scalar words:

```wat
(func (param i32 i32 i32 i32 i32 i32 i32))
```

Arguments are emitted in field order:
`code`, `label.ptr`, `label.len`, `first.ptr`, `first.len`, `second.ptr`,
`second.len`. No GC reference, array reference, or ownership token crosses the
canonical boundary.

## Admission and fail-closed guards

The route is admitted only when all of these facts match the manifest:

1. Exactly one matching synchronous `@host_func` declaration exists.
2. The locator, member, descriptor id, package, world, interface, direction,
   parameter and result signature match exactly.
3. The Do record is named `Writing` and has exactly the ordered fields
   `code u32`, `label text`, `first [u32]`, `second [u32]`.
4. The resolved source/world hash and measured root/child layout match this
   document, including both capacities and accepted lengths.
5. Every source span and multiplication is validated before its first load or
   copy; a failed guard emits no host call and leaves no WAT artifact.

Async declarations, locator/member drift, field reorder, `[u8]` fields, extra or
missing fields, arbitrary list element types, dynamic capacities, and unknown
descriptors remain rejected or on the existing fallback route according to the
existing admission boundary. They are not promoted by structural similarity.

## Lowering and cleanup

```mermaid
flowchart LR
    A[GC Writing record] --> B[Read code, label, first, second]
    B --> C[Validate spans, lengths, capacity, and arithmetic]
    C --> D[Allocate and copy label]
    D --> E[Allocate and copy first]
    E --> F[Allocate and copy second]
    F --> G[Canonical seven-word host call]
    G --> H[Free second]
    H --> I[Free first]
    I --> J[Free label]
```

The GC record remains the source value. The lowerer uses `$do_text`/`$do_bytes`
for `label` and `$do_u32` for both lists. Temporary linear allocations are
released exactly once in reverse acquisition order: `second`, `first`, then
`label`. If allocation or range validation fails after an earlier allocation,
the cleanup mask releases every acquired span before trapping.

## Required evidence gates

The descriptor is complete only after all of these pass with the pinned
toolchain:

1. Plan and WAT unit tests prove the exact four-field shape, capacities,
   seven scalar parameters, span guards, two `array.get $do_u32` copies, one
   text copy, and reverse free order.
2. The manifest-backed Component host gate observes
   `code=7`, `label=hello`, `first=[10,20,5]`, `second=[3,4]`, one callback,
   three temporary allocations and three frees.
3. The fixed ARC oracle and generated GC Component use the same WIT and
   canonical import; equivalence observes equal values and `3/3` cleanup.
4. Negative fixtures reject async, locator/member drift, field reorder,
   `[u8]` substitution, extra fields, and record-name drift before WAT.
5. Default and explicit routes emit no ARC marker for this exact descriptor,
   and canonical imports remain free of `(ref`.
6. Full regression, ReleaseSmall, release smoke, residual, semantic
   equivalence, inventory, and formatting gates pass. Inventory remains
   intentionally `complete_rows=15 pending_rows=15` with exit code `1`.

## Non-goals and rollback

- No general record/list or arbitrary producer inference.
- No nested aggregates, variants, options, results, resources, async,
  cancellation, `own<T>`, `borrow<T>`, or `ref<T>` lowering.
- No manifest schema change, canonical ABI change, ARC fallback removal, or
  migration-row closure.

If any focused or full gate fails, remove only this descriptor's manifest/WIT
inputs, source fixtures, admission entry, fixed emitter variant, and dedicated
tests. Existing descriptors and unrelated dirty-worktree changes remain
untouched.
