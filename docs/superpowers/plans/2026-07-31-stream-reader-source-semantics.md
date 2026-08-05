# Stream Reader Source Semantics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the generic source-level reader operation `@next(Stream<T>) -> Future<Result<T, nil>>` with explicit async and affine validation.

**Architecture:** `@next` is a compiler special form, like `@cancel`, so it cannot collide with a user function or silently become a normal call. It borrows the current stream reader: creating or awaiting its Future does not transfer the reader. Result tag zero carries an item; the `Err(nil)` tag is EOF. A WIT completion future remains a separate future value and is outside this source-only increment.

**Tech Stack:** Zig parser/sema, Do check fixtures, existing Result and Future affine passes.

## Global Constraints

- Public spelling is exactly `@next(reader)` with one argument; do not repurpose `recv`.
- `Stream<T>` is the imported-WIT reader shell; existing `StreamReader<T>` remains an affine reader alias for internal producer/consumer APIs.
- `@next` requires the current reader owner inside an `async` body and produces `Future<Result<T, nil>>` with the same `T`.
- `@next` does not consume the reader. Only assigning a reader to a same-typed reader binding transfers it.
- Do not emit WAT, introduce a host import, add public ownership syntax, or remove `AsyncLoweringUnavailable` in this increment.
- Shared dirty worktree: do not reset, clean, stage, commit, or change unrelated files.

---

### Task 1: Parse And Reserve `@next`

**Files:**
- Modify: `src/build/parser.zig`
- Modify: `src/build/sema_tokens.zig`
- Modify: `src/build/sema_function_calls.zig`
- Create: `src/build/test/check/377_stream_next_reader.do`

**Interfaces:** Parser accepts `@next(reader)` only as an intrinsic call. Bare `next` remains a valid user declaration, local, and ordinary function value.

- [x] **Step 1: Write the positive check fixture**

```do
async consume(reader Stream<u8>) -> nil {
    pending Future<Result<u8, nil>> = @next(reader)
    item Result<u8, nil> = await(pending)
    if @is(item, Ok) {
        value u8 = item
        _ = value
    }
}

start() {}
```

- [x] **Step 2: Verify red**

Run: `./bin/do check src/build/test/check/377_stream_next_reader.do`

Expected: fail at `@next` with `UnsupportedExpr` until the name is registered as an intrinsic.

- [x] **Step 3: Add `next` to all intrinsic-name tables**

Add the exact string `"next"` to `is_builtin_call_name` in `parser.zig` and `sema_function_calls.zig`. Keep it out of `sema_tokens.is_builtin_special_or_core_name`, and make parser bare-name validation exclude `next`, so only the `@next(...)` spelling is intrinsic. Do not add a runtime core function.

- [x] **Step 4: Verify parser green**

Run: `cd src && zig test build/parser.zig && zig test build/sema_function_calls.zig && cd .. && ./bin/do check src/build/test/check/377_stream_next_reader.do`

Expected: parsing succeeds; semantic validation still fails until Task 2.

### Task 2: Validate Reader Ownership And Result Type

**Files:**
- Modify: `src/build/sema_async.zig`
- Modify: `src/build/sema_error.zig`
- Modify: `src/build/diag.zig`
- Create: `src/build/test/err/377_stream_next_outside_async.do`
- Create: `src/build/test/err/377_stream_next_outside_async.expect`
- Create: `src/build/test/err/378_stream_next_result_type_mismatch.do`
- Create: `src/build/test/err/378_stream_next_result_type_mismatch.expect`
- Create: `src/build/test/err/379_stream_next_transferred_reader.do`
- Create: `src/build/test/err/379_stream_next_transferred_reader.expect`

**Interfaces:** `check_await_context` reports `InvalidStreamReaderRead` for a malformed or non-async `@next`. `check_async_ownership` permits a next operation only when its typed `Future<Result<T,nil>>` target matches the current `Stream<T>`/`StreamReader<T>` owner.

- [x] **Step 1: Write the three failing diagnostics**

```do
consume(reader Stream<u8>) -> nil {
    pending Future<Result<u8, nil>> = @next(reader)
}
```

```do
async consume(reader Stream<u8>) -> nil {
    pending Future<Result<i32, nil>> = @next(reader)
    await(pending)
}
```

```do
async consume(reader Stream<u8>) -> nil {
    moved Stream<u8> = reader
    pending Future<Result<u8, nil>> = @next(reader)
    await(pending)
    _ = moved
}
```

- [x] **Step 2: Verify red**

Run: `./bin/do check src/build/test/err/377_stream_next_outside_async.do`

Expected: the source is accepted or reports a generic intrinsic error instead of `InvalidStreamReaderRead`.

- [x] **Step 3: Add a narrow `stream_next_binding` parser to `sema_async.zig`**

Accept only `name Future<Result<T,nil>> = @next(reader)`. Reuse the existing token-range comparison to require identical stream and Result item types. Include `Stream<T>` alongside `StreamReader<T>` in reader collection and transfer. Reject unknown, transferred, mismatched, malformed, or non-async readers with `InvalidStreamReaderRead`; keep `StreamReaderAlreadyConsumed` for a transferred source binding.

- [x] **Step 4: Verify green**

Run: `./bin/do check src/build/test/check/377_stream_next_reader.do && ! ./bin/do check src/build/test/err/377_stream_next_outside_async.do && ! ./bin/do check src/build/test/err/378_stream_next_result_type_mismatch.do && ! ./bin/do check src/build/test/err/379_stream_next_transferred_reader.do`

Expected: the positive check passes. The three diagnostics contain, respectively, `InvalidStreamReaderRead`, `InvalidStreamReaderRead`, and `StreamReaderAlreadyConsumed`.

### Task 3: Document The Source Boundary And Run Regression

**Files:**
- Modify: `doc/async-design.md`
- Modify: `doc/spec_rules.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `docs/superpowers/plans/2026-07-31-stream-reader-source-semantics.md`

**Interfaces:** Documentation states `@next` precisely, records the verified descriptor-owned `Stream<u8>` Component/Rust slice, and keeps generic WIT stream lowering, completion-future variants, backpressure, and producer execution explicitly bounded.

- [x] **Step 1: Add the source contract**

Document this exact form:

```do
pending Future<Result<u8, nil>> = @next(reader)
item Result<u8, nil> = await(pending)
if @is(item, Ok) { byte u8 = item } // Err(nil) is EOF
```

State that `reader` remains its caller-owned affine handle and Scope cleanup releases it.

- [x] **Step 2: Mark the source-semantic blocker resolved**

Replace the missing-endpoint portion of `Stream Endpoint Surface` with the admitted `@next` contract, and retain the P3 canonical/Rust fixture as the remaining unblock condition.

- [x] **Step 3: Run final verification**

Run: `cd src && zig test build/parser.zig && zig test build/sema_async.zig && zig test build/sema_function_calls.zig && cd .. && ./src/build/test/run_tests.sh && git diff --check`

Expected: all commands exit zero; ordinary `do build` still rejects an async program with `AsyncLoweringUnavailable`.

### Task 4: Verify A Descriptor-Owned Stream Reader

**Files:**
- Modify: `src/build/sema_imports.zig`
- Modify: `examples/p3-runtime/stream-probe-component.do`
- Create: `src/build/test/check/385_p3_async_stream_reader_descriptor.do`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/stream_probe.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/test_rust_stream_reader_descriptor.sh`

**Interfaces:** A custom registry descriptor must provide the explicit canonical
module/import metadata. Its source signature is `() ->
Tuple<Stream<u8>, Future<Result<nil, ErrorType>>>`; the bounded reader fixture
consumes two items, observes `Err(nil)` EOF, and drops the unread completion
future exactly once.

- [x] Add and verify the red custom-descriptor signature check.
- [x] Accept only the bounded reader signature in sema; preserve unknown and
  malformed descriptor rejection.
- [x] Verify custom WAT/WIT assembly and Component validation.
- [x] Execute the assembled Component with a Rust/Wasmtime host and assert
  item/item/EOF, no completion poll, and exactly-once stream/future disposal.

## Plan Self-Review

- Task 1 owns parsing and reserved-name behavior.
- Task 2 owns semantic type, context, and affine reader behavior.
- Task 3 records only the verified source contract and does not overclaim Component runtime support.
