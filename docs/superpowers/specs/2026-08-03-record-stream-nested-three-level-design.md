# Three-Level Nested Owned Resource Record Stream Design

> Superseded boundary note: the follow-up four-level gate now admits a fourth
> container level; this document records the original three-level slice.

## Goal

Extend the private descriptor-driven record-stream consumer by one bounded
nested `own<ticket>` path:

`resource-entry.inner.deep.deeper.ticket`.

The path remains a frame-owned value that is decoded, released exactly once,
and never escapes the consumer.

## Boundary

- Admit exactly one top-level nested path with three container levels.
- Each container has exactly one child and no storage, ownership, resource, or
  drop metadata.
- The final leaf has one aligned `i32` storage slot and `ownership: "own"`.
- Keep `borrow`, `list`, `variant`, mixed scalar/nested fields, multiple
  children, resource escape, and deeper paths outside this original slice.
- Keep public Do ownership syntax unchanged; this is registry metadata and
  descriptor-specific lowering only.

## Implementation

The manifest parser raises its explicit nested-depth ceiling from two to three
container levels. Existing recursive WIT declaration, decode, and release
emitters are reused. A private registry descriptor, Do/WIT fixture, and one
Rust/Wasmtime runner variant provide the authoritative execution evidence.

## Verification

The gate requires manifest acceptance/rejection tests, emitter WAT/WIT marker
tests, Component validation, and pending/ready/error Wasmtime runs. Each mode
must observe entries `[111,222]`, two resource creates/drops, three stream
reads including EOF, one completion future drop, one stream drop, and an empty
resource table.
