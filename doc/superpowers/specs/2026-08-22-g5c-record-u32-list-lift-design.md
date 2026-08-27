# G5c Bounded Record `list<u32>` Lift Design

## Goal

Close one independently verifiable synchronous G5c lift slice for the fixed
record:

```wit
record reading {
  code: u32,
  payload: list<u32>,
}
```

The corresponding Do boundary is `Reading { code u32, payload [u32] }` and a
synchronous `@host_func` returning `Reading`.

This is a single hash-pinned descriptor. It does not generalize list elements,
record fields, producer expressions, async/resource lowering, or ownership
syntax.

## Descriptor and ABI

The descriptor is:

```text
demo:marshal-record-u32-list-lift/api.read@1.0.0/lift
```

The canonical import returns one result-area pointer:

```text
(func (param i32))
```

The result area is a 12-byte record:

| Field | Offset | Size | Alignment |
| --- | ---: | ---: | ---: |
| `code` | 0 | 4 | 4 |
| `payload.ptr` | 4 | 4 | 4 |
| `payload.len` | 8 | 4 | 4 |
| record total | 0 | 12 | 4 |

The `list<u32>` child has element size/stride/alignment `4`,
`cabi_realloc` allocation/free, capacity `3`, and accepted lengths `0..3`.
The `code` scalar is loaded as Core `i32`.

## Lowering and lifetime

The canonical call writes the record result area. The GC lift then:

1. validates the 12-byte result area;
2. loads `code`, list pointer, and list length;
3. validates `4 * length` and the linear-memory span;
4. allocates a GC `$do_u32` array and copies each element with `i32.load`;
5. frees the temporary linear payload exactly once;
6. constructs and publishes one `$do_record` containing `code` and the GC array.

The empty list is valid. A malformed length, overflow, or out-of-bounds span
traps before copying. No GC reference crosses the canonical import.

## Admission and non-goals

Admission requires one synchronous `@host_func`, the exact locator/member,
`Reading` fields in the exact order and types, the manifest source hash, and
the measured layout above. Async declarations, locator/member drift, field
reordering, `[u8]` drift, extra fields, and unlisted shapes reject before WAT.

This slice does not admit arbitrary `list<T>`, list-bearing nested records,
multiple list fields, text/list mixtures, async/resource calls,
`own<T>`/`borrow<T>`/`ref<T>`, or the full G5c cutover.

## Evidence gate

The slice is complete only after the manifest/component host gate, ARC/GC
equivalence gate, six negative cases, ordinary default-route fixture, full
regression, ReleaseSmall build, release smoke, and `git diff --check` pass.
The migration inventory remains `complete_rows=15 pending_rows=15`.
