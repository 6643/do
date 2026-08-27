# G5c C15-B: private scalar-plus-text record lower

## Status

Selected and implemented as a bounded private manifest-backed probe. This
slice does not change the default host/WIT route, does not admit arbitrary
aggregate lowering, and does not close the G5c cutover.

## Goal

Prove that the GC-first marshal route can lower one fixed WIT record containing
one scalar and one managed `string` field into the canonical Component ABI.
The gate must preserve the record value, copy the managed bytes into linear
memory, call the host exactly once, and release the temporary string buffer
exactly once after the call.

## Selected WIT shape

```wit
package demo:marshal-record-managed-lower@1.0.0;

interface api {
  record writing {
    code: u32,
    label: string,
  }

  write: func(value: writing);
}
```

The private world imports `api` and exports `run: func() -> u32`. The GC probe
constructs `{ code: 7, label: "hello" }`. The host callback must observe the
same two fields and exactly one call.

## ABI evidence and measured layout

The pinned `wasm-tools 1.255.0 (76e20611d 2026-07-30)` probe was run against
the exact WIT shape. `component new` rejects a canonical import with one or
two `i32` parameters and accepts three `i32` parameters (with an exported
linear memory). The canonical lower import is therefore:

```wat
(type $canonical_lower (func (param i32 i32 i32)))
```

The three parameters are the flat values `code`, `label.ptr`, and
`label.len`. The measured canonical record facts are:

| field | offset | size | alignment |
| --- | ---: | ---: | ---: |
| `code` | 0 | 4 | 4 |
| `label.ptr` | 4 | 4 | 4 |
| `label.len` | 8 | 4 | 4 |
| `writing` | 0 | 12 | 4 |

The record has no indirect result/argument area. The module still exports
linear memory because the Component adapter requires memory for the string
canonicalization path.

## GC lower algorithm

1. Load `code` and the `label` GC text from the input `$do_record`.
2. Guard `label.length <= array.len(label.bytes)`.
3. Call `$cabi_realloc(0, 0, 1, label.length)` once.
4. Copy each byte from `$do_bytes` into the allocated linear span.
5. Call the canonical import with `(code, ptr, label.length)`.
6. Call `$cabi_realloc(ptr, label.length, 1, 0)` once, after the host call.

No GC reference crosses the canonical import. The record and text remain GC
values; only the temporary UTF-8 bytes cross through linear memory.

## Admission and rejection

The private descriptor route admits exactly the root shape
`record { u32, string }` with the measured offsets above. It rejects source,
package, world, member, direction, signature, or hash drift; an indirect
layout; missing/extra children; a non-`u32` scalar; nested managed fields;
lists, variants, options/results, resources, async members; and any GC
reference in a canonical slot. Existing scalar-only and indirect scalar
record probes remain unchanged.

## Verification gates

- focused Zig route/operation/emitter tests, including a RED shape test;
- Core WAT parse and Component embed/new/validate with the pinned toolchain;
- source-hash drift rejection;
- Rust/Wasmtime host execution observing `code=7`, `label="hello"`, one call,
  and one allocation/free pair;
- ARC/GC equivalence observing identical fields, call count, and cleanup;
- full compiler regression, ReleaseSmall build, migration inventory, and
  residual gate.

## Non-goals and rollback

This slice does not implement text fields in arbitrary records, multiple
managed fields, list fields, recursive aggregate lowering, async/resource
lowering, default route wiring, or public ownership syntax. If any measured
fact or boundary gate fails, remove only the C15-B descriptor/probe/gate and
leave prior C15-A and scalar lower evidence intact.
