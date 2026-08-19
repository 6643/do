# Four-Level Nested Owned Resource Record Stream Design

## Goal

Extend the private descriptor-driven record-stream consumer to one bounded
four-level nested `own<ticket>` path:

`resource-entry.inner.deep.deeper.deepest.ticket`.

The path remains frame-owned, decoded recursively, and released exactly once.

## Boundary

- Admit exactly one top-level nested path with four container levels.
- Each container has exactly one child and no storage, ownership, resource, or
  drop metadata.
- The final leaf has one aligned `i32` storage slot and `ownership: "own"`.
- Keep fifth-level paths, `borrow`, `list`, `variant`, mixed scalar/nested
  fields, multiple children, and resource escape rejected.
- Keep public Do `own<T>`, `borrow<T>`, and `ref<T>` syntax unchanged; this is
  registry metadata and descriptor-specific lowering only.

## Implementation

Raise the manifest parser's explicit nested-depth ceiling from three to four.
Reuse the existing recursive WIT declaration, decode, and release emitters.
Register a private descriptor and add Do/WIT plus Rust/Wasmtime fixtures. The
accepted path must preserve the canonical frame-owned handle slot and the
existing exactly-once cleanup protocol.

## Verification

The gate requires manifest and emitter tests, registry admission, WAT/WIT
Component validation, and pending/ready/error Wasmtime runs. Each runtime mode
must observe entries `[111,222]`, two resource creates and drops, three stream
reads including EOF, one completion future drop, one stream drop, and an empty
resource table.
