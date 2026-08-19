# G6.2 Bounded Stream-Mirror Producer Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

Goal: Add one private descriptor-bounded stream mirror that reads up to three u8 values from a registered source stream, writes them through a guest StreamWriter<u8>, and transfers the readable endpoint to the registered sink with exactly-once cleanup.

Architecture: Keep StreamMirrorPlan in codegen_component_async_plan.zig beside the existing StreamWriterPlan, so it can reuse existing token/range helpers and the path-sensitive lease contract. Add a distinct stream_mirror Component target and emitter entry, while reusing the writer queue, callback waitable set, frame allocator, and WAT terminal cleanup. The source and sink remain registry-selected descriptors; no general async-call IR or public ownership syntax is introduced.

Tech Stack: Zig 0.16 compiler/tests, Do source fixtures, WAT/WIT Component assembly, pinned wasm-tools 1.254.0, Rust 2024 with Wasmtime 47 legacy async runner, shell regression harness.

## Global Constraints

- Admit only do:stream-probe@0.1.0/read-via-stream and do:stream-probe@0.1.0/write-via-stream with u8 stream elements.
- Accept one new_stream<u8>(1), one zero-pre-guarded remaining u64 = 3 loop, at most three sequential @next/await/writer(value) pairs, one @cancel(source_done), one deferred close(writer), and one sink await.
- Preserve the source reader owner, source completion future/drop operation, writer lease, output reader transfer, sink future, and frame as separate cleanup obligations.
- Do not add public own<T>, borrow<T>, ref<T>, pointer, reference, scheduler, or retained callback syntax.
- Reject dynamic loop bounds, nested loops, multiple streams, helper calls, arbitrary producer expressions, lists, variants, resource-valued elements, and payload-bearing errors.
- Keep ordinary do build async rejection (AsyncLoweringUnavailable) unchanged; this slice is only for the explicit Component target.
- Preserve all existing fixed/parameterized producer, helper, HTTP body producer, stream-reader, record-stream, and cancellation gates.
- Use /home/_/._/do/.tmp/do-tmp for full regression temporary output and explicit Zig cache directories; preserve unrelated dirty worktree changes.

---

## File Map

- Modify: src/build/codegen_component_async_plan.zig — add StreamMirrorPlan, fixed loop/read/write shape parsing, and plan unit tests.
- Modify: src/build/codegen_component_async.zig — add Target.stream_mirror, source/sink target classification, and WAT/WIT dispatch before generic stream targets.
- Modify: src/build/codegen_component_stream_writer.zig — add mirror frame layout, source-read callback states, and public emit_stream_mirror_component_wat/emit_stream_mirror_component_wit functions while reusing writer runtime helpers.
- Test: src/build/codegen_component_async_plan.zig, src/build/codegen_component_async.zig, src/build/codegen_component_stream_writer.zig — focused red/green unit tests and generated WAT assertions.
- Create: examples/p3-runtime/stream-probe-stream-mirror.do — exact bounded source-to-writer fixture.
- Create: examples/p3-runtime/wit/stream-probe-stream-mirror.wit — combined private source/sink world sidecar.
- Create: examples/p3-runtime/test_do_stream_mirror_lowering.sh — WAT/WIT/Component validation gate.
- Create: examples/p3-runtime/rust-host-runner/src/bin/stream_probe_stream_mirror.rs — source producer plus sink consumer Wasmtime runner.
- Create: examples/p3-runtime/test_rust_stream_mirror.sh — pending/ready/source-EOF/error/cancel/early-drop runtime matrix.
- Modify: doc/async-design.md, doc/host_abi_blockers.md, doc/pending_blocked.md, doc/roadmap_status.md, doc/start_here.md, README.md, CHANGELOG.md — record only the verified bounded boundary.

---

### Task 1: Add Red Plan And Target Tests

Files:
- Modify: src/build/codegen_component_async_plan.zig
- Modify: src/build/codegen_component_async.zig
- Modify: src/build/codegen_component_stream_writer.zig

Interfaces:
- Planned StreamMirrorPlan.analyze(tokens, registry) !StreamMirrorPlan returns the exact source/sink names, one syntactic read/write pair, the literal runtime bound max_reads = 3, capacity, and source completion binding.
- Planned Target.stream_mirror is selected only when the exact source and sink descriptor pair plus mirror body are present.
- Planned emitter entrypoints are emit_stream_mirror_component_wat(allocator, program, tokens, module_graph) ![]u8 and emit_stream_mirror_component_wit(allocator, tokens) ![]u8.

- [ ] Step 1: Write the failing plan test.

Add a unit source containing probe_read, sink_write, source, input, source_done, new_stream<u8>(1), defer close(writer), remaining u64 = 3, one @next loop, direct Ok payload binding, writer(value), @cancel(source_done), and sink_write(writer). Assert that the implementation under test returns max_reads == 3, capacity == 1, source_reader_name == "input", source_completion_name == "source_done", and sink_host_name == "sink_write".

Add rejection cases for remaining = count, remaining = 4, a second @next in one iteration, a literal writer(65), a second stream, a helper call, missing @cancel(source_done), missing defer close(writer), and a Result<u8, ProbeError> item instead of Result<u8, nil>.

- [ ] Step 2: Write the failing target test.

Add a target_for_tokens fixture containing both registered source and sink bindings and the exact async body. Assert Target.stream_mirror; assert a source-only fixture remains Target.stream_reader and a sink-only fixture remains Target.stream_writer.

- [ ] Step 3: Write the failing emitter assertions.

Add a source fixture to codegen_component_stream_writer.zig and assert the future WAT includes [stream-mirror], separate source-read and writer-write callback markers, the source frame offsets, and the combined WIT package/world. The current code must fail because the target and entrypoints do not exist.

- [ ] Step 4: Run the red focused tests.

Run:

    cd src
    zig test build/codegen_component_async_plan.zig
    zig test build/codegen_component_async.zig
    zig test build/codegen_component_stream_writer.zig

Expected: compilation fails with missing StreamMirrorPlan/Target.stream_mirror or equivalent unsupported-shape errors; no existing test may regress before implementation starts.

---

### Task 2: Implement StreamMirrorPlan Source-Shape Analysis

Files:
- Modify: src/build/codegen_component_async_plan.zig

Interfaces:
- pub const max_stream_mirror_reads: usize = 3.
- pub const StreamMirrorRead = struct { pending_name: []const u8, item_name: []const u8, value_name: []const u8, write_pending_name: []const u8, write_result_name: []const u8 }.
- pub const StreamMirrorPlan = struct { export_name, source_descriptor, sink_descriptor, source_host_name, sink_host_name, source_handles_name, source_reader_name, source_completion_name, output_reader_name, writer_name, capacity: u32, max_reads: usize, read: StreamMirrorRead }.
- pub fn StreamMirrorPlan.analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !StreamMirrorPlan.

- [ ] Step 1: Implement descriptor pairing guards.

Find exactly one registered stream-reader binding for do:stream-probe@0.1.0/read-via-stream and exactly one registered stream-writer binding for do:stream-probe@0.1.0/write-via-stream. Require Stream<u8>/StreamWriter<u8>, zero source parameters, a Result<nil, ProbeError> source completion, the registered future-drop-readable operation, a Result<nil, ProbeError> sink result, and capacity one. Return error.UnsupportedP3StreamMirrorComponent for any other descriptor, duplicate binding, or missing binding; do not invent a future-cancel operation absent from the registry.

- [ ] Step 2: Implement the exact source prefix parser.

Reuse the existing find_matching, tok_eq, parse_stream_u8_acquire_prefix, and parse_guest_stream_new helpers. Record source, input, source_done, reader, and writer; require defer close(writer) immediately after new_stream<u8>(1). Reject any statement between acquisition and the writer defer.

- [ ] Step 3: Implement the bounded loop parser.

Require the literal binding remaining u64 = 3, a single loop, the guard if @eq(remaining, 0) { break }, then exactly one Future<Result<u8, nil>> = @next(input) and Result<u8, nil> = await(read_pending). In the Ok arm require a direct value u8 = item, a Future<Result<nil, StreamError>> = writer(value), one await/discard, and remaining = @sub(remaining, 1). In the Err arm require only break. Record the one syntactic iteration and set max_reads to the literal bound 3; reject a second syntactic read, a fourth runtime bound, or any additional statement inside the loop.

- [ ] Step 4: Implement terminal parsing.

After the loop require exactly @cancel(source_done), one Future<Result<nil, ProbeError>> = sink_write(writer), and return await(pending) at function end. Ensure no writer transfer occurs after the active defer, and return a plan with the source and sink descriptor values retained for the emitter.

- [ ] Step 5: Run the focused plan tests.

Run:

    cd src && zig test build/codegen_component_async_plan.zig

Expected: the positive mirror plan passes and every malformed shape fails with error.UnsupportedP3StreamMirrorComponent; existing writer plan tests remain green.

---

### Task 3: Add Component Target Classification And WIT Shape

Files:
- Modify: src/build/codegen_component_async.zig
- Test: src/build/codegen_component_async.zig
- Create: examples/p3-runtime/wit/stream-probe-stream-mirror.wit

Interfaces:
- Target.stream_mirror is a distinct target, not an alias for stream_reader or stream_writer.
- target_for_tokens calls StreamMirrorPlan.analyze before generic stream classification and maps only the exact pair to .stream_mirror.
- emit_component_wat dispatches .stream_mirror to codegen_component_stream_writer.emit_stream_mirror_component_wat.
- emit_component_wit dispatches .stream_mirror to codegen_component_stream_writer.emit_stream_mirror_component_wit.

- [ ] Step 1: Add the combined WIT sidecar.

Create this exact package shape:

    package do:stream-probe@0.1.0;

    interface types {
      enum error-code { io, illegal-byte-sequence, pipe }
    }

    interface source {
      use types.{error-code};
      read-via-stream: func() -> tuple<stream<u8>, future<result<_, error-code>>>;
    }

    interface sink {
      use types.{error-code};
      write-via-stream: async func(data: stream<u8>) -> result<_, error-code>;
    }

    world stream-mirror-probe {
      import source;
      import sink;
      export produce: async func() -> result<_, error-code>;
    }

- [ ] Step 2: Add target dispatch.

Add .stream_mirror to Target, classify the exact source/sink pair before the existing stream cases, and map unsupported mirror analysis back to error.UnsupportedP3AsyncComponent. Keep source-only and sink-only classification unchanged.

- [ ] Step 3: Add WIT output assertions.

Assert the generated WIT matches the sidecar exactly, includes both imported interfaces, exports only produce, and does not expose a helper or a second stream endpoint.

- [ ] Step 4: Run target and WIT tests.

Run:

    cd src && zig test build/codegen_component_async.zig

Expected: mirror classification and WIT tests pass while all existing target classification tests remain green.

---

### Task 4: Implement Mirror Frame And Callback Lowering

Files:
- Modify: src/build/codegen_component_stream_writer.zig
- Test: src/build/codegen_component_stream_writer.zig

Interfaces:
- pub const StreamMirrorFrameLayout = struct { source_reader: u32 = 64, source_completion: u32 = 68, source_pending: u32 = 72, source_result_tag: u32 = 76, source_result_payload: u32 = 80, remaining: u32 = 88, size: u32 = 96 }; the existing writer fields remain at offsets 0 through 63.
- pub fn emit_stream_mirror_component_wat(allocator, program, tokens, module_graph) ![]u8 consumes StreamMirrorPlan and returns Core WAT.
- pub fn emit_stream_mirror_component_wit(allocator, tokens) ![]u8 returns the combined package/world sidecar.
- Generated WAT contains callback markers [stream-mirror-source-read], [stream-mirror-source-eof], [stream-mirror-writer-write], [stream-mirror-sink-result], and [stream-mirror-cancel].

- [ ] Step 1: Add frame layout tests.

Assert the writer offsets remain unchanged, the source fields use the exact offsets above, the size is 96, and metadata includes both source and writer cleanup responsibilities. Run the focused emitter test and confirm the new assertions are red.

- [ ] Step 2: Add mirror WAT initialization and imports.

Start from the existing writer runtime template. Add the source stream read/drop imports from StreamReaderShape, the source completion future-drop-readable import (the registered implementation of @cancel for this descriptor), the source/writer frame initialization, and the combined source/sink descriptor import names. Initialize every new slot before the first callback.

- [ ] Step 3: Emit the source-read state machine.

Implement a source-read callback state that calls the source stream read, stores the result tag/payload in the mirror frame, and routes Ok(u8) to the writer admission state. Route Err(nil) to source completion cancellation and then sink start. A pending read must retain the frame and join the same waitable set; it must not issue a second @next.

- [ ] Step 4: Reuse writer admission and terminal cleanup.

Pass the stored one-byte payload through the existing $writer-enqueue/$writer-promote path. Decrement the remaining i64 slot only after an admitted write. On writer completion, return to the source-read state; on sink success/error, source cancellation, consumer drop, or task cancellation, release source reader, source completion future, writer endpoint, sink subtask, waitable set, and frame once.

- [ ] Step 5: Emit the root export and WIT.

Generate one produce async lift with no parameters, no helper exports, and the combined WIT package from Task 3. Keep ordinary WAT output guarded by the existing explicit Component mode.

- [ ] Step 6: Run focused emitter tests.

Run:

    cd src
    zig test build/codegen_component_stream_writer.zig
    zig fmt --check build/codegen_component_async_plan.zig build/codegen_component_async.zig build/codegen_component_stream_writer.zig

Expected: all mirror WAT markers and frame assertions pass; existing writer queue and producer tests remain green.

---

### Task 5: Add Do Fixture And Component Lowering Gate

Files:
- Create: examples/p3-runtime/stream-probe-stream-mirror.do
- Create: examples/p3-runtime/test_do_stream_mirror_lowering.sh

Interfaces:
- The fixture is the exact source shape from the design document and exports produce() -> Result<nil, ProbeError> only through the Component WIT.
- The script produces Core WAT, generated WIT, a parsed Core wasm, and a validated Component wasm under a temporary directory.

- [ ] Step 1: Add the source fixture.

Create the exact declarations and body from the design, including StreamError error = StreamClosed | StreamWriteFailed, remaining u64 = 3, direct Ok payload binding, one source completion cancel, and deferred writer close. Do not add start, helper functions, a second stream, or source parameters.

- [ ] Step 2: Add the lowering script.

The script must run:

    DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
      --p3-wit-output "$wit_path" "$repo_root/examples/p3-runtime/stream-probe-stream-mirror.do" \
      -o "$core_path"
    wasm-tools parse "$core_path" -o "$core_wasm"
    bash "$repo_root/examples/p3-runtime/assemble_async_component.sh" \
      "$wit_path" "$core_wasm" stream-mirror-probe "$component_path"
    wasm-tools validate --features cm-async,cm-more-async-builtins "$component_path"

Compare the WIT with examples/p3-runtime/wit/stream-probe-stream-mirror.wit and assert the source-read, writer-write, source-cancel, frame-size 96, and root-only export markers.

- [ ] Step 3: Run the lowering gate.

Run:

    bash examples/p3-runtime/test_do_stream_mirror_lowering.sh

Expected: WIT comparison, Core parsing, Component assembly, and validation pass; the ordinary ./bin/do build path still reports AsyncLoweringUnavailable for this async fixture.

---

### Task 6: Add Rust/Wasmtime Source And Sink Runtime Matrix

Files:
- Create: examples/p3-runtime/rust-host-runner/src/bin/stream_probe_stream_mirror.rs
- Create: examples/p3-runtime/test_rust_stream_mirror.sh

Interfaces:
- The runner installs do:stream-probe/source@0.1.0 and do:stream-probe/sink@0.1.0 instances.
- The source returns [65, 66, 67] through a StreamProducer<u8> and a never-ready completion future; the sink consumes exactly the configured number of values through StreamConsumer<()>; the future drop is the observable @cancel finalization for this descriptor.
- Runner modes are pending, ready, source-eof, error, cancel, and early-drop; output reports items, source-stream-drops, source-future-drops, sink-callbacks, and sink-stream-drops. The lowering gate, rather than the host, observes the guest writer-close marker.

- [ ] Step 1: Implement the source producer and completion future.

Reuse the StreamProducer<u8> and Future patterns from stream_probe.rs. Record source item order and increment source stream/future drop counters in Drop. For source-eof, expose fewer than three values and let the Component receive Err(nil); for other modes expose all three.

- [ ] Step 2: Implement the sink consumer.

Reuse the StreamConsumer<()> pattern from stream_probe_guest_producer_dynamic.rs. Record one sink callback, make pending return Poll::Pending once, make ready consume immediately, make error return Err(ErrorCode::Pipe), and make early-drop return StreamResult::Dropped after the first value. Always await the reader drop notification before returning the sink result.

- [ ] Step 3: Assert the cleanup contract.

Require [65,66,67] in normal pending/ready modes, a shorter prefix plus EOF in source-eof, result=err:pipe in error, and one consumed value in early-drop. Every mode must report one source stream drop, one source future drop, one sink callback, one sink reader drop, and no duplicate terminal event. cancel must report the source future drop without a completion poll and still leave the resource table empty.

- [ ] Step 4: Add and run the shell matrix.

The script must assemble the Component using the Task 5 output and run:

    for mode in pending ready source-eof error cancel early-drop; do
      cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
        --bin do-p3-stream-mirror-host-runner -- "$component_path" "$mode"
    done

Run bash examples/p3-runtime/test_rust_stream_mirror.sh; expected result is six passing runtime modes with exactly-once cleanup in each applicable path.

---

### Task 7: Documentation And Full Verification

Files:
- Modify: doc/async-design.md
- Modify: doc/host_abi_blockers.md
- Modify: doc/pending_blocked.md
- Modify: doc/roadmap_status.md
- Modify: doc/start_here.md
- Modify: README.md
- Modify: CHANGELOG.md

Interfaces:
- Documentation names the admitted descriptor pair, the three-read mirror limit, frame size/cleanup contract, and every rejection boundary using the same terms as the compiler diagnostics and fixtures.
- Documentation must not call this general producer runtime, full G6.2, or complete WASI.

- [ ] Step 1: Record the verified bounded boundary.

Add one current checkpoint describing source stream -> bounded writer -> sink, pending/ready/source-EOF/error/cancel/early-drop evidence, and exactly-once cleanup. Keep the existing general producer, borrowed resource, and D2 blockers unchanged.

- [ ] Step 2: Run focused and runtime gates.

Run:

    cd src
    zig test build/codegen_component_async_plan.zig
    zig test build/codegen_component_async.zig
    zig test build/codegen_component_stream_writer.zig
    zig test main.zig
    zig build -Doptimize=ReleaseSmall
    cd ..
    bash examples/p3-runtime/test_do_stream_mirror_lowering.sh
    bash examples/p3-runtime/test_rust_stream_mirror.sh

- [ ] Step 3: Run the full regression with explicit caches.

Run:

    TMPDIR=/home/_/._/do/.tmp/do-tmp \
    ZIG_LOCAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-cache \
    ZIG_GLOBAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-gcache \
      ./src/build/test/run_tests.sh
    TMPDIR=/home/_/._/do/.tmp/do-tmp \
    ZIG_LOCAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-cache \
    ZIG_GLOBAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-gcache \
      RUN_WASM=1 ./src/build/test/run_tests.sh

Expected: fail=0, the existing skip set unchanged, and the WASM run summary reports no new skipped mirror fixture.

- [ ] Step 4: Run final static checks.

Run:

    rustfmt --check examples/p3-runtime/rust-host-runner/src/bin/stream_probe_stream_mirror.rs
    bash -n examples/p3-runtime/test_do_stream_mirror_lowering.sh examples/p3-runtime/test_rust_stream_mirror.sh
    python3 -m json.tool src/build/p3_async_registry.json >/dev/null
    git diff --check

Record command output and distinguish verified items from any unrelated dirty-worktree failures.

---

## Deferred After This Plan

- General producer expressions and unrestricted async-call composition.
- General ownership/borrow IR or public own<T>/borrow<T>/ref<T> syntax.
- Arbitrary stream element layouts, list/variant/resource-valued stream items.
- A sixth helper-forwarding edge or dynamic/unbounded mirror loops.
- D2 real host runtime, full WASI, scheduler API, and rollback of external side effects.
