# G3 synchronous GC aggregate migration report

## Scope

Admitted named managed structs in the restricted synchronous GC lowering path.
The default backend, ARC runtime, CLI, component/WIT lowering, and user
documentation were left unchanged.

## TDD evidence

Added two focused tests in `src/build/codegen_pipeline.zig` before production
changes:

- `synchronous GC lowers a managed struct identity`
- `synchronous GC preserves scalar fields in a managed struct identity`

Red run:

```text
cd src && zig test build/codegen_pipeline.zig --test-filter 'managed struct'
```

Both tests failed at the existing `UnsupportedGcSyncAggregate` guard in
`codegen_gc_sync.zig`.

After the minimal implementation, the same focused command passed 2/2.

## Implementation

- `codegen_gc_model_adapter.zig` now supplies the collected source shapes and
  GC aggregate layouts to sync lowering.
- `GcFieldLayout` retains the source field type, representation, and
  `field_index`; the generic runtime emitter consumes the index and maps
  inline scalars, `text`, `[u8]`, and nested admitted managed structs to WAT
  field types.
- Sync lowering emits `$do_bytes`, `$do_text`, and named lower-case GC struct
  declarations before function signatures. Function params, results, locals,
  scalar constants, and root classification use the same adapter facts.
- Unsupported resources, tuples/lists outside the admitted leaves, recursive
  aggregates, and other existing fail-closed surfaces remain rejected.

## Verification

| Command | Result |
| --- | --- |
| `cd src && zig test build/codegen_pipeline.zig --test-filter 'managed struct'` | PASS, 2/2 |
| `cd src && zig test build/codegen_pipeline.zig` | PASS, 84/84 |
| `cd src && zig test build/codegen_gc_sync_adapter.zig` | PASS, 9/9 |
| `cd src && zig test build/codegen_gc_model_adapter_test.zig` | PASS, 16/16 |
| `cd src && zig test main.zig` | PASS, 394/394 |
| `cd src && zig build -Doptimize=ReleaseSmall` | PASS |
| `./src/build/test/run_tests.sh` | PASS, 1243 passed, 0 failed, 3 skipped |
| `zig fmt --check src/build/codegen_gc_layout.zig src/build/codegen_gc_sync.zig src/build/codegen_gc_sync_adapter.zig src/build/runtime_gc_wat.zig src/build/runtime_gc_prelude_wat.zig src/build/codegen_pipeline.zig` | PASS |
| `git diff --check` | PASS |

## Concerns

- This remains an internal oracle path. It emits typed declarations and
  identity/reference flow only; ownership/release lowering is intentionally
  untouched and aggregate construction/update expressions remain unsupported.
- Type names are lowered to lower-case WAT names for this restricted path,
  matching the current `$box` convention. Broader name collision/mangling
  policy is outside this migration unit.
