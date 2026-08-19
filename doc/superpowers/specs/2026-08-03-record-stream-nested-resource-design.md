# Nested Owned Resource Record-Stream Design

> Bounded G6.2 follow-up. This slice does not expose WIT ownership syntax in Do.

## Goal

Admit private record-stream descriptors whose element contains one bounded
nested path with one `own<ticket>` resource field, while preserving
frame-owned exactly-once cleanup. The accepted path is at most two nested
record levels (`ResourceEntry -> InnerEntry -> DeepEntry -> own<ticket>`).

## Boundary

- Do source uses ordinary `InnerEntry` and `ResourceEntry` records only.
- The registry admits exactly one nested path and exactly one owned resource
  child. The path may contain one or two nested record levels; intermediate
  containers have no Core storage or ownership metadata.
- The nested child is backed by one aligned Core `i32` storage slot.
- The record is discarded after decode; the nested resource cannot escape,
  copy, or participate in another operation.
- Borrowed, list, variant, recursive, multiple nested paths, a third nested
  level, and nested scalar/string children remain rejected.
- Generated `own<ticket>` and `[resource-drop]ticket` occur only in the
  private WIT sidecar and Core imports.

## Data flow

The manifest records a parent source field with recursively bounded
`nested_fields`. The emitter walks the single path, generates deepest-first
private WIT records, reserves one frame-owned handle slot, loads the nested
Core handle into that slot, and releases/clears it before the record-active
bit is cleared. The existing stream/future cleanup remains unchanged.

## Verification

The slice requires manifest and emitter unit tests, generated WAT/WIT markers,
Component assembly/validation, and Rust/Wasmtime pending/ready/error probes
for both accepted depths that observe one resource drop per record and an
empty resource table.
