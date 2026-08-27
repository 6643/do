# G5c Bounded Mixed `text` + `list<u8>` Lift Design

## Status

Implemented and verified on 2026-08-25. This design promotes one hash-pinned
descriptor only; it does not generalize aggregate inference, list inference, or
the full GC migration. The ARC path remains an equivalence oracle, not the
selected runtime target.

## Goal

Admit exactly this synchronous lift boundary through the ordinary manifest-backed
GC/WIT route:

```wit
package demo:marshal-record-mixed-text-byte-list-lift@1.0.0;

interface api {
  record reading {
    code: u32,
    label: string,
    payload: list<u8>,
  }

  read: func() -> reading;
}
```

The Do source mirror is:

```do
Reading {
    code u32
    label text
    payload [u8]
}

read = @host_func(
    "demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0",
    "read",
    () -> Reading
)
```

The descriptor id is:

```text
demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift
```

This is one exact, synchronous, no-parameter result shape. It adds no public
syntax and leaves every unadmitted host/WIT declaration on the existing
ARC fallback or fail-closed path.

## Fixed layout and canonical ABI

The result-area root is measured as 20 bytes with 4-byte alignment:

| Field | Offset | Size | Alignment |
| --- | ---: | ---: | ---: |
| `code` | 0 | 4 | 4 |
| `label.ptr` / `label.len` | 4 / 8 | 8 | 4 |
| `payload.ptr` / `payload.len` | 12 / 16 | 8 | 4 |
| record total | 0 | 20 | 4 |

The `label` child is a text span with pointer/length offsets `0/4`, byte size
`8`, alignment `4`, and `cabi_realloc` allocation/free. The `payload` child is
a byte-list span with pointer/length offsets `0/4`, byte size `8`, alignment
`4`, element byte size/alignment/stride `1/1/1`, capacity `4`, and accepted
lengths `0, 1, 2, 3, 4`; its allocation and free authority is `cabi_realloc`.
The scalar `code` uses Core `i32`; byte elements use `i32.load8_u` and the
managed GC array type `$do_bytes`.

The canonical lift import has one result-area pointer and no Core result:

```text
(func (param i32))
```

No GC reference, array reference, or ownership token crosses this boundary.
The manifest source hash is computed from the exact record source, a newline,
the exact world source, and a final newline. The checked-in manifest is the
only accepted source of the measured layout.

## Lowering and lifetime

The host callback writes the result-area root and its two temporary linear
spans. The generated lift performs this sequence:

1. validate the 20-byte result-area span;
2. load `code`, label pointer/length, and payload pointer/length;
3. validate both linear spans and the byte-list bounds without multiplication
   overflow;
4. allocate `$do_bytes` and copy the label with `i32.load8_u`;
5. allocate `$do_bytes` and copy the payload with `i32.load8_u`;
6. free the payload span exactly once;
7. free the label span exactly once;
8. construct and publish one `$do_record` containing `code`, `$do_text`, and
   the payload `$do_bytes` value.

Empty label and empty payload are valid. A malformed pointer/length pair,
length above `4`, integer overflow, or an out-of-bounds span traps before the
corresponding copy. If a later validation or allocation traps after one span
has been acquired, the existing synchronous cleanup path must release every
acquired span exactly once; no successful host call may leave an owned linear
span unfreed.

The fixed host oracle uses `code=7`, `label="hello"`, and
`payload=[10,20,5]`. The generated probe returns `47` (`7 + 5 + 10 + 20 + 5`),
reports cleanup statistic `34` (`2 * 16 + 2`), and observes one host callback,
two allocations, and two frees. These values are gate fixtures, not a new
language-level constant.

## Admission and negative boundary

Admission succeeds only if all guards match:

1. exactly one synchronous `@host_func` has no parameters and result `Reading`;
2. locator is exactly `demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0`;
3. member is exactly `read`;
4. `Reading` has exactly ordered fields `code u32`, `label text`,
   `payload [u8]`;
5. manifest package/world/member/direction, source hash, canonical signature,
   root layout, child layout, capacity, and accepted lengths match;
6. the emitted canonical import is exactly one scalar `i32` parameter.

The compiler rejects before writing WAT for an async marker, locator drift,
member drift, field reorder, `[u32]` payload, `text` payload, an extra field,
or a record-name mismatch. An unrelated ordinary host declaration is still
allowed to use its existing ARC fallback.

## Non-goals and invariants

- Do not add or change public syntax.
- Do not add `own<T>`, `borrow<T>`, `ref<T>`, `Option`, `Result`, async,
  resource, cancellation, or generic ownership behavior.
- Do not infer arbitrary record layouts, list element types, or capacities.
- Do not widen the existing `list<u32>` descriptor; this is a separate hash-
  pinned descriptor and separate negative boundary.
- Keep GC-first v1 and ARC fallback for every unadmitted host/WIT shape.
- Use only `wasm-tools 1.255.0`.
- Keep migration inventory at `complete_rows=15 pending_rows=15`; this bounded
  route does not close a full migration row or full G5c cutover.

## Evidence gate

The descriptor is complete only when all of the following pass:

1. typed-plan and WAT unit tests for the exact 20-byte root, byte-list child,
   `i32.load8_u` copy, and canonical `(i32)` import;
2. positive and negative source-level compiler fixtures with failure before WAT;
3. manifest-backed Component assembly and Rust/Wasmtime host execution;
4. ARC/GC canonical-boundary equivalence with equal result and cleanup counts;
5. ordinary default `do build`, pinned `wasm-tools 1.255.0` parse, and no-ARC
   output gate;
6. residual gate wiring, full regression, ReleaseSmall, release smoke, and
   `git diff --check`;
7. migration inventory still reports `complete_rows=15 pending_rows=15` with
   its deliberate non-zero status.
