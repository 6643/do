# G5c Scalar Call-Graph Boundary Design

## Status

Approved continuation of the bounded G5c synchronous scalar route. This slice
hardens an existing capability; it does not introduce a new public syntax or
claim a full GC cutover.

## Evidence

The current scalar-leaf route already emits a non-recursive scalar helper call
as typed GC WAT, including a direct `call $helper`. The same route currently
admits mutual recursion and emits `;; gc-sync`; that contradicts the existing
fail-closed scalar admission contract, which rejects recursive shapes. The new
RED test in `src/build/codegen_pipeline.zig` reproduces that case.

The scalar control-flow route remains narrower: its condition and return
expression scanner accepts scalar atoms and `@eq` only. This design does not
widen those expressions to calls.

## Goal

Make the default typed-GC scalar route admit only a finite, acyclic,
same-module scalar call graph while preserving already-working non-recursive
helper calls.

```mermaid
flowchart TD
    source[scalar program] --> shape{scalar headers and body shape}
    shape -->|reject| fallback[existing fallback / diagnostic]
    shape -->|accept| graph[collect top-level call edges]
    graph --> cycle{cycle?}
    cycle -->|yes| fallback
    cycle -->|no| gc[typed GC scalar route]
```

## Admission contract

1. Every non-`start` function still has only Core Wasm scalar parameters, one
   scalar result, and a body already accepted by the scalar-leaf or restricted
   scalar-control-flow predicate.
2. A direct call to another top-level function remains allowed when the
   existing `BodyEmitter` can type-check and lower it.
3. The top-level call graph, including `start`, must be acyclic. Self-recursion,
   mutual recursion, and cycles of any length fall back before GC emission.
4. Imported module graphs, host/WIT bindings, managed declarations, async,
   resources, loops, `defer`, unsupported expressions, and unsupported headers
   retain their current fallback or diagnostic behavior.
5. The detector is fail-closed on malformed declaration ranges or unresolved
   call targets. It must not add an allocator, global state, or a public API.
6. No grammar, ownership, `Option`, `Result`, `Future`, `Stream`, or WIT
   semantics change.

## Detection boundary

The detector scans only identifier-call pairs in top-level function bodies;
intrinsics prefixed by `@` are not user-function edges. For each declared
function, it recursively follows declared callees with a token-count bound.
Reaching the starting function proves a cycle. The bound is finite because a
simple path cannot contain more top-level declarations than the token stream;
exceeding it is treated as a cycle and therefore falls back.

This intentionally does not attempt general call-graph optimization,
inlining, imported symbol resolution, or recursion lowering.

## Verification and rollback

- The mutual-recursion unit test must fail before the detector and pass after
  it.
- A positive fixture with a three-function acyclic scalar chain must retain
  `;; gc-sync`, contain calls to the helper functions, contain no `__arc_`, and
  parse with `wasm-tools 1.255.0`.
- The full regression, release smoke, default 79-fixture gate, residual gate,
  and 26-row semantic-equivalence matrix must remain green.
- The migration inventory must remain intentionally
  `complete_rows=15 pending_rows=15`.
- If verification fails, revert only this detector, its tests, fixture, gate,
  and documentation; do not weaken existing negative tests or change the ARC
  fallback.

## Non-goals

This slice does not add control-flow calls, loops, arbitrary producer
expressions, imported calls, managed call graphs, async/resource lowering,
ownership syntax, or full G5c/GC cutover.
