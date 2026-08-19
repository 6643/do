# G5a Managed-Field Payload Rebuild Design

**Status:** bounded parsed GC migration slice.

## Goal

Admit direct replacement of one managed `[u8]` field while preserving the
published value semantics of the containing struct:

```do
Box {
    value [u8]
    tag i32
}

update(box Box, value [u8]) -> Box {
    return @set(box, .value, value)
}
```

The result is a new `Box`. The old `Box` and its old payload remain observable;
the new `value` reference is selected directly, and unchanged fields are read
from the old struct.

## Fixed Boundary

Admitted only for an otherwise supported synchronous GC program when:

- the receiver is a local of a managed struct type;
- the selected field is exactly `[u8]`;
- the replacement expression is one direct local of exactly `[u8]`;
- the result is the same struct type; and
- no module import, generic, async, resource, multi-result, or Component path
  is present.

The following remain rejected in this slice:

- text or other managed field payload types;
- nested `@set`, `@put`, literal, or general producer expressions as the field
  replacement;
- resource fields, Tuple/storage, unions, generic calls, and imports.

## Lowering Contract

The emitter must evaluate the replacement local once and emit the outer fields
in declaration order. The selected field is loaded from the replacement local;
every other field is loaded from the old receiver and the result is constructed
with `struct.new`. No source object is mutated and no ARC symbol is emitted.

## Verification Gate

The focused unit matrix must prove positive direct payload replacement,
preservation of unrelated scalar fields, rejection of unsupported managed field
types, and rejection of nested producers. The executable probe must validate the
WAT with `wasm-tools`, compile it with Wasmtime GC, and check old/new object
identity, old/new payload contents, and preserved scalar fields.

This is a G5a capability slice only. ARC/GC equivalence remains a G5b task and
the default backend remains ARC until G5c.

## Rollback

Remove this slice's focused test, probe fixture/script, and direct managed-field
guard. Existing scalar-field rebuild and earlier byte-list slices remain
unchanged; the default compiler route is unaffected.
