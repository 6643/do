# G6.2 Bounded List-Owned Resource Stream Lowering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lower exactly one registered private `stream<list<resource-entry>>`
descriptor through a single stream read with a bounded, exactly-once owned-ticket
cleanup lifecycle.

**Architecture:** Keep the existing generic record-stream emitter unchanged.
Add a new manifest shape, source-plan analyzer, and fixed component emitter for
`do:record-resource-list-stream-probe@0.1.0/read-via-stream`. The generated WAT
uses the ABI verified by the canonical probe: `ptr@64`, `len@68`, stride `4`,
ticket offset `0`, and only zero, one, or three list elements. It moves validated
ticket handles into three frame-owned slots, clears each slot before its resource
drop, releases list storage by the proven `cabi_realloc` call, and shares one
cleanup path for completion, error, and early terminal paths.

**Tech Stack:** Zig 0.16.0, Do compiler source, hand-emitted Core WAT,
wasm-tools 1.254.0, Rust 1.97.1, Wasmtime 47.0.2.

## Global Constraints

- The only admitted descriptor is locator
  `do:record-resource-list-stream-probe@0.1.0`, member `read-via-stream`,
  source result `Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>>`.
- The source body has one `@next(reader)`, one `await(pending)`, does not expose
  the received list, then awaits the completion and returns `Ok()` or `Err`.
- `stream.read` receives result space at `frame+64`; it may transfer lengths
  `0`, `1`, or `3` only. A nonempty list has `ptr != 0`, `ptr % 4 == 0`, and
  `len * 4` exactly matches the private allocation. Length `0` requires
  `ptr == 0`.
- Every transferred ticket is copied to one of `frame+20`, `frame+24`, or
  `frame+28`, with no allocation or pointer arithmetic exposed to Do source.
  The handle slot is cleared before `[resource-drop]ticket` and is released once.
- List storage is allocated only as `cabi_realloc(0, 0, 4, 4|12)` and released
  once as `cabi_realloc(ptr, len * 4, 4, 0)`. Empty lists do not allocate or
  release storage.
- Malformed pointer/length, a missing ticket handle, a duplicate release, a
  second read, a list length of `2` or `4+`, any nested list/resource/variant,
  borrowed resource, unregistered descriptor, or public
  `Option<T>`/`own<T>`/`borrow<T>`/`ref<T>` syntax remains rejected or traps at
  the existing boundary. Do not relax a generic parser or increase a limit.
- Cleanup must drop the stream, completion future, all owned tickets, and list
  storage exactly once on ready, pending, completion `Err(io)`, and early cleanup.
  No ticket may be read before validation has completed.
- Preserve the current dirty worktree. Do not reset, clean, commit, or alter
  unrelated user changes.

---

## File Structure

- `src/build/p3_async_manifest.zig`: Parses and validates a new exact
  `record-resource-list-stream-reader` lowering shape; it owns the typed ABI
  facts consumed by codegen.
- `src/build/p3_async_registry.json`: Registers the sole private descriptor
  and records its list, element, resource-drop, and async import facts.
- `src/build/codegen_component_record_resource_list_stream.zig`: Contains the
  exact source analyzer, WIT writer, fixed Core-WAT template, WAT construction,
  and focused Zig tests. It does not import `codegen_component_record_stream.zig`.
- `src/build/codegen_component_async.zig`: Routes only the new manifest shape
  to the new emitter, leaving record-stream routing untouched.
- `examples/p3-runtime/record-resource-list-stream-probe-component.do`: Becomes
  the positive, single-read compiler fixture.
- `examples/p3-runtime/test_do_record_resource_list_stream_lowering.sh`: Builds
  the positive fixture, embeds the produced WAT, and runs the existing
  Rust/Wasmtime list-resource ABI runner for ready/pending/error/early paths.
- `examples/p3-runtime/record-resource-list-stream-unregistered-component.do`
  and `examples/p3-runtime/test_do_record_resource_list_stream_boundary.sh`:
  Retain a distinct unknown-locator negative compiler boundary.
- `doc/host_abi_blockers.md`, `doc/pending_blocked.md`, and
  `doc/roadmap_status.md`: Record only the registered bounded slice after all
  runtime gates pass; retain every broader shape as pending.

## Task 1: Register and Reject the Exact Descriptor

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Test: `src/build/p3_async_manifest.zig`

**Interfaces:**
- Produces `LoweringShape.record_resource_list_stream_reader` with the method,
  stream/future operations, `resource-entry` layout, `list_result_offset=64`,
  `list_length_offset=68`, `element_stride=4`, `ticket_offset=0`, and
  `max_items=3`.
- The next task consumes this shape without re-parsing JSON or accepting a
  generic record/list combination.

- [ ] **Step 1: Add a failing manifest test for the exact descriptor.**

  Add a minimal registry JSON fixture containing the exact list result spelling,
  one `own ticket` field, the five async operations, and the list ABI facts.
  Assert that `lowering_shape` returns the new shape and exposes `0/1/3` as the
  admitted element-count set. Add one fixture with `element_stride=8` and one
  with `max_items=4`; assert both resolve to `null`.

- [ ] **Step 2: Run the focused manifest tests and confirm RED.**

  Run:

  ```bash
  cd src && zig test build/p3_async_manifest.zig --test-filter 'list-owned resource stream'
  ```

  Expected: the positive fixture cannot classify because
  `record_resource_list_stream_reader` does not exist yet.

- [ ] **Step 3: Add the narrow manifest model and validator.**

  Add a distinct shape struct rather than extending `RecordStreamReaderShape`.
  Require all of the following before returning it:

  ```zig
  descriptor.params.len == 0
  descriptor.effect == "record-resource-list-stream-reader"
  descriptor.result == "tuple<stream<list<resource-entry>>,future<result<_,error-code>>>"
  layout.byte_size == 4
  layout.source_fields.len == 1
  layout.source_fields[0].ownership == .own
  list_result_offset == 64
  list_length_offset == 68
  element_stride == 4
  ticket_offset == 0
  max_items == 3
  ```

  Register exactly `do:record-resource-list-stream-probe@0.1.0` with matching
  `source` and `probe` WIT metadata plus resource-drop import
  `[resource-drop]ticket`. Do not make an existing descriptor match the new
  validator.

- [ ] **Step 4: Run the manifest tests and the existing manifest suite.**

  Run:

  ```bash
  cd src && zig test build/p3_async_manifest.zig
  ```

  Expected: the new exact descriptor is admitted, malformed alternatives are
  rejected, and all existing registry tests remain green.

## Task 2: Prove Source Routing and Preserve the Negative Boundary

**Files:**
- Modify: `src/build/codegen_component_async.zig`
- Create: `examples/p3-runtime/record-resource-list-stream-unregistered-component.do`
- Modify: `examples/p3-runtime/test_do_record_resource_list_stream_boundary.sh`
- Test: `src/build/codegen_component_async.zig`

**Interfaces:**
- Consumes the new manifest shape from Task 1.
- Produces `Target.record_resource_list_stream`, selected only when the exact
  source binding and a future `ListResourceStreamPlan` both validate.

- [ ] **Step 1: Add a failing target-selection test.**

  Use the checked-in positive fixture shape and assert that
  `target_for_tokens` returns `record_resource_list_stream`. Add a second
  source that repeats `@next(reader)` and assert it returns
  `UnsupportedP3AsyncComponent`.

- [ ] **Step 2: Run the target-selection test and confirm RED.**

  Run:

  ```bash
  cd src && zig test build/codegen_component_async.zig --test-filter 'list-owned resource stream'
  ```

  Expected: the target enum has no list-resource-stream route.

- [ ] **Step 3: Route only the new shape.**

  Add a target enum case and call
  `codegen_component_record_resource_list_stream.emit_component_wat` /
  `emit_component_wit`. Match the new shape in `target_for_descriptor` and
  `target_for_tokens`; do not alter `.record_stream`, `.stream_reader`, or
  `.wasi_read_directory` matching. Keep an unknown locator fixture in the
  boundary script and require `UnknownP3AsyncHostDescriptor`.

- [ ] **Step 4: Verify routing and rejection.**

  Run:

  ```bash
  cd src && zig test build/codegen_component_async.zig
  ./examples/p3-runtime/test_do_record_resource_list_stream_boundary.sh
  ```

  Expected: the exact positive source reaches the new target; repeated-read
  and unknown-locator sources fail before WAT emission.

## Task 3: Implement Single-Read List Ownership Lowering

**Files:**
- Create: `src/build/codegen_component_record_resource_list_stream.zig`
- Modify: `src/build/codegen_component_async.zig`
- Test: `src/build/codegen_component_record_resource_list_stream.zig`

**Interfaces:**
- Consumes `RecordResourceListStreamShape` and the exact Do source program.
- Produces `emit_component_wat` and `emit_component_wit`, returning
  `UnsupportedP3RecordResourceListStreamComponent` for every other form.

- [ ] **Step 1: Add a failing WAT-emitter test.**

  Tokenize the positive source and assert emitted WAT contains the exact ABI
  markers and cleanup structure:

  ```text
  ;; [list-result-pointer] 64
  ;; [list-result-length] 68
  ;; [list-element-stride] 4
  ;; [list-ticket-offset] 0
  call $consume-list
  call $release-list
  call $ticket-drop
  ```

  Assert the generated module calls `stream-read` once, checks only lengths
  `0`, `1`, and `3`, and emits a strict `cabi_realloc` allocation/release pair.
  Add negative source tests for a second `@next`, a loop, list item consumption,
  an unregistered locator, and an altered resource field.

- [ ] **Step 2: Run the emitter test and confirm RED.**

  Run:

  ```bash
  cd src && zig test build/codegen_component_record_resource_list_stream.zig --test-filter 'list-owned resource'
  ```

  Expected: the module and its exact source plan do not exist.

- [ ] **Step 3: Implement a separate exact analyzer and fixed emitter.**

  The analyzer must accept only the source sequence below, apart from local
  identifier spelling:

  ```do
  handles Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>> = probe_read()
  reader Stream<[ResourceEntry]> = @get(handles, 0)
  completion Future<Result<nil, ProbeError>> = @get(handles, 1)
  pending Future<Result<[ResourceEntry], nil>> = @next(reader)
  item Result<[ResourceEntry], nil> = await(pending)
  _ = item
  completed Result<nil, ProbeError> = await(completion)
  if @is(completed, Err) return completed
  return Ok()
  ```

  Emit a fixed 128-byte frame. `consume-list` validates the complete pointer /
  length contract before loading tickets, copies the zero to three raw handles
  to slots `20 + index * 4`, clears the raw handle after transfer, releases
  list storage exactly once, and marks ownership active. `release-list` drops
  only active slots, clears each before `$ticket-drop`, then marks the list
  terminal. `cleanup` calls future-drop, stream-drop, list release, waitable
  drop, context clear, task return, and frame free in that order. Reuse only
  local helper text construction patterns from the generic record-stream
  emitter; do not refactor it into a shared generic list path.

- [ ] **Step 4: Emit exact WIT for the registered private world.**

  Generate `resource ticket`, `record resource-entry { ticket: own<ticket> }`,
  `stream<list<resource-entry>>`, the completion `future<result<_,error-code>>`,
  and the async `probe.run` export. Its package, interface, world, and names
  must come from the registered descriptor.

- [ ] **Step 5: Run focused unit tests and parse the emitted Core WAT.**

  Run:

  ```bash
  cd src && zig test build/codegen_component_record_resource_list_stream.zig
  DO_LIB_ROOT="$PWD/lib" "$PWD/bin/do" build --p3-async-component \
    examples/p3-runtime/record-resource-list-stream-probe-component.do \
    --p3-wit-package-output /tmp/do-list-resource-wit -o /tmp/do-list-resource.wat
  wasm-tools parse /tmp/do-list-resource.wat -o /tmp/do-list-resource.wasm
  wasm-tools component embed /tmp/do-list-resource-wit /tmp/do-list-resource.wasm \
    --world record-resource-list-stream-probe \
    --features cm-async,cm-more-async-builtins -o /tmp/do-list-resource.embedded.wasm
  ```

  Expected: all focused Zig tests pass and the generated Core module embeds
  using the private WIT world.

## Task 4: Execute the Generated Component Matrix

**Files:**
- Create: `examples/p3-runtime/test_do_record_resource_list_stream_lowering.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/record_resource_list_stream_abi.rs`
- Test: `examples/p3-runtime/test_do_record_resource_list_stream_lowering.sh`

**Interfaces:**
- Consumes the compiler-generated component from Task 3.
- Produces a runtime gate that proves generated, not hand-authored, WAT obeys
  the list ownership ABI and cleanup matrix.

- [ ] **Step 1: Add a failing generated-component gate.**

  Copy the current canonical ABI script structure but build the positive Do
  fixture first. Point the Rust runner at the generated component and require
  `ready-empty`, `ready-one`, `ready-three`, `pending`, `completion-error`, and
  `early-drop` outputs to show the exact entries, ticket-drop count, future and
  stream drops, and `table-empty=true`.

- [ ] **Step 2: Run the new gate and confirm RED.**

  Run:

  ```bash
  ./examples/p3-runtime/test_do_record_resource_list_stream_lowering.sh
  ```

  Expected: the current compiler does not emit the required list-resource WAT
  or the runner cannot link the generated package yet.

- [ ] **Step 3: Make the runner package-neutral for the two private worlds.**

  Replace its two hard-coded component instance strings with command-line or
  paired constants selected by a `--generated` flag. Keep all resource types,
  list values, cleanup counters, malformed and duplicate behavior identical;
  this is test infrastructure, not a second lowering path.

- [ ] **Step 4: Extend the generated gate with malformed and duplicate variants.**

  Derive temporary WAT variants from generated WAT at the stable list-consume
  and list-release markers. Require length `4` to trap before owning tickets
  (`resource-drops=0`, table nonempty), and a second release to trap after
  exactly three drops with an empty table.

- [ ] **Step 5: Run all list ABI gates.**

  Run:

  ```bash
  bash -n examples/p3-runtime/test_do_record_resource_list_stream_lowering.sh
  ./examples/p3-runtime/test_record_resource_list_stream_abi.sh
  ./examples/p3-runtime/test_do_record_resource_list_stream_lowering.sh
  ```

  Expected: the hand-authored canonical probe and compiler-generated component
  pass the same ready/pending/error/early/malformed/duplicate matrix.

## Task 5: Document the Narrow Admission and Run the Regression Gate

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Test: `src/build/test/run_tests.sh`

**Interfaces:**
- Consumes fresh output from Tasks 1-4.
- Produces current-state documentation that names the one descriptor and every
  rejected adjacent shape.

- [ ] **Step 1: Update only verified facts.**

  Record the registered locator, one read, lengths `0/1/3`, four-byte element
  layout, exactly-once cleanup, and the generated Rust/Wasmtime matrix. State
  that public ownership syntax, generic lists, second reads, length `2/4+`,
  borrowed/list/variant/nested shapes, and the remaining G6.2/D2 work are
  still unavailable.

- [ ] **Step 2: Run formatting and focused checks.**

  Run:

  ```bash
  cd src && zig fmt --check build/p3_async_manifest.zig build/codegen_component_async.zig build/codegen_component_record_resource_list_stream.zig
  rustfmt --edition 2024 --check examples/p3-runtime/rust-host-runner/src/bin/record_resource_list_stream_abi.rs
  bash -n examples/p3-runtime/test_do_record_resource_list_stream_boundary.sh
  bash -n examples/p3-runtime/test_do_record_resource_list_stream_lowering.sh
  git diff --check
  ```

- [ ] **Step 3: Run full regression and final boundary checks.**

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp/list-resource-regression" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/list-resource-zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/list-resource-zig-gcache" \
    ./src/build/test/run_tests.sh
  ./examples/p3-runtime/test_do_record_resource_list_stream_boundary.sh
  ./examples/p3-runtime/test_do_record_resource_list_stream_lowering.sh
  ```

  Expected: regression reports zero failures; the unknown descriptor still
  emits `UnknownP3AsyncHostDescriptor`; all generated list-resource runtime
  cases preserve their exact ownership accounting.

## Plan Self-Review

- The sole positive shape, ABI offsets, three permitted list sizes, ticket
  transfer, list allocation/release, and all terminal paths are covered by
  Tasks 1, 3, and 4.
- Parser/public-type scope is not broadened: Task 2 only dispatches after the
  new exact manifest and source analyzer match; Task 5 repeats every boundary.
- The plan keeps generic record streams isolated and changes no existing
  resource-list lowering limit.
- No placeholder implementation step remains; all test commands and required
  evidence are named explicitly.
