# Rust P3 Wait-For Adapter Plan

**Goal:** Verify that Wasmtime Rust 47.0.2 can link and execute the one pinned
WIT-level async import that the C API cannot declare.

**Scope:** only `wasi:clocks@0.3.0/monotonic-clock.wait-for`,
`async func(u64)` with no result, one Store, one component call, and an empty
`task.return` completion.

**Non-goals:** compiler lowering, generic P3/WASI support, cancellation,
resources, Stream/Future lowering, or removal of `AsyncLoweringUnavailable`.

## Steps

- [x] Add a shell regression script requiring explicit duration, pending-poll,
  and completion output markers.
- [x] Confirm red state: the script fails before the Cargo project exists.
- [x] Add a standalone Rust package pinned to `wasmtime = 47.0.2` with a
  checked-in lockfile.
- [x] Configure component model, component async, more async builtins, and
  concurrency support.
- [x] Register `wait-for` with `Linker::instance(...).func_wrap_concurrent`.
- [x] Use `Store::run_concurrent` and `TypedFunc::call_concurrent` to invoke
  exported async `run`.
- [x] Assert one `27815` call, one intentional `Pending`, and one completion.
- [x] Preserve the existing C probe and document that its WIT async-type
  limitation remains C-API-specific.

## Verification

```bash
examples/p3-runtime/test_rust_wait_for.sh
examples/p3-runtime/test.sh
./src/build/test/run_tests.sh
git diff --check
```

The Rust test supports the repository's split Rust package layout without
altering global toolchains. A standard complete Rust installation uses its
normal Cargo and C linker instead.
