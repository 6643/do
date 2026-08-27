# G5a Generic Nested Managed-Struct Field Path Design

## Status

Bounded internal refactor. This design removes the repeated one-, two-,
three-, four-, and five-level parser/emitter branches while preserving the
current five-level synchronous GC admission boundary.

## Goal

Represent a direct nested managed-struct field path once and use the same
parser, `@get` emitter, and `@set` reconstruction loop for every admitted
depth from one through five managed links.

The existing source forms remain unchanged:

```do
@get(top, .outer, .inner, .middle, .leaf, .core, .tag)
@set(top, .outer, .inner, .middle, .leaf, .core, .tag, 13)
```

This is an internal codegen change, not a new language feature.

## Evidence and problem

`src/build/codegen_gc_sync.zig` currently has five separate path records,
five parsers, five dispatch branches, and five reconstruction branches. The
behavior is equivalent but each additional depth duplicates validation and
WAT emission logic. The current compiled/Wasmtime/equivalence gates prove
depths one through five and intentionally reject depth six.

## Selected approach

Use one fixed-capacity value record. Fixed capacity keeps parsing allocation
free and preserves the current error/lifetime behavior; the admission limit
is explicit rather than hidden in an allocator or a dynamically growing list.

```text
GenericNestedFieldPath {
    root_local, root_ty,
    layouts[0..managed_depth + 1],
    managed_fields[0..managed_depth],
    managed_depth,
    terminal_field,
    value_start?, value_end?
}
```

`layouts[0]` is the root layout. Each `managed_fields[i]` selects the child
layout in `layouts[i + 1]`. `terminal_field` belongs to
`layouts[managed_depth]` and must be an inline core scalar.

The fixed capacity is five managed links for this slice. A sixth link is
rejected with the existing `UnsupportedGcSyncExpression` boundary before WAT
is emitted. Raising the capacity is a separate design and gate; this change
does not admit deeper paths.

### Rejected alternatives

1. **Add a sixth hard-coded record/parser/emitter.** This preserves behavior
   but increases duplicated code and makes every future depth another special
   case.
2. **Use allocator-backed dynamic arrays now.** This removes the depth bound
   but adds ownership and cleanup paths to a hot parser result without a
   product decision to admit arbitrary depth.

The fixed-capacity record gives the structural benefit without widening the
language boundary.

## Data flow

```mermaid
flowchart LR
    A[Token arguments] --> B[Generic path parser]
    B --> C{1..5 managed links?}
    C -->|no / sixth| D[UnsupportedGcSyncExpression]
    C -->|yes| E[GenericNestedFieldPath]
    E --> F[@get chain emitter]
    E --> G[@set terminal-to-root rebuild]
    F --> H[Existing GC WAT]
    G --> H
    H --> I[Existing compiled / Wasmtime / equivalence gates]
```

## Parser contract

- The root is one direct local identifier.
- Every intermediate segment is a named field with `rep == .gc_managed` and
  a registered GC struct layout.
- The terminal segment is a named field with an inline core-Wasm scalar type.
- `@get` has no value expression; `@set` has exactly one value expression.
- A direct managed field without a nested segment continues through the
  existing non-nested path and is not consumed by this parser.
- Dynamic path segments, producer roots, spread/multi-value updates, resource
  fields, async/host calls, and a sixth segment remain rejected.

## Emitter contract

### `@get`

Emit `local.get` followed by one `ref.as_non_null`/`struct.get` pair for each
managed link, then the terminal scalar `struct.get`. The order and WAT shape
must remain equivalent to the current one- through five-level output.

### `@set`

For the terminal layout, emit every field in declaration order, replacing only
the terminal scalar with the value expression. Emit `struct.new` and save the
new child in the existing nested temporary local. Walk the path toward the
root; at each parent replace exactly the selected child field with the saved
temporary and load all other fields through the original root chain. Emit one
`struct.new` per path layout, leaving the rebuilt root as the expression
result.

Untouched scalar fields and managed payload references must remain observable
and the original root must remain unchanged, preserving existing value
semantics.

## Compatibility and non-goals

- No public syntax, type, ownership, reference, or lifetime change.
- No `own<T>`, `borrow<T>`, `ref<T>`, `Option`, or `Result` change.
- No producer-expression, async, resource, host/WIT, tuple, list, or union
  admission change.
- No migration inventory row changes; `complete_rows=15 pending_rows=15`
  remains the expected status.
- Existing shorter paths and direct field setters must retain their current
  behavior and diagnostics.

## Verification and rollback

Focused unit tests must cover a one-level and five-level `@get/@set` plus the
existing sixth-level rejection. Existing five-level compiled and Wasmtime
probes must remain green. The full regression, ReleaseSmall smoke, G5c
baseline, semantic-equivalence, and `git diff --check` gates are required.

If any gate fails, revert only the generic path implementation and its direct
tests; do not weaken the sixth-level negative or migration inventory gates.
