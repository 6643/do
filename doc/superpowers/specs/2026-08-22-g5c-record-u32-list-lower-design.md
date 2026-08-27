# G5c Bounded Record `list<u32>` Lower Design

Status: implemented and verified (2026-08-22)

## Goal

Close one additional, independently verifiable G5c host/WIT lowering slice:

```wit
package demo:marshal-record-u32-list-lower@1.0.0;

interface api {
  record writing {
    code: u32,
    payload: list<u32>,
  }

  write: func(value: writing);
}
```

The Do source mirror is:

```do
Writing {
    code u32
    payload [u32]
}

write = @host_func(
    "demo:marshal-record-u32-list-lower/api@1.0.0",
    "write",
    (Writing) -> nil
)
```

This is a fixed descriptor, not general record inference. It adds no public
`own<T>`, `borrow<T>`, or `ref<T>` syntax and does not admit async host calls.

## Descriptor and ABI

The descriptor id is:

```text
demo:marshal-record-u32-list-lower/api.write@1.0.0/lower
```

The manifest source is hash-pinned:

```text
sha256:30a6d8c42680333d2c0b359888f589d41d30a82fc105e94ef1a43e0920fc519b
```

The measured root record layout is fixed:

| Field | Offset | Size | Alignment |
| --- | ---: | ---: | ---: |
| `code` | 0 | 4 | 4 |
| `payload.ptr` | 4 | 4 | 4 |
| `payload.len` | 8 | 4 | 4 |
| record total | 0 | 12 | 4 |

The `list<u32>` child has pointer offset `0`, length offset `4`, element size
`4`, stride `4`, element alignment `4`, `cabi_realloc` allocation/free,
capacity `3`, and accepted lengths `0, 1, 2, 3`. WIT `u32` lowers to Core
`i32` in the copied linear payload. The canonical host import is:

```text
(func (param i32 i32 i32))
```

The arguments are `code`, `payload.ptr`, and `payload.len`, in that order. No
GC reference may occur in the canonical import or in the values passed to it.

## Admission

The ordinary `do build` route admits the descriptor only when all guards pass:

1. There is exactly one matching host declaration.
2. The declaration is synchronous `@host_func`, not `@host_async_func`.
3. The locator is exactly `demo:marshal-record-u32-list-lower/api@1.0.0`.
4. The member is exactly `write`.
5. The declaration has exactly one parameter, `Writing`, and a `nil` result.
6. `Writing` has exactly two fields in order: `code u32`, `payload [u32]`.
7. The resolved WIT record and manifest source hash match the descriptor.
8. The measured record and child list facts match the fixed layout above.

Any guard failure rejects before WAT output for the candidate descriptor. An
unadmitted host declaration continues through the existing ARC transition
route; it is not silently promoted by structural similarity.

## Lowering and lifetime

The GC value remains a record containing a scalar and a GC `u32` array. The
lowerer performs these operations in order:

```mermaid
flowchart LR
    A[GC Writing record] --> B[Read code and u32-array length]
    B --> C[Validate length and linear memory range]
    C --> D[cabi_realloc allocate 4*len bytes]
    D --> E[Copy array elements as i32]
    E --> F[Canonical host call i32 i32 i32]
    F --> G[cabi_realloc free payload]
```

The payload allocation is temporary and is freed exactly once after the host
call returns. Cancellation and async drop are outside this synchronous slice.
The generated WAT guards accepted lengths and multiplication/offset overflow
before copying. An empty payload is valid and follows the same guarded
allocation/free contract; the host must not read payload bytes when its
length is zero.

## Evidence gates

The descriptor is complete only when all of the following are green:

1. The manifest-backed Core/WIT host gate validates with `wasm-tools 1.255.0`
   and a Rust/Wasmtime runner observes `code=7`, payload `[10,20,30]`, one
   callback, and one allocation/free pair.
2. A compiler-generated GC Component and a fixed linear-memory ARC oracle use
   the same WIT and runner; both observe the expected payload and host result,
   the canonical imports are identical, and no GC reference crosses them.
3. Negative gates reject async declaration, locator drift, member drift, field
   reorder, `[u8]` element drift, and an extra record field before WAT; no
   output artifact remains after rejection.
4. The ordinary default-build gate includes the new fixture, emits `;; gc-sync`,
   contains no `__arc_` marker, parses with the pinned tool, and covers 73
   admitted fixtures.
5. The full regression, ReleaseSmall build, release smoke, residual gate, and
   `git diff --check` remain green. The migration inventory remains deliberately
   `complete_rows=15 pending_rows=15` because this is one bounded row, not full
   G5c cutover.

## Non-goals

- No `list<T>` record generalization beyond this exact `list<u32>` field.
- No inference for `list<u8>`, text/list mixtures, multiple list fields, nested
  records, spread/multi-value producers, or arbitrary record field counts.
- No lift path for this descriptor.
- No async/resource/borrowed ownership lowering or public ownership syntax.
- No change to the canonical ABI policy or to the ARC fallback for unadmitted
  shapes. The separate fixed `list<u8>` record lower is documented by
  `2026-08-22-g5c-record-byte-list-lower-design.md`.

## Rollback invariant

If any positive or negative gate fails, remove only this descriptor's manifest
entry, source/WIT fixtures, route admission, and dedicated tests. The prior
73-fixture default behavior and all previously admitted descriptors must remain
unchanged.
