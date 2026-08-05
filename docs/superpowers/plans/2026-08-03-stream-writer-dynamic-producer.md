# Dynamic Stream Writer Producer Implementation Plan

> **For agentic workers:** Execute this plan inline with focused red/green verification. Do not widen public `own<T>`, `borrow<T>`, or `ref<T>` syntax.

**Goal:** Add the bounded countdown `StreamWriter<u8>` producer described by the dynamic producer design.

**Architecture:** Extend `StreamWriterPlan` with a distinct countdown producer mode. Keep static producer sequences unchanged. Emit a dynamic writer pump that stores `i64 remaining` in the existing offset-52 slot, starts the registered sink before pumping, and uses the current callback/backpressure protocol.

**Tech Stack:** Zig compiler/WAT, pinned Component async ABI, wasm-tools, Rust/Wasmtime.

## Global Constraints

- Only the registered `do:stream-probe@0.1.0` sink descriptor is admitted.
- Root signature is exactly `(count u64) -> Result<nil, ProbeError>`.
- Element type is fixed `u8`, byte value is literal `65`, stream capacity is exactly `1`.
- The loop is one zero-pre-guarded countdown; each iteration has one write, one await, one discard, and one `@sub(..., 1)`.
- `count=0` is valid and yields an empty stream; negative/third-party shapes are rejected.
- No public ownership/reference syntax, general async calls, dynamic byte values, or arbitrary producer endpoints.

## Tasks

### Task 1: Red plan and source fixtures

**Files:** `src/build/codegen_component_async_plan.zig`, `src/build/test/check/399_stream_writer_dynamic_producer.do`.

- Add a plan test for the exact countdown source and assert dynamic mode, parameter name, byte value, and count source.
- Add a negative test for a dynamic byte parameter or missing zero pre-guard.
- Run `zig test src/build/codegen_component_async_plan.zig` and confirm the new positive test fails before implementation.

### Task 2: Dynamic plan parser

**Files:** `src/build/codegen_component_async_plan.zig`.

- Add `ProducerMode.countdown` and explicit count/byte metadata to the plan.
- Parse the root `(count u64)` signature, stream creation, countdown loop, literal write/await/discard, decrement, finalizer, sink, and return await.
- Preserve fixed sequence and helper paths unchanged; reject extra statements and unsupported dynamic forms.

### Task 3: Dynamic WAT and WIT

**Files:** `src/build/codegen_component_stream_writer.zig`, `src/build/codegen_emit_async.zig` only if metadata needs a named offset.

- Emit `$async-run-i64` and a parameterized `produce` root for countdown mode.
- Emit a dynamic pump using `i64.load/store` at offset 52, decrementing only after `writer-enqueue` returns admitted.
- Start the sink task before the first pump step and retain the existing terminal callback cleanup.
- Render `export produce: async func(count: u64) -> result<_, error-code>;`.

### Task 4: Component and runtime fixtures

**Files:** `examples/p3-runtime/stream-probe-guest-producer-dynamic.do`, descriptor/runtime shell scripts, and the existing Rust stream-writer host runner.

- Add Component assembly checks for the i64 export, dynamic pump, and no static producer data sequence.
- Add Rust/Wasmtime calls for counts `0`, `1`, and `3`, pending/ready/`Err(pipe)` modes, asserting ordered bytes, one callback, and one stream drop.

### Task 5: Documentation and complete verification

**Files:** blocker/roadmap/README/async design/changelog docs.

- Record this as a bounded dynamic producer checkpoint and retain general producer/resource boundaries.
- Run focused Zig tests, new Component/Rust gates, default regression, `RUN_WASM=1`, ReleaseSmall smoke, `zig fmt --check`, `bash -n`, and `git diff --check`.
