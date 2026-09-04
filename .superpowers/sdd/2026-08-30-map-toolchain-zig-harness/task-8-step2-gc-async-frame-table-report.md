# Task 8 Step 2 GC async frame/table adapter batch

Date: 2026-09-04

## Scope

The Zig pure-lowering matrix now includes
`examples/p3-runtime/two-await-component.do`, the bounded
`--p3-wait-for-component` GC frame/table route. The case preserves the
generated WIT export marker and checks the GC-traced `$async-frame` table,
`table.get`, and `$waitable-set` access while rejecting ARC and linear-memory
frame allocation markers.

For this case, `compile_core_gc` invokes the typed current-only
`do-toolchain compile-core-gc` operation and asserts that the compiled output
exists. The dedicated
`examples/gc-p3-runtime/test_gc_async_frame_component.sh` gate uses the same
adapter operation instead of invoking Wasmtime directly. Component parse,
embed, new, and validate continue to use the adapter and the
`component-async` feature profile.

## Changed files

- `src/build/test/test_harness.zig`
- `examples/gc-p3-runtime/test_gc_async_frame_component.sh`

## Verification

- `cd src && zig test build/test/test_harness.zig --test-filter 'pure lowering matrix covers the bounded async GC frame table'`: passed, 1/1.
- `bash examples/gc-p3-runtime/test_gc_async_frame_component.sh`: passed from the repository root.
- `bash /home/_/._/_/do/examples/gc-p3-runtime/test_gc_async_frame_component.sh`: passed from unrelated `/tmp` cwd.
- `bash examples/gc-p3-runtime/test_gc_async_frame_equivalence.sh`: passed, GC/linear counters matched (`pending-polls=4`, `external-wakes=4`, `completions=4`).
- `bash /home/_/._/_/do/examples/gc-p3-runtime/test_gc_async_frame_equivalence.sh`: passed from unrelated `/tmp` cwd with the same counters.
- `cd src && zig build test --summary all`: passed, 14/14 steps and 51/51 tests; the harness reported the P3 pure-lowering matrix and GC runtime/assembly matrices as passed.
- `bash -n examples/gc-p3-runtime/test_gc_async_frame_component.sh examples/gc-p3-runtime/test_gc_async_frame_equivalence.sh`: passed.
- `bash src/build/test/check_toolchain_adapter.sh`: passed.
- `bash src/build/test/check_run_tests_entrypoint.sh`: passed.
- `git diff --check`: passed.

The first full-harness run caught an incorrect WIT marker in the new case. The
fixture emits `export run: async func(how-long: u64);`; the marker was corrected
to that observed contract before the successful rerun.

## Residuals

This closes only the bounded GC async frame/table pure-lowering sub-batch. It
does not establish generic async-call lowering, arbitrary async producers,
Stream/general async support, host runtime delivery, or full GC cutover. Task
8 Step 2 remains open for the remaining direct-tool and linker-boundary gates;
Task 4 map lifecycle remains blocked on generic map/pair-list ABI lowering and
exactly-once cleanup authority.
