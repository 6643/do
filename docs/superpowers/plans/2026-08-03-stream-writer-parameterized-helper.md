# Parameterized Stream-Writer Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admit one descriptor-specific async helper with `(StreamWriter<u8>, u64, u8)` parameters while preserving the existing parameterized producer pump and all general async-call rejection boundaries.

**Architecture:** Extend `codegen_component_async_plan.zig` source-shape recognition to validate a root `produce(count, value)` that transfers its writer and both direct parameters to one private helper. Reuse the existing `StreamWriterPlan` countdown metadata and `(i64, i32)` emitter, so generated Component output remains one root export with the existing frame offsets and cleanup protocol. Add a private Component/Rust/Wasmtime fixture and update only the G6.2 bounded-producer documentation.

**Tech Stack:** Zig compiler/WAT, pinned `wasm-tools 1.254.0`, Rust/Wasmtime `47.0.2`, existing `src/build/test/run_tests.sh` harness.

> **Status:** Complete. Focused Component/Rust gates, default and WASM regressions,
> ReleaseSmall smoke, formatting, shell syntax, and diff checks passed on
> 2026-08-03. The unsupported general async/resource boundaries remain in force.

## Global Constraints

- The only accepted helper signature is `async helper(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError>`.
- The root is exactly `async produce(count u64, value u8) -> Result<nil, ProbeError>` and creates one capacity-one stream.
- The helper contains one zero-pre-guarded countdown, writes the direct `value` parameter, awaits each write, decrements after admission, uses `defer close(writer)`, calls only the registered `do:stream-probe@0.1.0/sink.write-via-stream`, and awaits that result.
- The compiler emits only the root Component export and reuses frame offsets `52` (`i64 remaining`) and `60` (`i32 value`); it does not lower a general async call.
- Public `own<T>`, `borrow<T>`, `ref<T>`, pointers, arbitrary producer expressions, additional helper hops, borrowed/nested/variant resource fields, and arbitrary filesystem async methods remain rejected.
- Preserve all unrelated dirty-worktree changes; do not reset, clean, or overwrite them.

---

### Task 1: Red Source-Shape And Plan Tests

**Files:**
- Create: `examples/p3-runtime/stream-probe-guest-producer-parameterized-helper.do`
- Create: `src/build/test/check/400_stream_writer_parameterized_helper.do`
- Modify: `src/build/codegen_component_async_plan.zig` (tests near the existing parameterized/helper tests)

**Interfaces:**
- Consumes: existing `StreamWriterPlan.analyze`, `ProducerMode.countdown`, and the parameterized root source fixture.
- Produces: a fixture whose helper body is the only dynamic producer source, plus tests that require `plan.producer_helper_name == "finish_stream"` and reject malformed helper signatures.

- [x] **Step 1: Add the accepted helper fixture and check source.**

Use this exact shape in both files, with the check file ending in `start() {}`:

```do
sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
ProbeError error = Io | IllegalByteSequence | Pipe
StreamError error = StreamClosed | StreamWriteFailed

async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
    remaining u64 = count
    loop {
        if @eq(remaining, 0) { break }
        pending Future<Result<nil, StreamError>> = writer(value)
        result Result<nil, StreamError> = await(pending)
        _ = result
        remaining = @sub(remaining, 1)
    }
    defer close(writer)
    pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return await(pending)
}

async produce(count u64, value u8) -> Result<nil, ProbeError> {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
    return await(pending)
}
```

- [x] **Step 2: Add the failing plan assertion.**

Add a Zig test that tokenizes the fixture source, calls `StreamWriterPlan.analyze`, and asserts:

```zig
try std.testing.expectEqual(ProducerMode.countdown, plan.producer_mode);
try std.testing.expectEqualStrings("finish_stream", plan.producer_helper_name.?);
try std.testing.expectEqualStrings("count", plan.producer_count_name.?);
try std.testing.expectEqualStrings("value", plan.producer_value_name.?);
```

Add a second source string with helper parameters ordered `(count u64, writer StreamWriter<u8>, value u8)` and assert `error.UnsupportedP3StreamWriterComponent`.

- [x] **Step 3: Run the red test.**

Run:

```bash
cd src && zig test build/codegen_component_async_plan.zig --test-filter 'parameterized producer'
```

Expected: the new accepted-shape test fails because the current helper matcher only accepts one `StreamWriter<u8>` parameter.

### Task 2: Validate And Record The Parameterized Helper Shape

**Files:**
- Modify: `src/build/codegen_component_async_plan.zig`

**Interfaces:**
- Consumes: Task 1's root/helper source tokens.
- Produces: `StreamWriterPlan` metadata with `producer_mode == .countdown`, root count/value names, and `producer_helper_name` for the accepted helper; malformed helper shapes continue to return `UnsupportedP3StreamWriterComponent`.

- [x] **Step 1: Add a three-parameter helper descriptor.**

Extend the helper shape record with `count_name` and `value_name` and add a matcher that accepts only:

```text
async <name>(<writer> StreamWriter<u8>, <count> u64, <value> u8)
    -> Result<nil, <error>> { ... }
```

The matcher must verify the exact result range and body boundaries using the existing `find_matching` helpers.

- [x] **Step 2: Parse the root transfer call.**

In `find_guest_producer_function`'s countdown branch, retain the existing direct-root dynamic path first. If it does not match, parse exactly:

```text
pending Future<Result<nil, ProbeError>> = <helper>(writer, count, value)
return await(pending)
```

Require the call arguments to be the root's writer, count, and value names in that order. Resolve the helper by name, validate its three-parameter shape, and pass its body through the same countdown parser with the helper's parameter names. Return the same `DynamicGuestProducer` facts plus `helper_name`.

- [x] **Step 3: Reject unsupported helper calls early.**

Return `null` for a literal argument, renamed/crossed argument, second helper call, helper-created stream, literal writer value, missing root await, missing `defer close(writer)`, or a helper result type different from the root result. Keep the existing fixed-sequence and one-hop forwarding paths unchanged.

- [x] **Step 4: Run focused plan tests.**

Run:

```bash
cd src && zig test build/codegen_component_async_plan.zig --test-filter 'parameterized producer'
```

Expected: all new accepted/rejected tests pass, and existing dynamic/fixed/helper tests remain green.

### Task 3: Reuse The Existing `(i64, i32)` Component Lowering

**Files:**
- Modify: `src/build/codegen_component_stream_writer.zig` only if a helper marker or assertion is missing.
- Modify: `src/build/codegen_emit_async.zig` only if the existing named frame offsets are not emitted for the helper plan.

**Interfaces:**
- Consumes: Task 2's countdown `StreamWriterPlan`.
- Produces: one root `[async-lift]produce` export of type `$async-run-i64-i32`, offset-52/offset-60 initialization, helper lease marker, and no helper export.

- [x] **Step 1: Add emitter assertions before changing emitter code.**

Extend the Component emitter test to compile Task 1's source and assert:

```text
[writer-endpoint-mode] guest-producer
[writer-lease-transfer] async-helper
[writer-producer-index-offset] 52
[writer-producer-value-offset] 60
(type $async-run-i64-i32 (func (param i64 i32) (result i32)))
(func (export "[async-lift]produce") (type $async-run-i64-i32)
```

Also assert the helper name does not appear as an exported async lift.

- [x] **Step 2: Run the emitter test and inspect the failure.**

Run:

```bash
cd src && zig test build/codegen_component_stream_writer.zig --test-filter 'parameterized helper'
```

Expected: the plan currently rejects the source, so the test fails before WAT changes.

- [x] **Step 3: Implement only missing metadata rendering.**

Reuse the existing countdown value pump and callback cleanup. If the test shows no missing emitter behavior after Task 2, do not add new lowering branches; the helper is intentionally folded into the root plan.

- [x] **Step 4: Run focused emitter tests.**

Run:

```bash
cd src && zig test build/codegen_component_stream_writer.zig --test-filter 'parameterized helper'
cd src && zig test build/codegen_emit_async.zig --test-filter 'stream writer'
```

Expected: both pass with the same frame offsets and exactly-once terminal cleanup as the root parameterized producer.

### Task 4: Component And Rust/Wasmtime Runtime Gates

**Files:**
- Create: `examples/p3-runtime/wit/stream-probe-guest-producer-parameterized-helper.wit`
- Create: `examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_helper.sh`
- Create: `examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_helper.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/stream_probe_guest_producer_dynamic.rs`

**Interfaces:**
- Consumes: Task 1 source, the existing `stream-writer-probe` sidecar shape, and the existing dynamic producer runner.
- Produces: a Component-validating and Wasmtime-executing parameterized helper gate using the existing `produce(count, value)` WIT export.

- [x] **Step 1: Add the matching WIT sidecar.**

Copy the existing parameterized sidecar exactly; its world remains `stream-writer-probe` and its export remains:

```wit
produce: async func(count: u64, value: u8) -> result<_, error-code>;
```

- [x] **Step 2: Add the Component lowering script.**

Build Task 1's fixture with `--p3-async-component --p3-wit-output`, compare the sidecar, assert the helper-transfer marker, both frame offsets, the single root export, and the absence of a helper export, then run `wasm-tools parse`, `component embed`, `component new`, and `wasm-tools validate --features cm-async,cm-more-async-builtins`.

- [x] **Step 3: Extend the runner with a helper mode.**

Accept a third argument `parameterized-helper`; use the same typed `(u64, u8)` call and expected value `90` as `parameterized`, but include `producer=parameterized-helper` in the success line. Keep `parameterized` and count-only modes unchanged.

- [x] **Step 4: Add the Rust/Wasmtime script and run it.**

For `pending`, `ready`, and `error`, invoke the runner with `parameterized-helper`. Require counts `0/1/3`, value `90`, ordered output, one host callback, one stream drop, and the existing pending-poll expectations.

### Task 5: Documentation And Full Verification

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-08-03-stream-writer-parameterized-helper-design.md`

**Interfaces:**
- Consumes: successful focused gates from Tasks 1–4.
- Produces: synchronized evidence that parameterized helper transfer is verified, while general async calls, additional hops, borrowed resources, and arbitrary producer expressions remain pending.

- [x] **Step 1: Record the bounded checkpoint.**

Add the exact fixture/script names, `count=0/1/3`, `value=90`, pending/ready/`Err(pipe)`, one callback, and one drop to the recent G6.2 evidence. Do not mark the general producer/resource blocker closed.

- [x] **Step 2: Run the focused matrix.**

Run:

```bash
cd src && zig test build/codegen_component_async_plan.zig --test-filter 'parameterized producer'
cd src && zig test build/codegen_component_stream_writer.zig --test-filter 'parameterized helper'
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_helper.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_helper.sh
```

- [x] **Step 3: Run repository release gates.**

Run:

```bash
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
bash src/build/test/run_release_smoke.sh
zig fmt --check src/build/codegen_component_async_plan.zig src/build/codegen_component_stream_writer.zig src/build/codegen_emit_async.zig
rustfmt --check --edition 2024 examples/p3-runtime/rust-host-runner/src/bin/stream_probe_guest_producer_dynamic.rs
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_helper.sh examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_helper.sh
git diff --check
```

- [x] **Step 4: Update the plan status only from evidence.**

Mark this plan and the design's status complete only after every focused and release gate passes. Record any skipped checks and preserve the remaining G6.2 boundaries.
