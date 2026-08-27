# G5c Two-`list<u32>` Synchronous Record Lower Design

## Status

Proposed bounded slice. The capability matrix selected this shape, but no
compiler admission or migration row is changed by this document alone.

## Goal

Extend the existing manifest-backed synchronous host/WIT lower route to one
exact record containing two managed `list<u32>` fields. The slice must prove
that two independent linear spans are guarded, copied, passed across the
canonical boundary, and freed exactly once in reverse order.

## Exact source and WIT contract

Source fixture:

```wit
package demo:marshal-record-two-u32-lists-lower@1.0.0;

interface api {
  record writing {
    code: u32,
    first: list<u32>,
    second: list<u32>,
  }

  write: func(value: writing);
}
```

Do fixture:

```do
write = @host_func(
    "demo:marshal-record-two-u32-lists-lower/api@1.0.0",
    "write",
    (Writing) -> nil,
)

Writing {
    code u32
    first [u32]
    second [u32]
}

start() {
    value Writing = Writing{
        code = 7,
        first = .{10, 20, 5},
        second = .{3, 4},
    }
    write(value)
}
```

The assembly world imports `api`, exports `run: func() -> u32`, and otherwise
matches the source package. The manifest descriptor is:

```text
demo:marshal-record-two-u32-lists-lower/api.write@1.0.0/lower
```

The source hash and imports-world hash are measured from the checked-in files
and stored in the descriptor manifest; callers cannot provide independent
identity or layout facts.

## Measured layout and canonical ABI

The manifest fixes these facts:

| Field | Offset | Size | Alignment | Child shape |
| --- | ---: | ---: | ---: | --- |
| `code` | 0 | 4 | 4 | scalar `u32` / canonical `i32` |
| `first` | 4 | 8 | 4 | `list<u32>`, pointer `0`, length `4`, capacity `3`, stride `4` |
| `second` | 12 | 8 | 4 | `list<u32>`, pointer `0`, length `4`, capacity `2`, stride `4` |

The root record is `20` bytes with alignment `4`. Accepted list lengths are
`first: 0..3` and `second: 0..2`; every other length traps or rejects before
the first corresponding linear load/copy.

The canonical import is:

```wat
(type $canonical_lower (func (param i32 i32 i32 i32 i32)))
```

The five words are `code`, `first.ptr`, `first.len`, `second.ptr`, and
`second.len`. No canonical import or Component boundary may contain `(ref`.

## Lowering and cleanup contract

The operation plan must expose two independent scalar-list fields and the WAT
emitter must produce this order:

```text
read_gc_span(code/first/second)
flatten_gc_fields
validate first length and compute first byte count
cabi_realloc first
validate first linear span
copy first GC array -> linear memory
validate second length and compute second byte count
cabi_realloc second
validate second linear span
copy second GC array -> linear memory
canonical_call
cabi_realloc free(second)
cabi_realloc free(first)
```

Both allocations are freed exactly once even when one list is empty. The
canonical call is never reached after a failed guard. A failure in the second
allocation/copy path must not free an unallocated second span, and must retain
the existing first-span cleanup contract.

## Admission boundary

Admit only the exact descriptor above, one synchronous `@host_func`, the exact
record name and field order, and the exact `[u32]` element types. Reuse the
existing `LoadedRequest`, descriptor registry, source/WIT hash validation,
host-boundary validation, `SyncValuePlan`, and default route lease.

Reject before WAT for:

- `@host_async_func` or any async marker;
- locator or member drift;
- field reorder, renamed record, missing or extra field;
- either list changing to `[u8]` or `text`;
- a third managed field;
- an unregistered descriptor or source/WIT hash drift;
- resource, borrow, ownership, Future, Stream, Option, Result, Variant, or
  nested aggregate shapes.

Unknown host/WIT descriptors keep the existing ARC fallback. This slice does
not change public syntax and does not close `host_wit_marshalling` or any
inventory row.

## Host and equivalence oracle

The Rust host checks `code=7`, `first=[10,20,5]`, `second=[3,4]`, exactly one
callback, exactly two allocations and two frees, and an empty resource table.
The fixed ARC core oracle uses the same canonical five-word import and the
same observations. The GC and ARC components must report identical values,
callback count, and allocation/free counts.

## Verification and rollback

The slice requires focused operation/Wat tests, manifest/host-boundary unit
tests, positive Component host execution, seven or more fail-closed negative
fixtures, GC/ARC equivalence, default GC build inclusion, residual gate
coverage, ReleaseSmall smoke, full regression, and `git diff --check`.

If any guard ordering, canonical ABI, Component validation, host observation,
or equivalence check fails, revert only this descriptor, its route metadata,
fixtures, runners, gates, and docs. Do not weaken existing negative tests,
change the ARC fallback, or alter `complete_rows=15 pending_rows=15`.

## Non-goals

This design does not generalize arbitrary record/list lowering, add new list
element kinds, admit async/resource paths, introduce ownership syntax, or
switch the compiler to a global GC-only backend.
