# GC Core And Async Resource Scope

## Intent

The v1 language keeps Wasm GC as the production memory model and completes the
remaining synchronous core builtin lowering before expanding general WASI
async/resource support.

## Decisions

- General WASI async/resource support is in the v1 roadmap, but it is a separate
  implementation phase with its own ABI and lifecycle gates.
- The immediate phase is GC synchronous core parity: numeric arithmetic,
  comparisons, bitwise operations, count operations, conversions, boolean
  short-circuiting, and floating point operations.
- Ordinary Do objects remain GC managed. Public `own<T>`, `borrow<T>`,
  `ref<T>`, pointers, and lifetime syntax remain outside the v1 source model.
- External WASI/Component resources retain explicit API-defined close/drop
  behavior. GC does not close external resources.
- Unsupported async/resource and aggregate shapes remain fail-closed until their
  dedicated lowering is implemented.

## Chosen Implementation

Extend the existing `src/build/codegen_gc_sync.zig` `BodyEmitter` with the core
operation forms already recognized by the parser and semantic layer. Each group
uses its existing compile fixture as the red test, emits typed Wasm instructions
on the GC route, removes only the corresponding pending entry, and updates the
WAT expectation. ARC lowering is retained only for the existing equivalence
oracle.

The immediate order is:

1. Variadic scalar arithmetic and numeric selection (`02`, `12`).
2. Wasm type casts, bitwise operations, count operations, and conversions
   (`13`, `15`, `16`, `17`).
3. Boolean short-circuiting and floating point operations (`18`, `19`).
4. Full regression, documentation status, and review of remaining pending
   categories.

## Non-goals

This phase does not implement general async calls, arbitrary Future/Stream
composition, WIT resource transfer, borrowed data across suspension, public
ownership syntax, or general host/WIT aggregate lowering.

## Success Criteria

The eight listed compile fixtures lower through the GC route with their typed
Wasm expectations, their pending entries are removed, static and dynamic safety
behavior remains unchanged, and `./src/build/test/run_tests.sh` passes with no
new pending mismatch.
