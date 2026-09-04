# Task 8 Step 2 GC resource terminal adapter batch

Date: 2026-09-04

## Scope

The existing pure-lowering case for
`examples/p3-runtime/async-resource-result-component.do` now enables the
typed `compile_core_gc` path. The matrix therefore compiles its GC async
frame/result WAT through current-only `do-toolchain compile-core-gc` and
asserts the compiled artifact exists, in addition to the existing WIT/WAT
markers and Component validation.

The dedicated `examples/gc-p3-runtime/test_gc_resource_terminal_cleanup.sh`
gate now uses the same adapter operation instead of direct Wasmtime
compilation. Its Rust host, cancellation-shape, cancellation-runtime, and
GC/linear equivalence sub-gates remain unchanged and continue to provide the
resource cleanup evidence.

## Changed files

- `src/build/test/test_harness.zig`
- `examples/gc-p3-runtime/test_gc_resource_terminal_cleanup.sh`

## Verification

- `cd src && zig test build/test/test_harness.zig --test-filter 'pure lowering matrix compiles the async resource Result case with GC'`: RED first failed because the case flag was unset; GREEN passed, 1/1 after the minimal case update.
- `bash examples/gc-p3-runtime/test_gc_resource_terminal_cleanup.sh`: passed from the repository root, including cancellation and exactly-once cleanup markers.
- `bash /home/_/._/_/do/examples/gc-p3-runtime/test_gc_resource_terminal_cleanup.sh`: passed from unrelated `/tmp` cwd with the same resource/cancellation markers.
- `cd src && zig build test --summary all`: passed, 14/14 steps and 51/51 tests; the P3 pure-lowering, GC runtime/assembly, map, and Rust matrices all passed.
- `bash -n examples/gc-p3-runtime/test_gc_resource_terminal_cleanup.sh`: passed.
- `bash src/build/test/check_toolchain_adapter.sh`: passed.
- `bash src/build/test/check_run_tests_entrypoint.sh`: passed.
- `git diff --check`: passed.

## Residuals

This closes only the bounded async resource Result compile-adapter
sub-batch. It does not claim generic async/resource lowering, arbitrary async
producers, Stream/general async support, or full GC cutover. Task 8 Step 2
remains open for residual direct-tool and linker-boundary gates; Task 4 map
lifecycle remains blocked on generic map/pair-list ABI lowering and
exactly-once cleanup authority.
