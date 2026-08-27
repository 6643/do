# G5c Bounded Mixed Text + `list<u32>` Record Lower Design

## Status

Approved bounded continuation of the synchronous G5c host/WIT route. This
document defines one exact manifest-backed descriptor; it does not generalize
record or list inference and does not close the full GC migration.

## Goal

Admit exactly this private synchronous lower boundary through the ordinary
GC/WIT route:

```wit
package demo:marshal-record-mixed-text-u32-list-lower@1.0.0;

interface api {
  record writing {
    code: u32,
    label: string,
    payload: list<u32>,
  }

  write: func(value: writing);
}
```

The Do source mirror is:

```do
Writing {
    code u32
    label text
    payload [u32]
}

write = @host_func(
    "demo:marshal-record-mixed-text-u32-list-lower/api@1.0.0",
    "write",
    (Writing) -> nil
)
```

The descriptor id is:

```text
demo:marshal-record-mixed-text-u32-list-lower/api.write@1.0.0/lower
```

The route is synchronous, private, exact-descriptor based, and measured from
the pinned WIT source. It adds no public syntax and does not change the
ownership model.

## Fixed layout and canonical ABI

The root record is measured as 20 bytes with 4-byte alignment:

| Field | Offset | Size | Alignment |
| --- | ---: | ---: | ---: |
| `code` | 0 | 4 | 4 |
| `label.ptr` / `label.len` | 4 / 8 | 8 | 4 |
| `payload.ptr` / `payload.len` | 12 / 16 | 8 | 4 |
| record total | 0 | 20 | 4 |

The text child uses pointer offset `0`, length offset `4`, byte size `8`,
4-byte alignment, and `cabi_realloc` allocation/free. The `list<u32>` child
uses container pointer/length offsets `0/4`, container size/alignment `8/4`,
element byte size/alignment/stride `4/4/4`, `cabi_realloc` allocation/free,
capacity `3`, and accepted lengths `0, 1, 2, 3`.

The canonical Core import has only scalar words:

```text
(func (param i32 i32 i32 i32 i32))
```

Arguments are emitted in WIT field order:
`code`, `label.ptr`, `label.len`, `payload.ptr`, `payload.len`. No GC
reference, array reference, or ownership token crosses the import.

## Admission guards

The ordinary route admits the descriptor only when every guard succeeds:

1. Exactly one matching host declaration exists.
2. The declaration is synchronous `@host_func`, never `@host_async_func`.
3. The locator is exactly
   `demo:marshal-record-mixed-text-u32-list-lower/api@1.0.0`.
4. The member is exactly `write`.
5. The declaration has one `Writing` parameter and a `nil` result.
6. `Writing` has exactly these fields, in order: `code u32`, `label text`,
   `payload [u32]`.
7. The resolved WIT package, world, interface, member, direction, concatenated
   source/world hash, canonical signature, and measured layout match the
   manifest descriptor.
8. The measured root and both managed children match this document, including
   the `list<u32>` capacity and accepted lengths.

A failed guard rejects before WAT output for the selected descriptor. An
unrelated or unadmitted declaration keeps its existing route; structural
similarity never promotes it implicitly.

## Lowering and lifetime

The GC record remains the source value. The synchronous lowerer performs these
operations in order:

```mermaid
flowchart LR
    A[GC Writing record] --> B[Read code, label, payload spans]
    B --> C[Validate source spans and arithmetic]
    C --> D[Allocate label bytes]
    D --> E[Copy label bytes]
    E --> F[Allocate 4*payload.len bytes]
    F --> G[Copy u32 elements with stride 4]
    G --> H[Canonical five-word host call]
    H --> I[Free payload exactly once]
    I --> J[Free label exactly once]
```

The text uses the existing `$do_text`/`$do_bytes` representation. The list
uses `$do_u32`, `array.get $do_u32`, and `i32.store`; the element kind, stride,
size, alignment, and capacity come from the existing measured
`ManagedScalarListField` rather than emitter-local constants. Empty text and
empty payload are valid. A source-length, multiplication, or destination-range
failure before the host call must not call the host. If one allocation has
already succeeded, the existing synchronous cleanup path releases it before
trapping; no acquired allocation may leak.

## Evidence gates

The descriptor is complete only after all of these pass with
`wasm-tools 1.255.0`:

1. Typed-plan and WAT unit tests prove the exact shape, `u32` load/store,
   stride, capacity, five scalar arguments, and reverse free order.
2. A manifest-backed Core/WIT host gate and Rust/Wasmtime runner observe
   `code=7`, `label=hello`, `payload=[10,20,5]`, one callback, two temporary
   allocations, and two frees.
3. A compiler-generated GC Component and a fixed linear-memory ARC oracle use
   the same WIT and canonical import; the equivalence runner observes equal
   field values and result/cleanup counters.
4. Negative source and descriptor fixtures reject async declaration, locator or
   member drift, field reorder, `[u8]` payload, `text` payload, extra fields,
   and measured layout/capacity drift before writing WAT.
5. The default GC route includes exactly this positive fixture, emits no ARC
   marker for it, parses with the pinned tool, and increments the admitted
   fixture count by one. Existing routes remain unchanged.
6. Full regression, ReleaseSmall, release smoke, residual, semantic
   equivalence, migration inventory, and formatting gates remain green. The
   migration inventory remains `complete_rows=15 pending_rows=15`.

## Non-goals and rejection boundary

- No general record or `list<T>` inference.
- No multiple text/list fields, nested aggregates, variants, options, results,
  resources, producer expressions, or lift path.
- No async host function, `Future`, `Stream`, cancellation, ownership, or
  borrowed-reference lowering.
- No manifest schema change and no canonical ABI change.
- No removal or semantic change of the ARC fallback for unadmitted shapes.

## Rollback invariant

If any focused or full gate fails, remove only this descriptor's manifest/WIT
inputs, source fixtures, admission branch, emitter change, and dedicated tests.
All previously admitted descriptors, the 79-fixture baseline, and unrelated
dirty-worktree changes must remain intact.
