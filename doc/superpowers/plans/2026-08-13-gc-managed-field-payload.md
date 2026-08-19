# G5a Managed-Field Payload Rebuild Plan

**Goal:** lower one direct `[u8]` payload replacement through the parsed
synchronous GC entry while preserving immutable outer-struct semantics.

**Spec:** `doc/superpowers/specs/2026-08-13-gc-managed-field-payload-design.md`

## Tasks

- [x] Add the positive and negative parsed-emitter tests and observe RED before
  implementation.
- [x] Admit only managed `[u8]` fields with a direct `[u8]` local replacement;
  preserve scalar-field rebuild behavior and reject other managed payloads.
- [x] Add the test-only probe shape, fixture, and Wasmtime gate.
- [x] Run the 12-probe GC oracle, default regression, GC regression, formatting,
  and diff checks; synchronize status documents with exact results.

Verification on 2026-08-13:

- `zig test build/gc_sync_probe.zig`: `26/26`.
- `zig test build/codegen_pipeline.zig`: `102/102`.
- `zig test build/codegen_gc_core.zig`: `48/48`.
- `zig test build/codegen_gc_emit_test.zig`: `18/18`.
- `zig test main.zig`: `395/395`.
- `./src/build/test/run_tests.sh`: `pass=1243 fail=0 skip=3`.
- `RUN_GC_CORE=1 WASMTIME_BIN=/home/_/Public/wasmtime/bin/wasmtime` oracle:
  twelve probes returned `27815` after `wasm-tools parse` and Wasmtime GC
  compilation.
- `zig fmt --check ...` and `git diff --check`: passed.

## Non-goals

No default GC cutover, ARC removal, public ownership/reference syntax, nested
producer admission, text-field replacement, Tuple/storage, imports, async, or
Component/WIT lowering is part of this plan.
