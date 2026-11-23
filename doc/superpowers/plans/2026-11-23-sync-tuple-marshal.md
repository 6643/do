# Synchronous Tuple Marshal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add measured synchronous lower/lift support for pure scalar and nested scalar WIT Tuples.

**Architecture:** Keep Tuple as an anonymous aggregate in the marshal tree. Extend the existing recursive plan and canonical word machinery, add a Tuple-specific memory plan and emitter path, and keep complex/async/resource shapes fail-closed.

**Tech Stack:** Zig compiler, WIT resolver, measured canonical ABI plans, WAT text emitters, Zig unit and integration tests.

**Spec:** `doc/superpowers/specs/2026-11-23-sync-tuple-marshal-design.md`

## Global Constraints

- Measured facts are required before WAT emission.
- A measured shape mismatch must fail before WAT is generated.
- The canonical boundary must not expose GC references.
- Pure scalar and nested scalar Tuple children plus scalar list children at
  direct or nested Tuple paths are admitted in this phase.
- Async, future, stream, resource, borrowed, and owned payloads remain rejected.

## Review Focus

- Tuple child order must stay identical between WIT source, measured facts, canonical words, and WAT loads/stores.
- Nested Tuple offsets must be added exactly once at each aggregate level.
- Wide scalar alignment and byte size must match the existing scalar layout rules.
- A Tuple with an unsupported child must fail before module assembly.
- Existing record, variant, scalar-list, and map routes must retain their current signatures and output.

## File Map

- `src/build/codegen_component_marshal_plan.zig`: Tuple node construction, measured binding, canonical type naming, alignment, and recursive core words.
- `src/build/codegen_component_marshal_ops.zig`: Tuple copy shape and measured memory-plan validation.
- `src/build/codegen_component_marshal_wat.zig`: Tuple lower/lift loads, stores, and value construction.
- `src/build/codegen_component_marshal_module.zig`: Tuple canonical import type declarations and wrapper type assembly.
- `src/build/codegen_component_marshal_registry.zig`: Exact WIT Tuple admission and recursive child conversion.
- `src/build/codegen_gc_plans_test.zig` and focused module/WAT tests: red/green coverage for public routing and output.
- `doc/spec_rules.md` or the relevant current component ABI documentation: supported Tuple contract and fail-closed boundary.

## Tasks

- [x] **Task 1: Add failing Tuple plan tests.** Add tests for `tuple<u32, i64, f32>` and nested scalar Tuple construction, canonical lower/lift word order, and Tuple text/resource rejection. Run the focused Zig test and confirm failure is `UnsupportedMarshalShape` or the current equivalent because Tuple is not admitted.

- [x] **Task 2: Implement Tuple plan and canonical flattening.** Add the independent Tuple node and `.tuple_fields` copy shape, compute child offsets using existing alignment rules, derive Tuple canonical names and recursive core words, and preserve source order. Run the focused plan tests.

- [x] **Task 3: Add measured Tuple binding tests and implementation.** Add passing and mismatch cases for child count, child offset, byte size, alignment, and nested Tuple facts. Bind measured facts recursively and reject any unsupported layout or child shape before a plan is returned.

- [x] **Task 4: Add failing Tuple WAT lower/lift tests.** Assert that lower emits the scalar loads and canonical call in Tuple order, and lift consumes canonical results in that order to construct the aggregate. Assert that nested Tuples flatten without duplicate offsets.

- [x] **Task 5: Implement Tuple memory operations and WAT emitters.** Extend `MemoryPlan`, operation validation, and the WAT dispatcher with Tuple-specific scalar-only paths. Keep text/list/map/variant children rejected in this phase.

- [x] **Task 6: Implement Tuple module declarations.** Emit canonical import signatures from the Tuple canonical signature and declare the wrapper's anonymous Tuple representation without synthetic record field names. Add module output assertions for lower and lift.

- [x] **Task 7: Admit parser-backed WIT Tuples precisely.** Convert parser Tuple children recursively in the registry, then reject any child outside the pure scalar/nested scalar subset. Add route tests for positive Tuple lower/lift and negative Tuple text/resource/future cases.

- [x] **Task 8: Add one measured direct list child to Tuple lower.** Add plan, measured-layout, operation, WAT/module, and parser-route coverage for one direct `list<u8>` or `list<u32>` child in lower direction. Reject list lift, multiple list children, nested Tuple list children, and every unsupported child before WAT assembly. Check `length * stride` overflow and free temporary linear memory after the canonical call.
- [x] **Task 9: Synchronize documentation and verify.** Update the current component ABI/spec documentation, run focused tests, `./src/build/test/run_tests.sh`, and the ReleaseSmall build. Review the final diff for fail-closed behavior, documentation drift, and unrelated changes.
- [x] **Task 10: Add indirect Tuple list lift.** Admit scalar list children only when the Tuple root has one `i32` indirect result word and `cabi_realloc` allocation/free metadata. Read Tuple scalars and every list span from measured result-area offsets, copy to GC typed arrays, free all linear list spans, and retain rejection for list-of-list or unsupported types.
- [x] **Task 11: Wire the exact Tuple byte-list lift through the compiler manifest route.** Pin source/WIT hashes and measured Tuple layout in `gc_descriptor_manifest.json`, validate the Do Tuple signature, generate the compiler wrapper, reject type drift, and execute the generated Component with a host callback.
- [x] **Task 12: Wire the exact Tuple u32-list lift through the compiler manifest route.** Pin the 4-byte list measurement, reuse the indirect result-area path, deduplicate shared `$do_u32` type emission, reject element-type drift, and execute the generated Component with a host callback.
- [x] **Task 13: Verify non-final list position in Tuple lift.** Add a measured `Tuple<list<u8>, u32>` WAT regression so the list copy and scalar load use their positional measured offsets rather than assuming the list is the final field.
- [x] **Task 14: Generalize Tuple scalar-list paths.** Admit all current scalar typed-array kinds, multiple direct list children, and lists inside nested Tuples. Keep list-of-list, complex list elements, map/record/text children, async/resource payloads, and arbitrary unmeasured indirect layouts fail-closed. Validate reverse lower cleanup and pre-construction lift cleanup order.

## Verification Commands

```bash
cd src && zig build test
./src/build/test/run_tests.sh
cd src && zig build --prefix .. -Doptimize=ReleaseSmall
```

