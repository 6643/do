# G5c Bounded Mixed `text` + `list<u32>` Lift Design

## Goal

Promote one independently verifiable synchronous GC/WIT lift route for the
fixed record:

```wit
record reading {
  code: u32,
  label: string,
  payload: list<u32>,
}
```

The corresponding Do host boundary is:

```do
Reading {
    code u32
    label text
    payload [u32]
}

read = @host_func(
    "demo:marshal-record-mixed-text-u32-list-lift/api@1.0.0",
    "read",
    () -> Reading,
)
```

This is one hash-pinned descriptor. It does not generalize record inference,
list element types, multiple list fields, nested aggregate lift, producer
expressions, async/resource lowering, or ownership syntax.

## Descriptor and ABI

The descriptor is:

```text
demo:marshal-record-mixed-text-u32-list-lift/api.read@1.0.0/lift
```

The canonical lift import receives one result-area pointer and returns no Core
value:

```text
(func (param i32))
```

The measured result area is a 20-byte, alignment-4 record:

| Field | Offset | Size | Alignment |
| --- | ---: | ---: | ---: |
| `code` | 0 | 4 | 4 |
| `label.ptr` | 4 | 4 | 4 |
| `label.len` | 8 | 4 | 4 |
| `payload.ptr` | 12 | 4 | 4 |
| `payload.len` | 16 | 4 | 4 |
| record total | 0 | 20 | 4 |

The `label` child is a `text` span with `cabi_realloc` allocation/free. The
`payload` child is a `list<u32>` span with element size/alignment/stride `4`,
`cabi_realloc` allocation/free, capacity `3`, and accepted lengths `0..3`.
The scalar `code` and list elements use Core `i32`.

The manifest source hash is computed from the exact record source, a newline,
the exact world source, and a final newline. The checked-in manifest is the
source of truth; no caller-supplied layout is accepted by the compiler route.

## Lowering and lifetime

The canonical host call writes the result area and its two temporary linear
spans. The GC lift must:

1. validate the 20-byte result-area span;
2. load `code`, the label pointer/length, and the payload pointer/length;
3. validate both linear spans and the checked `length * 4` payload byte count;
4. allocate a GC `$do_bytes` array and copy the label bytes with `load8_u`;
5. allocate a GC `$do_u32` array and copy payload elements with `i32.load`;
6. free the payload span exactly once;
7. free the label span exactly once;
8. construct and publish one `$do_record` containing `code`, `$do_text`, and
   `$do_u32` values.

The empty label and empty payload are valid. Overflow, malformed lengths, and
out-of-bounds spans trap before copying. No GC reference crosses the canonical
import boundary.

The generated probe uses `code=7`, `label="hello"`, and
`payload=[10,20,5]`; the exported `run` result is `47` (`7 + 5 + 10 + 20 +
5`), the cleanup statistic is `34` (`2 * 16 + 2`), and the host callback count
is `1`.

## Admission and negative boundary

Admission requires all of the following:

- one synchronous `@host_func` with no parameters and result `Reading`;
- exact locator `demo:marshal-record-mixed-text-u32-list-lift/api@1.0.0`;
- exact member `read`;
- exact `Reading` record name, field order, and field types;
- manifest source/world hash and measured layout above;
- canonical import with one `i32` result-area parameter and no GC reference.

The route rejects before WAT for an async marker, locator mismatch, member
mismatch, reordered fields, `[u8]` payload, `text` payload, an extra field, or
a record-name mismatch. An unrelated ordinary host declaration remains on the
existing ARC fallback path.

## Non-goals and invariants

- Do not add or change public syntax.
- Do not add `own<T>`, `borrow<T>`, `ref<T>`, `Option`, `Result`, async,
  resource, cancellation, or generic ownership behavior.
- Do not infer arbitrary aggregate layouts or arbitrary list capacities.
- Keep GC-first v1 and ARC fallback for every unadmitted host/WIT shape.
- Use only `wasm-tools 1.255.0`.
- Keep migration inventory at `complete_rows=15 pending_rows=15`; this route
  does not close a full migration row or full G5c cutover.

## Evidence gate

The route is complete only when all of these pass:

1. typed-plan and WAT unit tests;
2. exact source-level positive and negative compiler fixtures;
3. manifest-backed Component host execution with Rust/Wasmtime;
4. ARC/GC canonical-boundary equivalence;
5. default `do build`/`wasm-tools 1.255.0` parse and no-ARC gate;
6. residual gate wiring, full regression, ReleaseSmall build and release
   smoke;
7. `git diff --check`.
