# GC Nested Field Paths Without a Fixed Depth

## Status

Approved by the user on 2026-11-20: remove the fixed managed-segment limit.

## Intent

Allow synchronous Wasm GC lowering of direct-local nested `@get` and `@set`
paths at any depth representable by the source and available compiler memory.
The feature closes the current five-managed-segment ceiling without admitting
other aggregate or producer shapes.

```do
value = @get(root, .child, .child, ... , .value)
root = @set(root, .child, .child, ... , .value, 123)
```

For `@set`, rebuild structs from the terminal parent back to the root, preserve
all untouched fields, and leave the original value unchanged.

## Selected Approach

Replace the fixed arrays in `GenericNestedFieldPath` with compiler-allocated
storage sized as path segments are parsed. Keep the existing iterative parser,
`@get` emitter, and terminal-to-root `@set` reconstruction loops. Release the
temporary path storage on every success and error path.

This follows the current loop-based implementation and removes the arbitrary
depth constant. Adding one more fixed depth would leave the same ceiling and
require another feature change; recursive traversal would add call-stack depth
without helping the emitted path model.

## Scope

- Root is a direct local identifier.
- Each intermediate segment names a managed struct field with a resolved GC
  struct layout.
- The terminal field is an inline Wasm scalar.
- `@set` has exactly one scalar value expression.
- GC is the only runtime route. Verification uses GC lowering and Wasmtime;
  ARC equivalence is not a requirement.

## Non-Goals

No grammar change. No producer-expression roots, dynamic field names, aggregate
terminals, list/tuple/union path expansion, resource fields, async lowering,
host/WIT admission, or ownership syntax changes. Completing this path feature
does not close the broader producer, async/resource, or G5c boundaries.

## Verification

- Unit coverage for both `@get` and `@set` beyond the former five-segment limit
  and at a substantially greater depth, including malformed paths.
- A compiled GC fixture and Wasmtime execution proving deep reads, rebuilt
  values, preservation of untouched fields, and preservation of the source.
- Default GC admission gate, full regression harness, ReleaseSmall build/smoke,
  and `git diff --check`.
- Update the P2 blocker and current capability summaries. Do not add an ARC
  backend or require ARC/GC equivalence.
