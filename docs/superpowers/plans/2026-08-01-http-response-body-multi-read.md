# HTTP Response Body Multi-Read Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the pinned `response.consume-body` probe from one bounded `@next` operation to a linear sequence of up to three successful `stream<u8>` reads, with an optional explicit trailers-future read/discard path and exactly-once cleanup.

**Architecture:** Reuse the existing `StreamU8AcquirePlan` read-sequence contract and the CLI stdin reader's frame index state machine. `HttpResponseBodyPlan` records the number of linear reads and whether the source explicitly awaits trailers; the WAT frame stores the current read index, invokes the registered stream read once per state transition, and finishes after the final `Ok(u8)` result or terminal `Err(nil)` EOF. An awaited trailers future uses the pinned `future.read-2` operation and discards the result payload; the body host supplies one byte per read, returns `Completed` for items and `Dropped` for EOF.

**Tech Stack:** Zig compiler, Core Wasm WAT, pinned WASI HTTP async manifest, `wasm-tools`, Rust/Wasmtime 47.0.2.

## Global Constraints

- Admit only the pinned `wasi:http/types@0.3.0-rc-2025-09-16` `response.consume-body` descriptor.
- Accept only a linear sequence of `@next(reader)` -> `await` -> discard operations followed by either `@cancel(completion)` or one `await(completion)` -> discard.
- Bound the sequence by `component_async_plan.max_stream_u8_reads` (currently three); reject zero reads, control flow, EOF branching, and dynamic iteration.
- Keep `own<T>`, `borrow<T>`, references, copied HTTP records, and general `client.send` construction outside this slice.
- Preserve ordinary `do build` async rejection and the no-rollback cancellation contract.
- Use red -> focused green -> component/runtime green -> full regression.

### Task 1: Lock The Multi-Read Source Contract

**Files:**
- Create: `examples/p3-runtime/http-response-consume-body-two-read.do`
- Modify: `src/build/codegen_component_wasi_http.zig`
- Test: `src/build/codegen_component_wasi_http.zig`

**Interfaces:**
- Consumes: the existing pinned consume-body declaration and `StreamU8AcquirePlan` token sequence.
- Produces: `HttpResponseBodyPlan.read_count == 2` and a rejected fourth read beyond the registered bound.

- [x] **Step 1: Add the red fixture and unit assertion.**

Use this exact linear body after the existing tuple/reader/completion bindings:

```do
pending Future<Result<u8, nil>> = @next(reader)
first Result<u8, nil> = await(pending)
_ = first
pending_2 Future<Result<u8, nil>> = @next(reader)
second Result<u8, nil> = await(pending_2)
_ = second
@cancel(completion)
```

Assert the current analyzer rejects or reports `read_count != 2` before the implementation change.

- [x] **Step 2: Verify red.**

Run:

```bash
cd src && zig test build/codegen_component_wasi_http.zig --test-filter 'HTTP response body plan accepts two stream reads'
```

Expected: the test fails because the current HTTP matcher admits exactly one read.

- [x] **Step 3: Generalize the matcher.**

Use the same bounded loop already used by `StreamU8AcquirePlan`: parse pending/await/discard triples into a fixed read count, require at least one read, then require `@cancel(completion)` at the body end. Keep the existing one-read fixture green and reject a fourth triple.

- [x] **Step 4: Verify the plan.**

Run the focused test and `zig test build/codegen_component_wasi_http.zig`; assert the one-read and two-read plans both select the HTTP body emitter.

### Task 2: Add The Frame Read Index And Resume Transition

**Files:**
- Modify: `src/build/codegen_component_wasi_http.zig`
- Test: `src/build/codegen_component_wasi_http.zig`

**Interfaces:**
- Consumes: `HttpResponseBodyPlan.read_count`.
- Produces: WAT markers `[stream-read-count]`, `[stream-read-index-offset]`, and a callback path that starts the next read before terminal cleanup.

- [x] **Step 1: Add red WAT assertions.**

For the two-read fixture, require a frame read-index field, an increment after code `16` (`Ok`), a second `call $start-read`, and a terminal path that calls `$cleanup` only after index `2`.

- [x] **Step 2: Implement the bounded state machine.**

Add a frame slot at offset `20` for the read index. Initialize it to zero. In `$accept-read`, require code `16` for non-final reads, increment the index, finish when it equals `read_count`, otherwise call `$start-read`; retain the existing pending `waitable-join` path and event-4 cleanup path.

- [x] **Step 3: Keep cleanup ownership unchanged.**

Drop the readable stream and trailer future exactly once, drop the waitable set, clear context, free the frame, and call the existing nil task-return import. Do not inspect or synthesize trailer payloads in this slice.

- [x] **Step 4: Verify WAT and assembly.**

Run focused Zig tests, rebuild `bin/do`, and run `wasm-tools parse`, component embed/new, and validate on the two-read fixture.

### Task 3: Execute Two Body Reads In Wasmtime

**Files:**
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/http_response_consume_body.rs`
- Create: `examples/p3-runtime/test_rust_http_response_consume_body_two_read.sh`

**Interfaces:**
- Consumes: the two-read component generated by Task 2.
- Produces: `body-bytes=2`, one response consumption, one stream drop, one trailer future drop, and an empty ResourceTable.

- [x] **Step 1: Add a red expected-byte argument.**

Run the new script against the current one-read emitter with expected count `2`; it must fail with an observed body count of `1` or an unsupported source shape.

- [x] **Step 2: Make the host produce one item per read.**

Store a cursor in `BodyStream`, put exactly one byte into the destination per `poll_produce`, return `Completed` for each accepted item, and increment `State.stats.body_bytes` by the number actually placed in the destination. The two-read fixture supplies `[0x61, 0x62]`.

- [x] **Step 3: Add the shell fixture.**

Build the two-read source, append the probe world, parse/embed/new/validate the component, run the existing Rust binary with expected count `2`, and assert cleanup markers.

- [x] **Step 4: Verify both HTTP body fixtures.**

Run the existing acquisition and one-read scripts plus the new two-read script. The old fixtures must retain their prior assertions.

### Task 4: Verify The Third Bounded Read

**Files:**
- Create: `examples/p3-runtime/http-response-consume-body-three-read.do`
- Create: `examples/p3-runtime/test_rust_http_response_consume_body_three_read.sh`
- Modify: `src/build/codegen_component_wasi_http.zig`

- [x] **Step 1: Add the three-read source and WAT assertion.**

The analyzer reports `read_count == 3`, preserves the frame index contract,
and emits the final comparison against `3`.

- [x] **Step 2: Verify the assembled runtime.**

The Rust/Wasmtime host delivers one byte per read and observes
`body-bytes=3`, exactly-once stream/trailer cleanup, and an empty resource
table.

The adjacent four-read fixture is rejected by the same bounded analyzer, so the
registered `max_stream_u8_reads == 3` limit is covered by a negative test.

### Task 5: Accept Terminal EOF

**Files:**
- Modify: `src/build/codegen_component_wasi_http.zig`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/http_response_consume_body.rs`
- Create: `examples/p3-runtime/test_rust_http_response_consume_body_eof.sh`

- [x] **Step 1: Add the empty-body red runtime test.**

The host supplies zero body items; before the change the fixed read path
delivers an item or traps instead of accepting the stream terminal code.

- [x] **Step 2: Accept `Err(nil)` as terminal cleanup.**

The emitter accepts stream code `1` at any bounded read and routes directly to
the existing stream/trailers/frame cleanup. The host returns `Dropped` once its
configured body items are exhausted.

- [x] **Step 3: Verify EOF and non-EOF paths.**

The EOF script observes `body-bytes=0`; one-, two-, and three-read scripts
continue to observe their item counts and exactly-once cleanup.

### Task 6: Read And Discard The Trailers Future

**Files:**
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/codegen_component_wasi_http.zig`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/http_response_consume_body.rs`
- Create: `examples/p3-runtime/http-response-consume-body-await-trailers.do`
- Create: `examples/p3-runtime/test_rust_http_response_consume_body_await_trailers.sh`

- [x] **Step 1: Add the red source and ABI assertions.**

Accept one body read followed by `await(completion)` and a discard binding;
the pre-change analyzer rejects the source and the pre-change registry has no
`[async-lower][future-read-2]` operation.

- [x] **Step 2: Add the descriptor-driven future read.**

Record the pinned `(i32 future, i32 address) -> i32` operation. On a pending
read, return the normal callback wait code `2`; on event code `4`, accept only
the completed read code and route through the existing cleanup.

- [x] **Step 3: Verify host readiness modes.**

The Rust host runs the same component with an already-ready trailers future and
with one pending poll followed by a wake. Both paths observe exactly one future
drop and an empty resource table. The trailers payload remains intentionally
discarded.

### Task 7: Release Gate And Boundary Record

**Files:**
- Modify: `doc/async-design.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `docs/superpowers/plans/2026-07-30-p3-async-http-runtime.md`
- Modify: `docs/superpowers/plans/2026-08-01-http-response-body-multi-read.md`

- [x] **Step 1: Record the admitted sequence and residual gaps.**

Document that one through three bounded successful body reads, terminal EOF,
and one trailers future read/discard are executable, while conditional/dynamic
EOF iteration, trailer payload lifting, request construction, and general
`client.send` remain unsupported.

- [x] **Step 2: Run the release gate.**

```bash
cd src && zig test build/codegen_component_wasi_http.zig && zig test build/codegen_component_stream_writer.zig
cd .. && bash examples/p3-runtime/test_rust_http_response_consume_body.sh
bash examples/p3-runtime/test_rust_http_response_consume_body_read.sh
bash examples/p3-runtime/test_rust_http_response_consume_body_two_read.sh
bash examples/p3-runtime/test_rust_http_response_consume_body_three_read.sh
bash examples/p3-runtime/test_rust_http_response_consume_body_eof.sh
bash examples/p3-runtime/test_rust_http_response_consume_body_await_trailers.sh
./src/build/test/run_tests.sh
git diff --check
```

Record exact results and do not claim full WASI completion.
