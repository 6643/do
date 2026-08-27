# G5a Five-Level Nested Managed-Struct Field Path Design

## Status

Bounded implementation slice. This design extends the already admitted direct
one-, two-, three-, and four-level synchronous managed-struct field path by one
fixed additional managed segment.

## Goal

Support this exact synchronous GC shape:

```do
@get(top, .outer, .inner, .middle, .leaf, .core, .tag)
@set(top, .outer, .inner, .middle, .leaf, .core, .tag, 13)
```

The update must rebuild the terminal `Core`, then `Leaf`, `Middle`, `Inner`,
`Outer`, and finally `Top` while reusing every unchanged scalar and managed
payload reference.

## Fixed source shape

```do
Core { value [u8], tag i32 }
Leaf { core Core, tag i32 }
Middle { leaf Leaf, tag i32 }
Inner { middle Middle, tag i32 }
Outer { inner Inner, tag i32 }
Top { outer Outer, tag i32 }

update(top Top) -> Top {
    return @set(top, .outer, .inner, .middle, .leaf, .core, .tag, 13)
}
```

The probe also reads the original and updated scalar/payload chain. The
semantic oracle remains `27815`, matching the existing nested-path probes.

## Admission and rejection

- Only a direct local identifier root is admitted.
- All five path segments must be named managed fields whose child types are
  registered GC struct layouts.
- The terminal field must be a scalar field; the existing payload-preservation
  checks remain in force.
- `@get` accepts the same five managed segments plus the terminal field.
- `@set` accepts the same path plus one scalar literal value.
- Producer expressions, dynamic paths, spread/multi-value updates, async or
  host calls, resource fields, and a sixth segment remain rejected before WAT.
- No public syntax, ownership type, WIT descriptor, inventory row, or ARC
  fallback policy changes.

## Implementation boundary

The parser/emitter gets a dedicated `QuintNestedFieldPath` record and explicit
terminal-to-root reconstruction. The probe gets a matching fixed classifier,
WAT wrapper, and classification test. Existing shorter paths must retain their
dispatch order and output.

## Verification and rollback

The positive fixture must assemble with `wasm-tools 1.255.0`, execute with
Wasmtime GC, and return `27815`; the WAT must contain no `__arc_` markers and
must show all five `struct.get` links and six `struct.new` operations. The
compiled-test fixture must pass the ARC/GC semantic-equivalence matrix. The
default-build fixture count increases by one; the migration inventory remains
`complete_rows=15 pending_rows=15`.

If any focused, full, residual, or equivalence check fails, revert only the
new fifth-level parser/probe/fixture/gate additions. Do not weaken existing
gates or promote generic nested aggregates.
