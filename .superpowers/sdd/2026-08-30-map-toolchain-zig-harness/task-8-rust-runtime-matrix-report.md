# Task 8 Step 3 Rust runtime matrix report

## Files changed

- `src/build/test/test_harness.zig`
  - Implemented `run_rust_runtime_matrix`.
  - Strengthened the existing structural matrix test to lock the declared case,
    runner, four modes, and non-empty marker sets.
- `.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-rust-runtime-matrix-report.md`
  - This report.

No other pre-existing dirty files were modified.

## Design

For each entry in `rust_runtime_cases`, the harness:

1. Builds the Do source and emits WAT/WIT through the existing compiler entry.
2. Compares generated WIT byte-for-byte with the declared snapshot.
3. Uses the current-only `do-toolchain` adapter for `parse-core`,
   `embed-component`, `new-component`, and `validate-component`.
4. Invokes the pinned Rust runner with `cargo run --quiet --locked`, the case
   Component, and each declared mode. The Rust runner remains responsible for
   Wasmtime runtime behavior.
5. Requires successful exit status and checks every marker declared for that
   mode. Temporary paths and every command result use the existing deferred
   cleanup/error-reporting helpers.

## Commands and results

- `cd src && zig test build/test/test_harness.zig`
  - PASS: 4/4 tests.
- Focused Component assembly through `bin/do-toolchain`, followed by
  `bash examples/p3-runtime/test_rust_async_call_component.sh <component>`
  - PASS: ready, pending, cancel-inline, and cancel-child; exact gate marker
    `rust-async-call-component gate passed`.
- `cd src && zig build test --summary all`
  - PASS: 10/10 build steps, 6/6 tests; integration harness completed all
    cases, including `rust async runner`.
- `git diff --check`
  - PASS.

The initial focused compile before implementation reproduced the expected
`undeclared identifier 'run_rust_runtime_matrix'` failure.

## Remaining concerns

The matrix currently covers only the Rust case declared by the existing
`rust_runtime_cases` table. Additional Rust shell gates remain outside this
scoped implementation and are not silently migrated here.
