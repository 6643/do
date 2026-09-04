# Task 8 Step 1 GC runtime-oracle adapter batch

Date: 2026-09-04

## Scope

The two bounded GC runtime-oracle gates below now route every external tool
operation through the repository-owned current-only `bin/do-toolchain`:

- `examples/gc-p3-runtime/test_async_frame_table.sh`
- `examples/gc-p3-runtime/test_cabi_realloc_budget.sh`

The Zig integration harness has an explicit `GC runtime oracle matrix` with the
same fixtures and probe contract. It uses typed `parse-core`,
`compile-core-gc`, and `invoke-core-gc` operations. The runtime oracle remains
Wasmtime-backed by design; this batch centralizes its invocation and does not
claim P3 host binding or generic map lifecycle support.

## Verification

- `cd src && zig test build/test/test_harness.zig --test-filter 'GC runtime oracle matrix'`: passed.
- `cd src && zig test build/test/test_cases.zig --test-filter 'integration case table'`: passed.
- `bash -n examples/gc-p3-runtime/test_async_frame_table.sh examples/gc-p3-runtime/test_cabi_realloc_budget.sh`: passed.
- `cd src && zig build test --summary all`: `14/14` steps, `51/51` tests passed.
- Root working directory: both scripts passed.
- Unrelated `/tmp` working directory: both scripts passed.
- Async frame probes: `27815`, budget `1`, canonical budget `1`.
- C ABI realloc probes: usage `4`, rollback `1`, quota rejection trapped.
- `git diff --check`: passed.

## Remaining scope

This closes only the two GC runtime-oracle scripts in Task 8 Step 1. The
remaining GC marshal/host linker and async/component scripts still require
individual classification. Wasmtime calls that are the runtime oracle may
remain behind the adapter; pure tool operations must continue to migrate.
Task 4 map lifecycle (async input copy, Stream cross-poll ownership, and
exactly-once cleanup) remains blocked by missing generic map/pair-list lowering.
