# Multiple Nested Owned Resource Paths Design

> Bounded G6.2 follow-up. This slice does not expose WIT ownership syntax in Do.

## Goal

Extend the private record-stream consumer to admit more than one top-level
nested resource path while preserving descriptor-driven canonical storage and
frame-owned exactly-once cleanup.

The accepted shape is a record such as:

```text
ResourceEntry {
    left LeftEntry
    right RightEntry
}

LeftEntry  -> own<ticket>
RightEntry -> own<ticket>
```

Each path may contain the already accepted one- or two-level nested record
chain, but every path has exactly one final owned `ticket` leaf.

## Boundary

- A record with nested paths has no non-nested top-level source fields.
- Every top-level path has exactly one child at each container level.
- Intermediate containers have empty storage, no ownership, no resource, and no
  drop import metadata.
- A leaf uses one aligned Core `i32` storage field and `ownership: "own"`.
- Multiple leaves may name the same resource; WIT resource declarations and
  Core drop imports are deduplicated by resource/drop identity.
- The record is decoded and discarded in the existing frame; no resource may
  escape, be copied, or participate in another operation.
- Third-level paths, multiple children in one container, nested scalar/string,
  borrow/list/variant fields, and mixed top-level scalar plus nested paths are
  rejected.
- No public `own<T>`, `borrow<T>`, or `ref<T>` syntax is added.

## Data flow

The manifest parser validates every top-level path and recursively checks its
single-child chain. The emitter walks the paths in source order. Each leaf
gets the next four-byte frame-owned slot, the corresponding Core handle is
loaded during decode, and release checks/drops/clears every slot before the
record-active bit is cleared. WIT record declarations are emitted deepest
first for each path; identical resource names and drop imports are emitted
once.

## Verification

The gate requires manifest acceptance and rejection tests, emitter WAT/WIT
marker tests, pinned registry lookup, a private Do/WIT Component assembly
fixture, and a Rust/Wasmtime pending/ready/error runner. The runner must
observe two entries, four resource creations/drops, one stream drop, one future
drop, and an empty resource table for all completion modes.
