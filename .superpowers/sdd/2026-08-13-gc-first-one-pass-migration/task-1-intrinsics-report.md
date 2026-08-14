# Task 1 Intrinsics Report: Synchronous GC `@len` and `@eq`

## Status

Implemented the bounded scalar intrinsic slice. The synchronous GC emitter now
lowers `@len` for already-admitted managed `text`, `[u8]`, and registered scalar
array values, and lowers `@eq` for already-admitted core scalar values. The
default backend route and all async, WIT, resource, generic-admission, and
producer boundaries remain unchanged.

## Files Changed

- `src/build/codegen_gc_sync.zig`
  - Added strict parsed `@len` lowering to `struct.get $do_text $length` or
    typed `array.len`.
  - Added strict parsed scalar `@eq` lowering to `i32.eq`, `i64.eq`,
    `f32.eq`, or `f64.eq` based on the admitted operand type.
  - Reused the existing admitted expression emitter for operands, preserving
    existing call/get/list admission and rejecting managed references and
    aggregates at the intrinsic boundary.
  - Added positive WAT assertions and negative fail-closed tests.
- `.superpowers/sdd/2026-08-13-gc-first-one-pass-migration/task-1-intrinsics-report.md`
  - This report. The directory is ignored by the repository's SDD ignore rule;
    it must be force-added when committing because the task explicitly
    requires this artifact.

## Observed Red Failure

Before the implementation, both new positive tests failed in
`BodyEmitter.emit_expr` with `error.UnsupportedGcSyncExpression` at the generic
call fallback. This confirmed that the tests exercised the missing intrinsic
lowering rather than existing behavior.

## Verification

- `cd src && zig test build/codegen_gc_sync.zig`: passed, `146/146`.
- `cd src && zig test build/codegen_gc_emit_test.zig`: passed, `29/29`.
- `cd src && zig test build/codegen_gc_roots.zig`: passed, `0` tests, exit 0.
- `git diff --check`: passed.

## Residual Concerns

- The normal CLI/compiler path still uses the ARC transition backend; this
  change does not alter default routing or claim G5b/G5c completion.
- `@len` is intentionally limited to the currently admitted managed leaf
  shapes. Managed structs, unions, resources, generic/unresolved values, and
  unsupported producers remain rejected before WAT completion.
- `@eq` is intentionally limited to core scalar values. Managed reference
  identity/content comparison, `@ne`, and aggregate comparison remain outside
  this slice.
- The focused Zig tests assert emitted WAT fragments. The full integration
  runner and a standalone Wasmtime oracle for these two new expressions were
  not rerun because this shared checkout contains unrelated dirty changes.
