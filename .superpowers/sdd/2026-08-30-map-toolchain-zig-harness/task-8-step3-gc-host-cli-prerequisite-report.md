# Task 8 Step 3 GC host CLI prerequisite cleanup batch

Date: 2026-09-04

## Scope

Four GC host gates used `wasmtime_bin` only in their executable precondition;
none invoked the Wasmtime CLI. Core parsing/Component assembly already used
the current-only `do-toolchain`, while runtime execution was supplied by the
locked Rust Wasmtime host runner.

The stale CLI prerequisite was removed from these gates. Their explicit
`do-toolchain` checks and Rust linker checks remain, and all host, WIT, Core,
Component, result, and cleanup assertions are unchanged.

## Changed files

- `examples/gc-p3-runtime/test_gc_marshal_u32_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_u32_lift_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_lower_host.sh`

## Verification

- Red static contract before the edit: selected scripts still contained the
  stale `wasmtime_bin` prerequisite and exited 1.
- Root gates: all four passed; observed markers were list lower values
  `[10, 20, 30]`, list lift checksum `60`, scalar record lift sum `42`, and
  scalar record lower result `42` with `write-calls=1`.
- Unrelated `/tmp` gates: all four passed with the same markers.
- `bash -n` for all four scripts: passed.
- Scoped scan for `WASMTIME_BIN`, `wasmtime_bin`, and `$wasmtime`: no matches.
- `bash src/build/test/check_toolchain_adapter.sh`: passed.
- `bash src/build/test/check_run_tests_entrypoint.sh`: passed.
- `cd src && zig build test --summary all`: passed, 14/14 steps and 51/51 tests.
- `git diff --check`: passed.

## Residuals

This closes only the four-script stale CLI prerequisite batch. Remaining GC
host scripts with the same historical check, `run-wasmtime.sh`'s intentional
CLI runtime oracle, C API linker gates, and Task 4 map lifecycle remain
separate work. No generic async/resource or full GC capability is inferred.
