# Task 9 Step 1 GC host prerequisite guard

## Scope

The active toolchain gate now scans `examples/gc-p3-runtime/test_*_host.sh` for
the unused `WASMTIME_BIN`, `wasmtime_bin`, and `$wasmtime` prerequisite forms.
`run-wasmtime.sh` is intentionally outside this glob because it is the direct
Wasmtime runtime oracle. The test creates and removes a temporary matching host
fixture to lock this contract.

## TDD evidence

- RED: before the gate change, `bash src/build/test/check_toolchain_adapter_test.sh`
  exited 1 with `stale GC host Wasmtime prerequisite was accepted`.
- GREEN: after the gate change, the same focused test passed and its temporary
  stale host fixture was rejected by the new scan.

## Verification

- `bash src/build/test/check_toolchain_adapter_test.sh`: passed.
- `bash src/build/test/check_toolchain_adapter.sh`: passed.
- `bash -n src/build/test/check_toolchain_adapter.sh src/build/test/check_toolchain_adapter_test.sh`: passed.
- `zig build test --summary all`: 14/14 steps and 51/51 tests passed.
- `git diff --check`: passed.

## Residuals

This guard only prevents stale CLI prerequisites in GC host test scripts. It
does not remove or change the intentional `run-wasmtime.sh` runtime oracle,
C API linker gates, generic map/async lifecycle, or full GC cutover.
