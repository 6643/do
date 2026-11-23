# Synchronous Tuple Marshal Design

## Intent

Add the first synchronous WIT Tuple marshal slice to the GC-first component
boundary. A Tuple is an anonymous aggregate whose children are addressed by
numeric position. Its canonical ABI representation is the recursive flattening
of its scalar children into core words.

The completed slice makes pure scalar and nested scalar Tuples measurable,
lowerable, liftable, and fail-closed when their descriptor facts do not match.
It also admits scalar list children at any Tuple path in both lower and
indirect lift directions, using the measured list layout for each child. This
does not claim arbitrary aggregate payload support.

## Goals

- Represent Tuple as an independent marshal tree node.
- Derive canonical core words recursively for Tuple children.
- Bind measured Tuple layout facts, offsets, size, and alignment.
- Emit synchronous lower and lift paths for pure scalar and nested scalar
  Tuples.
- Emit lower and indirect lift paths for one or more scalar list children at
  direct or nested Tuple paths, copying through measured linear memory.
- Keep the canonical boundary free of GC references.
- Preserve exact rejection for unsupported Tuple children and async/resource
  shapes.

## Non-goals

- Async, future, stream, resource, borrowed, or owned payload lowering.
- Arbitrary map lowering.
- Tuple children containing text, map, option, result, or variant.
- Lists nested inside lists and general complex list element lowering.
- Rewriting Tuple into a named record or exposing synthetic field names.

## Constraints

- `doc/memory.md` remains authoritative for the GC-first runtime model.
- Measured facts are required before WAT emission.
- A measured shape mismatch must fail before WAT is generated.
- Existing record/list/map/variant behavior must remain unchanged.
- Core words use the existing `i32`, `i64`, `f32`, and `f64` canonical types.

## Approaches

### Tuple as a record

This would reuse record emitters quickly, but it invents field names and makes
record-specific type and field assumptions part of Tuple behavior. It also
makes future Tuple nesting and diagnostics ambiguous.

### Independent Tuple aggregate

Tuple gets its own `NodeKind` and copy shape. Children retain their numeric
order and measured offsets. Shared scalar flattening helpers can be reused,
while record emitters remain record-specific. This is the selected approach
because it preserves the source shape and keeps the ABI contract explicit.

### General aggregate abstraction first

A broad aggregate framework could eventually cover records and Tuples, but it
would expand this change into unrelated complex-child and cleanup behavior.
It is deferred until the scalar Tuple slice provides concrete shared
requirements.

## Selected behavior

For a Tuple such as `tuple<u32, i64, f32>`:

- the marshal tree is `tuple(scalar, scalar, scalar)`;
- measured children must occur in the same order as the source Tuple;
- each child offset must match the measured layout;
- the lower canonical signature is `(i32, i64, f32)`;
- the lift canonical result signature is `(i32, i64, f32)`;
- lowering loads the Tuple's children in order and calls the canonical import;
- lifting constructs the Tuple value from canonical results in order.

Nested scalar Tuples flatten recursively in source order. A Tuple containing
text, map, option, result, variant, resource, future, or stream remains
unsupported. A Tuple may contain one or more scalar list children, including
lists inside nested Tuples. Lower represents each list as canonical
`(i32,i32)`, copies it into its own temporary linear span, and frees spans in
reverse allocation order after the canonical call. Lift requires root indirect
metadata with one `i32` core word and `cabi_realloc` allocation/free actions;
the canonical import receives the result-area pointer, then the compiler reads
each Tuple field and list `(ptr,len)` from the sum of its measured path offsets,
copies every list into a GC typed array, frees all linear spans, and only then
constructs and publishes the GC Tuple. Lists nested inside lists, complex list elements,
and resource, future, and stream shapes remain rejected by the registry or
marshal plan.

## Validation and tests

The tests cover Tuple node construction, canonical lower/lift signatures,
nested flattening, measured byte size/alignment/offset checks, WAT/module
declarations, and fail-closed rejection of unsupported children and async or
resource payloads. Existing full regression and ReleaseSmall build commands
remain required before delivery.

