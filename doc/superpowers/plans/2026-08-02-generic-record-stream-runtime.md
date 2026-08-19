# Generic Record-Stream Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a descriptor-driven consumer runtime for registered WIT record streams, including dynamic `@next` loops, record lifting, completion/error handling, cancellation, and exactly-once cleanup.

**Architecture:** Keep the pinned manifest as the ABI source of truth and add a pure `RecordStreamConsumer` state machine behind `src/build/codegen_component_record_stream.zig`. The generic emitter will consume that plan and emit one-in-flight-read resumable WAT; the existing fixed `read-directory` emitter will use the same validated layout and cleanup helpers during migration. Guest producer leases remain a separate follow-up and are not claimed by this plan.

**Tech Stack:** Zig compiler, WAT templates, pinned `wasm-tools 1.254.0`, Rust/Wasmtime runtime probes, existing Do lexer/sema and regression harness.

## Global Constraints

- Do source does not expose `own<T>`, `borrow<T>`, `ref<T>`, pointers, or references.
- WIT `own`/`borrow` remain internal descriptor and cleanup facts.
- Only descriptors with a pinned WIT/source mirror and validated record layout may lower.
- At most one stream read is in flight for a consumer.
- Cancellation waits for the Component operation to become terminal and never rolls back host effects.
- The existing fixed one-to-three-entry filesystem fixtures must remain green.
- No fallback WAT is emitted for an unsupported descriptor or source shape.

---

### Task 1: Add The Pure Consumer State Machine

**Files:**
- Create: `src/build/codegen_component_record_stream.zig`
- Test: `src/build/codegen_component_record_stream.zig` unit tests

**Interfaces:**
- Consumes: no compiler globals; later tasks pass a validated descriptor plan into it.
- Produces: `Consumer`, `Phase`, `Event`, `Effect`, and `Transition` types that encode one-in-flight-read and idempotent terminal cleanup.

- [x] **Step 1: Write the failing transition tests.**

Add tests for this exact event sequence and effect order:

```zig
var consumer = Consumer.init();
try expectEffects(consumer.dispatch(.start), &.{ .issue_read });
try expectEffects(consumer.dispatch(.read_pending), &.{ .wait_read });
try expectEffects(consumer.dispatch(.read_ok), &.{ .decode_record, .issue_read });
try expectEffects(consumer.dispatch(.read_eof), &.{ .await_completion });
try expectEffects(consumer.dispatch(.completion_ok), &.{ .drop_stream, .drop_completion, .release_record, .release_frame, .return_ok });
```

Also assert that a second `.issue_read` while `read_pending` is rejected,
`cancel` emits `cancel_read` before cleanup, and a repeated completion callback
emits no second drop or release.

- [x] **Step 2: Run the focused test and verify RED.**

Run:

```bash
cd src && zig test build/codegen_component_record_stream.zig
```

Expected: compilation fails because the new module and `Consumer` API do not
exist.

- [x] **Step 3: Implement the minimal guarded transition model.**

Use these public shapes:

```zig
pub const Phase = enum { idle, read_pending, item_ready, completion_pending, terminal, closed };
pub const Event = enum { start, read_pending, read_ok, read_eof, read_error, completion_pending, completion_ok, completion_error, cancel };
pub const Effect = enum { issue_read, wait_read, decode_record, await_completion, cancel_read, cancel_completion, drop_stream, drop_completion, release_record, release_frame, return_ok, return_err };
pub const Transition = struct { phase: Phase, effects: [max_effects]Effect, effect_count: u8 };
pub const Consumer = struct {
    phase: Phase = .idle,
    read_active: bool = false,
    completion_active: bool = false,
    cleanup_mask: u8 = 0,
    pub fn init() Consumer;
    pub fn dispatch(self: *Consumer, event: Event) Transition;
};
```

Invalid events must return a transition with `effect_count == 0` and leave the
phase unchanged. Cleanup bits are monotonic; `.terminal` may be dispatched more
than once but only the first terminal transition emits return/cleanup effects.

- [x] **Step 4: Run the focused test and verify GREEN.**

Run the same `zig test` command. All transition, illegal-read, cancellation,
EOF, error, and idempotence assertions must pass.

### Task 2: Generalize Manifest Record Metadata

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Test: `src/build/p3_async_manifest.zig`

**Interfaces:**
- Consumes: existing `Canonical.record_layout` and pinned filesystem source mirror.
- Produces: validated source-field encodings for scalar fields and UTF-8 pointer/length pairs, plus a private `do:record-stream-probe@0.1.0` descriptor.

- [x] **Step 1: Add red manifest cases.**

Add an in-memory layout with one `u32` source field and one `string` source
field backed by `label-ptr`/`label-len`; assert the parsed source fields expose
their storage offsets. Add malformed cases for a missing text pair, overlapping
pointer/length storage, duplicate source names, and a nested/list field.

- [x] **Step 2: Run the focused manifest tests and verify RED.**

Run:

```bash
cd src && zig test build/p3_async_manifest.zig --test-filter 'generic record metadata'
```

Expected: the new source-field assertions fail because the current metadata
contains only unnamed Core storage slots.

- [x] **Step 3: Implement owned source-field metadata and validation.**

Extend `RecordLayout` with `byte_size` and `source_fields`. A scalar source
field names one storage field; a UTF-8 field names a pointer storage field and a
length storage field. Parse and free all owned strings, require four-byte
alignment, require `byte_size` to cover every slot, and reject unsupported
source kinds before returning a lowerable shape.

- [x] **Step 4: Add the private record probe descriptor.**

Register `do:record-stream-probe@0.1.0/read-via-stream` with a
`tuple<stream<probe-entry>,future<result<_,error-code>>>` result, a record layout
containing `id u32` and `label string`, and the same canonical stream/future
operation signatures used by the pinned reader. Keep the existing filesystem
descriptor source hash and field-order checks unchanged.

- [x] **Step 5: Run focused manifest and existing filesystem tests.**

Run:

```bash
cd src && zig test build/p3_async_manifest.zig
cd .. && ./src/build/test/run_tests.sh
```

Expected: generic metadata tests pass, the private descriptor is discoverable,
and all existing cases remain green.

### Task 3: Parse The Generic Dynamic Consumer Source

**Files:**
- Modify: `src/build/codegen_component_record_stream.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Create: `examples/p3-runtime/record-stream-probe-component.do`
- Test: `src/build/codegen_component_record_stream.zig`

**Interfaces:**
- Consumes: lexer tokens, `Registry`, and `RecordStreamReaderShape` from Task 2.
- Produces: `RecordStreamSourcePlan.analyze(tokens, registry)` for a loop with one explicit `@next`/`await` per iteration and a generic `@is(item, Ok)` guard.

- [x] **Step 1: Add the red source fixture and analyzer assertions.**

Use this exact source contract:

```do
probe_read = @host_func("do:record-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>>)

async run() -> Result<nil, ProbeError> {
    handles Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>> = probe_read()
    reader Stream<ProbeEntry> = @get(handles, 0)
    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
    loop {
        pending Future<Result<ProbeEntry, nil>> = @next(reader)
        item Result<ProbeEntry, nil> = await(pending)
        if @is(item, Ok) {
            entry ProbeEntry = item
            _ = entry
        } else {
            break
        }
    }
    completed Result<nil, ProbeError> = await(completion)
    if @is(completed, Err) return completed
    return Ok()
}

start() {}
```

The analyzer test must assert the descriptor, record type, loop continuation,
completion binding, and one-in-flight read contract. Add a negative fixture with
two `@next` bindings before the first await and assert
`UnsupportedP3RecordStreamComponent`.

- [x] **Step 2: Run the analyzer test and verify RED.**

Run:

```bash
cd src && zig test build/codegen_component_record_stream.zig --test-filter 'dynamic source'
```

Expected: the fixture is rejected because no generic loop analyzer exists.

- [x] **Step 3: Implement guarded source analysis.**

Reuse `sema_tokens.find_matching`, existing loop-boundary helpers, and the
generic `@is(..., Ok/Err)` semantics. Accept only the source sequence shown
above; reject hidden reads, nested loops, multiple outstanding futures, writes,
and unregistered record descriptors. Return the explicit unsupported error for
every other shape.

- [x] **Step 4: Run source and sema regression tests.**

Run:

```bash
cd src && zig test build/codegen_component_record_stream.zig
cd .. && ./src/build/test/run_tests.sh
```

### Task 4: Emit Generic Record-Stream WAT

**Files:**
- Modify: `src/build/codegen_component_record_stream.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/codegen_component_wasi_filesystem_read_directory.zig`
- Create: `examples/p3-runtime/test_do_record_stream_probe_lowering.sh`
- Test: `src/build/codegen_component_record_stream.zig`

**Interfaces:**
- Consumes: `RecordStreamSourcePlan`, `RecordStreamConsumer`, descriptor import names, and source-field encodings.
- Produces: Core WAT/WIT with a shared frame, resumable read loop, record decode, completion await, and terminal cleanup.

- [x] **Step 1: Add WAT marker assertions before emission changes.**

Require the generated WAT to contain:

```text
[record-stream-plan]
[record-loop-state]
[record-read-index]
[record-field-id-offset]
[record-field-label-ptr-offset]
[record-field-label-len-offset]
call $cleanup
```

Also assert that it does not contain `directory-entry`, `descriptor.read-directory`,
or literal directory offsets.

- [x] **Step 2: Implement descriptor-driven frame and resume emission.**

Generate one frame slot for the stream handle, completion future, record area,
loop state, and cleanup flags. Emit `stream-read` only from the loop state, copy
scalar fields and text bytes into Do-owned storage, and route EOF, completion
error, cancellation, and normal return through the shared cleanup transition.

- [x] **Step 3: Connect the fixed filesystem emitter to shared layout helpers.**

Replace its record-offset replacement block with calls into the generic layout
resolver. Preserve its current one-to-three-read source guard and all existing
WAT import names while removing duplicate offset validation.

- [x] **Step 4: Run compiler/component lowering gates.**

Run:

```bash
cd src && zig test build/codegen_component_record_stream.zig
cd .. && bash examples/p3-runtime/test_do_record_stream_probe_lowering.sh
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_bounded_lowering.sh
```

Expected: the private record probe assembles and validates, and all fixed
filesystem lowering gates remain green.

### Task 5: Execute Pending/Ready Runtime And Close The Consumer Milestone

**Files:**
- Create: `examples/p3-runtime/wit/record-stream-probe.wit`
- Create: `examples/p3-runtime/test_rust_record_stream_probe.sh`
- Modify: existing Rust/Wasmtime probe runner or add a focused runner under `examples/p3-runtime/rust-host-runner/`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: generic WAT/WIT from Task 4 and the pinned async Component adapter.
- Produces: pending and immediately-ready runtime evidence with an empty resource table and exact cleanup counts.

- [x] **Step 1: Add the runtime red gate.**

The Rust host must provide two records (`id=1,label="alpha"` and
`id=2,label="beta"`), one pending completion future, one immediately-ready
completion future, and a completion error case. Before the generic emitter is
connected, the script must fail because the generated component is unsupported.

- [x] **Step 2: Implement host observations and exact cleanup assertions.**

Assert two records in order, one EOF, one pending wake in pending mode, zero
wakes in ready mode, one completion error, one stream drop per call, one future
drop per call, and an empty `ResourceTable` after every call.

- [x] **Step 3: Run the focused runtime matrix.**

Run:

```bash
bash examples/p3-runtime/test_do_record_stream_probe_lowering.sh
bash examples/p3-runtime/test_rust_record_stream_probe.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory_bounded.sh
```

- [x] **Step 4: Run the release verification matrix and update boundaries.**

Run:

```bash
./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

Document that generic consumer record streams are now executable, while guest
producer loops, arbitrary resource fields, payload-bearing completion errors,
and arbitrary filesystem async methods remain outside this plan until their
separate producer/resource gates pass.

## Plan Exit Criteria

- A registered non-filesystem record stream lowers through the shared plan.
- A dynamic loop consumes multiple records and EOF in a real Component.
- Pending, ready, error, and cancellation paths clean every owned endpoint once.
- The fixed filesystem slice still passes without duplicate hard-coded layout
  logic.
- Full regression and release smoke pass before the G6.2 status is changed.
