# G5c Bounded Record `list<u8>` Lower Design

Status: draft for review

## Goal

Close one additional, independently verifiable G5c host/WIT lowering slice:

```wit
package demo:marshal-record-byte-list-lower@1.0.0;

interface api {
  record writing {
    code: u32,
    payload: list<u8>,
  }

  write: func(value: writing);
}
```

The Do source mirror is:

```do
Writing {
    code u32
    payload [u8]
}

write = @host_func(
    "demo:marshal-record-byte-list-lower/api@1.0.0",
    "write",
    (Writing) -> nil
)
```

This is a fixed descriptor, not general record inference. It adds no public
`own<T>`, `borrow<T>`, or `ref<T>` syntax and does not admit async host calls.

## Descriptor and ABI

The descriptor id is:

```text
demo:marshal-record-byte-list-lower/api.write@1.0.0/lower
```

The measured record layout is fixed:

| Field | Offset | Size | Alignment |
| --- | ---: | ---: | ---: |
| `code` | 0 | 4 | 4 |
| `payload.ptr` | 4 | 4 | 4 |
| `payload.len` | 8 | 4 | 4 |
| record total | 0 | 12 | 4 |

The `list<u8>` child layout is pointer offset `0`, length offset `4`, element
size `1`, stride `1`, element alignment `1`, `cabi_realloc` allocation/free,
capacity `4`, and accepted lengths `0, 1, 2, 3, 4`. The canonical host import
is:

```text
(func (param i32 i32 i32))
```

The arguments are `code`, `payload.ptr`, and `payload.len`, in that order. No
GC reference may occur in the canonical import or in the values passed to it.

## Admission

The ordinary `do build` route admits the descriptor only when all guards pass:

1. There is exactly one matching host declaration.
2. The declaration is synchronous `@host_func`, not `@host_async_func`.
3. The locator is exactly `demo:marshal-record-byte-list-lower/api@1.0.0`.
4. The member is exactly `write`.
5. The declaration has exactly one parameter, `Writing`, and a `nil` result.
6. `Writing` has exactly two fields in order: `code u32`, `payload [u8]`.
7. The resolved WIT record and the manifest source hash match the descriptor.
8. The measured record and child list facts match the fixed layout above.

Any guard failure rejects before WAT output for the candidate descriptor. An
unadmitted host declaration continues through the existing ARC transition
route; it is not silently promoted by structural similarity.

## Lowering and lifetime

The GC value remains a record containing a scalar and a GC byte array. The
lowerer performs these operations in order:

```mermaid
flowchart LR
    A[GC Writing record] --> B[Read code and byte-array length]
    B --> C[Validate length and linear memory range]
    C --> D[cabi_realloc allocate payload]
    D --> E[Copy array bytes to linear memory]
    E --> F[Canonical host call i32 i32 i32]
    F --> G[cabi_realloc free payload]
```

The payload allocation is temporary and is freed exactly once after the host
call returns. Cancellation and async drop are outside this synchronous slice.
The length is checked for multiplication/offset overflow and the generated
WAT traps before copying if the source span or destination span is invalid.
An empty payload is valid and follows the same guarded allocation/free path;
the host must not read bytes when its length is zero.

## Evidence gates

The descriptor is complete only when all of the following are green:

1. A manifest-backed Core/WIT host gate validates with `wasm-tools 1.255.0`
   and a Rust/Wasmtime runner observes `code=7`, payload bytes `[10,20,5]`,
   one callback, and `result=42`.
2. A compiler-generated GC Component and a fixed linear-memory ARC oracle use
   the same WIT and runner; both observe `result=42`, payload equality, and
   exactly one host callback. The canonical imports are identical and carry no
   GC reference.
3. Negative gates reject async declaration, locator drift, member drift,
   field reorder, wrong field type, extra field, and measured list/layout
   drift before WAT; no output artifact is left by rejection.
4. The ordinary default-build gate includes the new fixture, emits `;;
   gc-sync`, contains no `__arc_` marker, parses with the pinned tool, and
   increases the admitted fixture count from 69 to 70.
5. Existing residual and full regression gates remain green; inventory stays
   `complete_rows=15 pending_rows=15` because this is one bounded row, not full
   G5c cutover.

## Non-goals

- No `list<T>` record generalization beyond this exact `list<u8>` field; the
  separate fixed `list<u32>` record lower has its own design and descriptor.
- No text/list mixtures beyond this exact two-field shape.
- No nested records, multiple list fields, spread/multi-value producers, or
  arbitrary record field counts.
- No lift path for this descriptor.
- No async/resource/borrowed ownership lowering or public ownership syntax.
- No change to the canonical ABI policy or to the ARC fallback for unadmitted
  shapes.

## Rollback invariant

If any positive or negative gate fails, remove only this descriptor's manifest
entry, source/WIT fixtures, route admission, and dedicated tests. Existing
The pre-u32 descriptor default behavior and all previously admitted descriptors
must remain unchanged.
