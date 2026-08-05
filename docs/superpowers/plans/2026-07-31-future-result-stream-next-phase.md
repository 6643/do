# Future Result and Stream Runtime Next Phase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the verified Component async subset from fixed unit/resource probes to one descriptor-driven `Future<Result<T, E>>` payload model and a bounded Stream reader/writer lifecycle, while keeping unsupported shapes explicitly rejected.

**Architecture:** The manifest is the single source of truth for canonical result words, completion parameters, stream operations, and ownership hooks. The shared async plan converts those facts into frame slots and ordered operations; emitters consume the plan and never infer ABI layout from source type spelling. Stream reader, writer, EOF, cancellation, and cleanup are modeled as explicit state transitions, with no rollback claim for external effects.

**Tech Stack:** Zig compiler, existing lexer/parser/sema passes, `p3_async_manifest.Registry`, Wasm GC async frames, WAT/Component assembly, Rust/Wasmtime fixtures.

## Global Constraints

- Keep public `ref<T>`, `own<T>`, `borrow<T>`, pointers, and references unsupported; ownership remains an internal ABI/sema property.
- Keep ordinary `do build` returning `AsyncLoweringUnavailable` until general resumable lowering is complete.
- Accept only descriptor-registered canonical shapes. Do not infer HTTP, arbitrary resources, lists, strings, nested variants, or payload-bearing `error-code` from a private probe.
- `@cancel` waits for the ABI terminal state and does not undo external side effects.
- Use red tests before implementation and finish with `./src/build/test/run_tests.sh`, `zig fmt --check`, and `git diff --check`.

---

### Task 1: Canonical Result Payload Model

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/codegen_component_async_plan.zig`
- Test: `src/build/p3_async_manifest.zig`
- Test: `src/build/codegen_component_async_plan.zig`
- Create: `src/build/test/compile_err/382_result_payload_lowering_unavailable.do`
- Create: `src/build/test/compile_err/382_result_payload_lowering_unavailable.expect`

**Interfaces:**
- Add a manifest-owned result payload description containing the tag word, optional Ok/Err payload words, and the completion/result-area ownership rule.
- Make `LoweringShape.unit_result_tag` and `LoweringShape.resource_result_2word` use that description; preserve their current ABI output.
- Admit only one-word scalar payload arms plus `nil` in the new generic shape. Reject lists, text, managed values, nested variants, resources outside the registered probe, and payload-bearing `error-code` with `UnsupportedP3AsyncComponent`.

- [x] **Step 1: Write the failing registry and plan tests.**

```zig
const shape = p3_async_manifest.lowering_shape(scalar_result_descriptor) orelse return error.TestUnexpectedResult;
try std.testing.expectEqual(p3_async_manifest.LoweringShape.scalar_result, shape);
try std.testing.expectEqual(@as(usize, 2), descriptor.canonical.completion_params.len);
try std.testing.expectEqual(@as(usize, 1), shape.scalar_result.ok.len);
```

- [x] **Step 2: Run the focused tests to confirm the missing shape.**

Run: `cd src && zig test build/p3_async_manifest.zig && zig test build/codegen_component_async_plan.zig`

Expected: the new test fails because no canonical scalar Result shape exists; all existing tests remain green.

- [x] **Step 3: Implement manifest validation and shared-plan payload slots.**

Parse the explicit canonical arrays, verify tag/payload arity and scalar storage classes, and create frame slots from the descriptor rather than from `Result<T,E>` spelling. Keep the existing unit and private resource descriptors byte-for-byte compatible.

- [x] **Step 4: Verify the boundary.**

Run: `cd src && zig test build/p3_async_manifest.zig && zig test build/codegen_component_async_plan.zig && cd .. && ./bin/do build src/build/test/compile_err/382_result_payload_lowering_unavailable.do -o /tmp/382.wat`

Expected: registered scalar Result shapes pass plan tests; ordinary build still fails with `AsyncLoweringUnavailable`, while component lowering is admitted only for the registered scalar probe.

### Task 2: Result Payload Resume and Narrowing

**Files:**
- Modify: `src/build/codegen_p3_wait_for.zig`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/codegen_component_resource_async.zig`
- Test: `src/build/codegen_p3_wait_for.zig`
- Test: `examples/p3-runtime/`

**Interfaces:**
- Consume the payload slots from Task 1 and emit one resume state per operation.
- Preserve generic `@is(value, Ok)` / `@is(value, Err)` narrowing; a true branch reads only its registered payload slot.
- Release or transfer payload resources exactly once on terminal completion and cancellation.

- [x] **Step 1: Add a red WAT test for a scalar Result completion.**

Assert the generated frame contains a tag plus the declared payload slot, the resume path loads those slots, and `task.return` receives the registered canonical words.

- [x] **Step 2: Run the focused emitter test and verify the current unsupported result.**

Run: `cd src && zig test build/codegen_p3_wait_for.zig --test-filter 'scalar Result payload'`

Expected: fail before the emitter consumes the new plan shape.

- [x] **Step 3: Implement payload-aware resume and cleanup.**

Store completion words into the GC frame, dispatch on the tag, bind the selected payload, and route both `await` and `@cancel` through one terminal cleanup sequence. Do not reissue a completed host operation after resume.

- [x] **Step 4: Verify Component execution.**

Run: `cd src && zig test build/codegen_p3_wait_for.zig && zig test build/codegen_component_async.zig && cd .. && bash examples/p3-runtime/test_cli_result_probe.sh && bash examples/p3-runtime/test_do_cli_result_lowering.sh && bash examples/p3-runtime/test_rust_cli_result.sh`

Expected: existing `Result<nil,nil>` and private resource probes remain green; the new registered scalar Result fixture completes through Rust/Wasmtime; HTTP payload-bearing errors remain rejected.

**Immediate completion checkpoint (2026-08-01):** The selected single-operation
wrappers now distinguish a bare `Status::Returned == 2` from a started subtask
before calling `waitable-join`. Pending and immediately-ready Rust/Wasmtime
executions pass for clocks, CLI unit Result, scalar Result, private resource
Result, and cancellation. The scalar Result cancellation companion now runs
through Rust/Wasmtime with a `nil` root export, one committed host effect, one
host-future drop, and no rollback; a non-`nil` root result is rejected. This
does not extend the multi-await state machines or the rejected HTTP/arbitrary-
payload shapes.

**Narrow/unsigned scalar checkpoint (2026-08-01):** source-to-canonical
mapping and descriptor-driven WIT result rendering are covered for `u8`, but
the shape is not registered for runtime lowering. With the pinned
`wasm-tools 1.254.0` / Wasmtime `47.0.2` toolchain, a `result<u8,u8>` task
return traps with `TaskReturnInvalid` after the Rust host returns a valid
payload; the equivalent `result<s32,s32>` probe passes. The exact evidence and
unblock condition are recorded in `doc/host_abi_blockers.md`. Do not claim
narrow/unsigned runtime support until that probe passes.

### Task 3: General Stream Reader State Machine

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/codegen_component_cli_stream_stdin.zig`
- Modify: `src/build/codegen_component_async_plan.zig`
- Modify: `src/build/codegen_async_model.zig`
- Create: `src/build/test/compile_err/383_stream_shape_unavailable.do`
- Create: `src/build/test/compile_err/383_stream_shape_unavailable.expect`
- Test: `examples/p3-runtime/test_do_cli_stream_stdin_lowering.sh`
- Test: `examples/p3-runtime/test_rust_cli_stream_stdin.sh`

**Interfaces:**
- Keep the source contract `pending Future<Result<T, nil>> = @next(reader)` and the separate completion `Future<Result<nil, E>>`.
- Generate reader operation state from the registry: acquire, next/read, pending, ready, EOF, cancel-read, drop-readable, and future-drop.
- Start with registered scalar `u8` and one bounded capacity; reject arbitrary element layouts until their canonical ABI is registered.

- [x] **Step 1: Add red tests for a second read count and lifecycle states.**

Assert that the plan has distinct states for pending read, ready item, EOF, cancel, and terminal drop, and that a transferred reader cannot be read again.

- [x] **Step 2: Verify the current pinned-only behavior.**

Run: `cd src && zig test build/codegen_component_async_plan.zig && cd .. && bash examples/p3-runtime/test_do_cli_stream_stdin_lowering.sh`

Expected: the new generic plan case is rejected while the existing pinned CLI fixture passes.

- [x] **Step 3: Implement descriptor-driven reader emission.**

Replace fixed read-count branches with plan operations and frame slots. Preserve `Err(nil)` as EOF, make cancellation idempotent, and ensure completion futures are not cancelled after they are already ready.

- [x] **Step 4: Verify reader execution and ownership.**

Run: `cd src && zig test build/codegen_component_cli_stream_stdin.zig && cd .. && bash examples/p3-runtime/test_do_cli_stream_stdin_lowering.sh && bash examples/p3-runtime/test_rust_cli_stream_stdin.sh && ./src/build/test/run_tests.sh`

Expected: two items plus EOF are observed, reader and completion future each drop once, and ordinary async build rejection is unchanged.

### Task 4: Stream Writer Lease, FIFO, and Backpressure

**Files:**
- Modify: `src/build/sema_async.zig`
- Modify: `src/build/codegen_emit_async.zig`
- Create: `src/build/codegen_component_stream_writer.zig`
- Create: `src/build/test/check/384_stream_writer_runtime.do`
- Create: `src/build/test/err/384_stream_writer_backpressure_unfinalized.do`
- Create: `src/build/test/err/384_stream_writer_backpressure_unfinalized.expect`
- Create: `examples/p3-runtime/test_rust_stream_writer.sh`

**Interfaces:**
- `StreamWriter<T>` remains an affine producer lease; `close(writer)` and `abort(writer, err)` are the only terminal operations.
- The runtime queue has an explicit bounded capacity, FIFO order, producer wait state, consumer wake state, and terminal error/EOF state.
- A writer transfer moves the lease; exactly one owner finalizes or aborts it, including through `defer`.

**Current checkpoint:** `codegen_component_stream_writer.zig` provides a
bounded internal FIFO/lease model with executable tests for backpressure, FIFO,
pending-write promotion, transfer, close, abort, and wake flags. Pinned
`wasi:cli/stdout.write-via-stream` WIT generates the async canonical import set
with `wasm-tools 1.254.0` / `wasmtime 47.0.2`; the descriptor, A-route
forwarding wrapper, and Rust fixture are registered/emitted and pass pending,
immediate, and `Err(pipe)` host callback execution. The completion frame now
uses the compact canonical Result layout: one-byte tag at offset 0 and one-byte
error enum payload at offset 1, both zero-extended for `task-return`. The
fixed `guest-producer` endpoint is now implemented for the registered `u8`
shape: it creates a capacity-one guest stream, writes three values, and runs
through Rust/Wasmtime for normal, consumer-early-drop, and host-error paths.
Its producer writes may use bounded source-level `u8` bindings (`name u8 =
literal` followed by `writer(name)`), which are captured into the same fixed
producer data segment.
The internal `StreamWriterQueuePump` model now makes the bounded source-sequence
rule executable: a value retained in pending advances exactly once, capacity-zero
rendezvous waits for its consumer, and close is rejected until pending data is
drained. The fixed guest-producer emitter now routes its entry and callback through
one `$writer-pump-step` helper; the runtime matrix records FIFO `[65, 66, 67]`, one
pending write, one host callback, and exactly-once close/drop. Arbitrary source-level
Component codegen remains outside this boundary.
The WIT sidecar renderer now consumes the analyzed descriptor directly; a
private registered `do:stream-probe@0.1.0` writer descriptor is covered by a
unit test and `test_do_stream_writer_descriptor.sh` assembly probe so the
renderer cannot silently fall back to the stdout package.
General queue-to-stream lowering, arbitrary producer payloads, and an
externally writable endpoint remain the deferred B route; the pinned
forwarding/FIFO and fixed guest-producer behavior are the A release scope.

- [x] **Step 1: Add red source and runtime fixtures.**

Cover a full queue that must suspend the producer, FIFO item order, close wake-up, abort propagation, transfer, and double-finalization rejection.

- [x] **Step 2: Verify the source-only guard.**

Run: `./bin/do check src/build/test/check/384_stream_writer_runtime.do && ! ./bin/do build src/build/test/check/384_stream_writer_runtime.do -o /tmp/384.wat`

Expected: source sema passes, while normal build remains `AsyncLoweringUnavailable`.

- [x] **Step 3a: Implement the internal queue and lease state.**

The queue stores backpressured writes in a fixed pending FIFO, promotes them
only after a buffer slot is consumed, models capacity-zero rendezvous, and
drops unaccepted pending writes on close/abort while preserving accepted FIFO
items.

- [x] **Step 3b: Register the pinned stdout writer descriptor.**

`wasi:cli/stdout@0.3.0-rc-2025-09-16` is now registered with an explicit
`stream` canonical object containing all eight operation names and core
signatures. `test_cli_stream_stdout_abi_surface.sh` verifies the WIT hash,
`wasm-tools` output, and the generated imports. No operation name is inferred
from the WIT member.

- [x] **Step 3c: Implement the Component writer plan and codegen for the A forwarding scope.**

Use explicit frame fields for queue index/count/capacity, pending producer, terminal state, and error payload. Connect writer cleanup to the existing async ownership pass; never copy a writer lease.

The current implementation emits a fixed-capacity `u8` writer frame and
descriptor-driven `writer-enqueue`/`writer-promote` helpers that call the
registered `stream-write` operation and record backpressure. The completion
path reads the registered frame-layout metadata's compact Result area as byte
tag/payload values before `task-return`; the generated WAT carries explicit
offset markers and is covered by the pending, immediate, and error fixtures.
The pinned forwarding path still passes its exported reader endpoint directly
to the host callback; that path does not create a writable endpoint or pump
source items into the FIFO. The separate fixed guest-producer path does create
an internal writable endpoint and pumps three registered `u8` values, but it is
not yet a generic source-level write operation. A direct writable-side drop on
the forwarding reader handle is rejected by Wasmtime, so externally writable
cleanup and generic producer error mapping remain pending.

The HTTP async host-import gate now has the same narrow boundary: the exact
pinned `wasi:http/client.send` declaration is checked for its registered source
signature and deferred to `HttpServicePlan`; arbitrary descriptors still need a
non-null lowering shape. This restores the intended `do check`, resource
ownership, and ordinary-build diagnostics without admitting general HTTP
lowering.
The pinned HTTP resource graph is also checked before the plan is selected:
`fields`/headers, `request-options`, `request`, `response`, `request.new`, both
`consume-body` operations, and the `client.send` world signature must match the
vendored WIT snapshot. This is a shape boundary only; body/trailer execution and
general `client.send` lowering remain deferred.

- [x] **Step 4: Verify Rust/Wasmtime behavior for the A forwarding scope.**

The external ABI evidence, explicit stdout descriptor, frame helpers, and both
forwarding and fixed guest-producer fixtures are verified. The two Rust scripts
exercise pending/immediate callbacks, host `Err(pipe)`, normal three-item output,
and consumer early-drop, while the Zig model covers close/abort/backpressure
and exactly-once lease finalization. Generic producer-endpoint execution,
arbitrary payloads, and external writable-side close/abort remain deferred. The
current `doc/wit/wasi_registry.json` entries for
`output-stream.check-write`, `output-stream.write`, and `output-stream.flush`
remain synchronous and are not reused for the async writer descriptor.

Run: `cd src && zig test build/sema_async.zig && zig test build/codegen_component_stream_writer.zig && cd .. && bash examples/p3-runtime/test_rust_stream_writer.sh`

Expected: FIFO and bounded backpressure pass; close and abort wake the correct waiter; each lease is finalized once. A-route execution additionally returns both `Ok(())` and `Err(pipe)` through the compact Result frame.

### Task 5: Cancellation, Documentation, and Release Gate

**Files:**
- Modify: `doc/async-design.md`
- Modify: `doc/spec_rules.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `examples/p3-runtime/README.md`
- Modify: `docs/superpowers/plans/2026-07-31-component-async-function-plan.md`

**Interfaces:**
- Document the accepted canonical shapes and the exact rejection boundary.
- State that cancellation waits for terminal ABI completion and does not roll back database/network/external side effects.
- Keep real `wasi:http/client.send`, arbitrary WIT stream payloads, nested variants, generic resources, and full WASI out of the release gate until their own pinned execution matrices pass.

**Current release checkpoint (2026-08-01):** the former lowercase-WIT
`result<...>` fixtures use Do `Result<...>`, the pinned HTTP async host-import
gate is covered, and the full regression is green: `pass=1035 fail=0 skip=3`.
The writer integration is still bounded: the verified A paths include one
internal fixed guest-producer endpoint, but do not yet provide a generic
source-level queue-to-stream pump or an externally writable endpoint.

- [x] **Step 1: Add cancellation and ownership matrix fixtures.**

Cover pending Result, ready Result, pending reader, ready reader, EOF, writer
close, writer abort, and cancellation after an external side effect. The
Result cancellation fixture now asserts one committed effect, one host-future
drop, and zero rollback; lifecycle unit tests cover the writer close/abort
states. Generic externally writable-endpoint execution remains deferred to the
B route; the fixed internal guest-producer execution is covered by
`test_rust_guest_stream_writer.sh`.

- [x] **Step 2: Update blocker and plan status documents.**

Record exact commands, tool versions, accepted descriptors, and the remaining unblock condition for payload-bearing nested variants.

- [x] **Step 3: Run the full release gate.**

Run: `cd src && zig fmt --check build && zig test build/p3_async_manifest.zig && zig test build/codegen_component_async_plan.zig && zig test build/codegen_p3_wait_for.zig && zig test build/codegen_component_async.zig && cd .. && ./src/build/test/run_tests.sh && git diff --check`

Result: all focused tests pass, `./src/build/test/run_tests.sh` reports
`pass=1035 fail=0 skip=3`, and no unsupported async shape is silently lowered.

## Phase Exit Criteria

- `Future<Result<T,E>>` payload layout is descriptor-driven, tested, and limited to registered scalar/unit/resource shapes.
- Reader lifecycle and writer lease semantics have executable FIFO/backpressure/EOF/abort coverage.
- Cancellation and cleanup are observable in Rust/Wasmtime fixtures, without rollback claims.
- Ordinary `do build` still rejects async programs outside the verified Component target.
- HTTP and complete WASI remain separate future phases, not implied by these probes.
