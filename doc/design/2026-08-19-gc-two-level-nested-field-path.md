# GC Two-Level Nested Field Path Design

**Status:** implemented bounded slice; direct managed-field call producer follow-up admitted

## Goal

Extend the typed GC synchronous lowering with one additional managed-struct
field segment while preserving immutable published values:

```do
@get(outer, .inner, .leaf, .value)
@set(outer, .inner, .leaf, .value, 9)
```

The existing one-level path (`outer -> inner -> leaf`) remains unchanged.

## Boundary

- The root must be a direct local.
- Both intermediate fields must be admitted GC managed structs.
- `@set` admits only an inline Wasm scalar leaf and the existing direct scalar
  expression rules.
- `@get` uses the existing field type compatibility checks.
- Lowering rebuilds the leaf parent, then the middle parent, then the root;
  unchanged fields are loaded through the original object chain, so the old
  objects remain observable.
- Arbitrary producer expressions, nested/multi-result/mismatched call
  producers, resources, tuples, unions, async functions, WIT/host bindings,
  and paths deeper than two managed segments remain rejected before WAT
  emission. A direct single-result synchronous call with an exact field-type
  match for a managed `[u8]` or `text` field is admitted by the follow-up slice
  below.

## Direct call producer follow-up slice

The bounded GC sync producer admits a managed `[u8]` or `text` field
replacement whose value is one direct synchronous function call with exactly one
result and an exact field-type match. Existing call emission and typed GC
call-result root markers are reused. Nested managed structs and lists, nested
calls, multi-result calls, mismatched results, async/host calls, and arbitrary
expressions remain fail-closed.

## Lowering shape

For a write to `outer.inner.leaf.value`, codegen emits:

1. Load every unchanged field of `leaf` through `outer.inner.leaf`.
2. Emit the new `leaf` and bind it to the reserved GC temporary.
3. Load every unchanged field of `inner` through `outer.inner`, substitute the
   rebuilt `leaf`, and bind the rebuilt `inner`.
4. Load every unchanged field of `outer`, substitute the rebuilt `inner`, and
   emit the rebuilt `outer`.

For a read, codegen follows the same chain with `struct.get` and returns the
   final field value.

## Verification

- Unit RED/GREEN tests in `src/build/codegen_gc_sync.zig` cover a deep scalar
  write, a deep managed-field read, and rejection of a third managed segment.
- A compiled fixture observes both the original and rewritten nested values.
- A Wasmtime GC probe and the ARC/GC equivalence matrix pin the observable
  result and reject `__arc_` in the admitted WAT.
- Status documents state this is a bounded two-level slice; general nested
  aggregates remain pending.
