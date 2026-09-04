# Task 8 Step 2 GC async equivalence toolchain-boundary batch

Date: 2026-09-04

## Scope

`test_gc_async_frame_equivalence.sh` already assembled both GC and linear
Components through `do-toolchain` and executed the Rust/Wasmtime runner. Its
remaining `WASMTIME_BIN`/`wasmtime_bin` check was an unused CLI dependency: the
script does not invoke the Wasmtime CLI, and runtime execution is provided by
the locked Rust Wasmtime crate.

The script now checks and probes the repository `do-toolchain` executable
before assembling either component. GC/linear component construction,
equivalence counters, Rust runner arguments, and cleanup assertions are
unchanged.

## Changed files

- `examples/gc-p3-runtime/test_gc_async_frame_equivalence.sh`

## Verification

- `bash examples/gc-p3-runtime/test_gc_async_frame_equivalence.sh`: passed from the repository root; counters matched (`pending-polls=4`, `external-wakes=4`, `completions=4`).
- `bash /home/_/._/_/do/examples/gc-p3-runtime/test_gc_async_frame_equivalence.sh`: passed from unrelated `/tmp` cwd with the same counters.
- `bash -n examples/gc-p3-runtime/test_gc_async_frame_equivalence.sh`: passed.
- A scoped scan confirms no `WASMTIME_BIN`, `wasmtime_bin`, or direct `$wasmtime` reference remains in this script.
- `bash src/build/test/check_toolchain_adapter.sh`: passed.
- `bash src/build/test/check_run_tests_entrypoint.sh`: passed.
- `cd src && zig build test --summary all`: passed, 14/14 steps and 51/51 tests.
- `git diff --check`: passed.

## Residuals

This only removes an unused CLI prerequisite from the equivalence wrapper; it
does not alter the Rust/Wasmtime runtime oracle or prove generic async
lowering. Remaining GC host/linker and C API boundaries, generic async/Stream
routes, and Task 4 map lifecycle are still separate work.
