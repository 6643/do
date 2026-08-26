# G6.2 Direct Owned-Record Producer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement and verify the private, descriptor-bounded G6.2 direct
`stream<resource-entry>` producer selected in the design spec, with one owned
ticket transfer and exactly-once cleanup on every terminal path.

**Architecture:** Keep the capability behind the existing manifest-driven
Preview-3 Component route. A dedicated manifest shape and dedicated emitter
recognize only the exact `do:g6-2-owned-record-producer@0.1.0` descriptor; a
hand-authored Core-WAT template performs one record write and its cleanup. The
Rust/Wasmtime runner is the lifecycle oracle, while Do positive/negative
fixtures lock the source admission boundary. No public ownership syntax or
general async lowering is introduced.

**Tech Stack:** Zig `0.16.0`, Do compiler, `wasm-tools 1.255.0`, Rust/Cargo
`1.97.1`, Wasmtime `47.0.2`, Bash regression gates, and the existing
`component-model-async` feature set.

**Spec:** `doc/superpowers/specs/2026-08-26-g6-2-owned-record-producer-design.md`

## Global Constraints

- The WIT source is exactly the text in the spec and has SHA-256
  `6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace`.
- The descriptor is `do:g6-2-owned-record-producer@0.1.0`, member
  `consume-via-stream`, effect `record-resource-stream-producer`, world
  `owned-record-producer`.
- The stream element is exactly `resource-entry`; the record is four bytes,
  aligned to four bytes, with `ticket: own<ticket>` at offset zero.
- The stream capacity is one and each valid invocation creates and transfers
  at most one ticket with seed `111`.
- The source binding is `@host_func(..., (u32) -> Ticket)` and the sink binding
  is `@host_async_func(..., (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)`.
- The source sentinel has exactly `produce(mode u32) -> Result<nil, ProducerError> { return Ok() }`
  and `start() {}`; no Do async token or async intrinsic is admitted.
- Canonical sink imports use the exact names and arities in the spec, with
  `core_params = ["i32", "i32"]`, `core_results = ["i32"]`,
  `completion_params = ["i32", "i32"]`, and `completion = "task-return"`.
- Ownership transfers only after a successful stream write. Before transfer
  the guest drops the ticket; after transfer the host drops it. Every stream,
  task/future, frame/waitable, and ticket lease is cleaned exactly once.
- Cancellation and early task drop clean internal state only; they never claim
  to roll back an external effect already observed by the sink.
- A drift, unsupported shape, or probe failure returns a fail-closed error
  before WAT emission. No compatibility alias is added.
- Do not stage or revert unrelated dirty-worktree files. Each commit names
  only the files listed by its task.

---

### Task 1: Pin WIT and build the hand-authored canonical lifecycle oracle

**Files:**
- Create: `examples/p3-runtime/wit/g6-2-owned-record-producer.wit`
- Create: `examples/p3-runtime/g6-2-owned-record-producer-canonical.wat`
- Create: `examples/p3-runtime/test_g6_2_owned_record_producer_abi.sh`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_producer_abi.rs`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_producer.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`

**Interfaces:**
- Consumes the exact WIT contract, canonical operation table, mode table, and
  cleanup state machine from the spec.
- Produces a component artifact that can be loaded by both the canonical ABI
  runner and the later compiler-generated gate; the runner reports
  `mode=...`, observed ticket seeds, result, pending polls, drop counts, and
  `table-empty=true`.

- [ ] **Step 1: Add the pinned WIT source.**

  Create the file with this exact content and final newline:

  ```wit
  package do:g6-2-owned-record-producer@0.1.0;

  interface types {
    enum error-code { io, pipe, invalid-mode }
    resource ticket {}
    record resource-entry { ticket: own<ticket> }
  }

  interface source {
    use types.{ticket};
    make-ticket: func(seed: u32) -> own<ticket>;
  }

  interface sink {
    use types.{error-code, resource-entry};
    consume-via-stream: async func(
      data: stream<resource-entry>
    ) -> result<_, error-code>;
  }

  world owned-record-producer {
    use types.{error-code};
    import source;
    import sink;
    export produce: async func(mode: u32) -> result<_, error-code>;
  }
  ```

  Run:

  ```bash
  test "$(sha256sum examples/p3-runtime/wit/g6-2-owned-record-producer.wit | awk '{print $1}')" = \
    6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace
  ```

- [ ] **Step 2: Add the canonical Core-WAT template.**

  Emit one module that imports the source `make-ticket`, the sink
  `[async-lower]consume-via-stream`, all seven stream operations, and
  `[resource-drop]ticket`; export the async-lifted `produce` entry and the
  completion callback required by `owned-record-producer`. The template must
  contain these machine-readable markers with the shown values:

  ```wat
  ;; [producer-record-byte-size] 4
  ;; [producer-record-ticket-offset] 0
  ;; [producer-stream-capacity] 1
  ;; [producer-ticket-seed] 111
  ;; [producer-record-transfer]
  ;; [producer-resource-drop-exactly-once]
  ;; [producer-child-before-parent-cleanup]
  ```

  The function creates one stream, creates one ticket, stores the handle at
  the record offset, performs no list allocation, and has explicit branches
  for pre-transfer cleanup, post-transfer cleanup, task completion, and
  cancellation. It must not contain `__arc_` symbols or a second stream write.

- [ ] **Step 3: Implement the Rust/Wasmtime oracle.**

  Define `Mode` with the exact values `Ready=0`, `Pending=1`,
  `SinkErrorBefore=2`, `SinkErrorAfter=3`, `CancelBeforeTransfer=4`,
  `CancelAfterTransfer=5`, `EarlyDropBeforeTransfer=6`,
  `EarlyDropAfterTransfer=7`, `Repeat=8`, and invalid `255`. Implement a
  `StreamConsumer<State>` whose `type Item = ResourceEntry`, not a list. The
  sink must:

  - return `Pending` exactly once for mode `1`;
  - complete `Err(io)` without lifting for mode `2`;
  - lift one entry then complete `Err(pipe)` for mode `3`;
  - hold pending for modes `4` and `6`, and accept then hold for modes `5`
    and `7`;
  - consume and complete `Ok` for mode `0`;
  - run mode `0` twice in the same `Store` for mode `8`;
  - reject `255` before creating a stream or ticket.

  Record `created`, `resource_drops`, `received`, `host_calls`,
  `pending_polls`, `stream_drops`, `future_drops`, `cancel_calls`, and the
  final `ResourceTable` state. Convert a transferred resource into host
  ownership exactly once before deleting it from the table; the guest-owned
  path must be dropped by the registered resource destructor.

  The one-line `g6_2_owned_record_producer.rs` wrapper must include the ABI
  runner source, matching the existing G6.2 runner layout.

- [ ] **Step 4: Register both Rust binaries.**

  Add these exact `Cargo.toml` entries without changing dependency versions:

  ```toml
  [[bin]]
  name = "do-p3-g6-2-owned-record-producer-abi"
  path = "src/bin/g6_2_owned_record_producer_abi.rs"

  [[bin]]
  name = "do-p3-g6-2-owned-record-producer"
  path = "src/bin/g6_2_owned_record_producer.rs"
  ```

- [ ] **Step 5: Add the canonical assembly gate.**

  `test_g6_2_owned_record_producer_abi.sh` must:

  1. require `wasm-tools --version` to report `1.255.0`;
  2. verify the WIT hash and required WIT names;
  3. parse the canonical WAT;
  4. run `component embed` with
     `--world owned-record-producer --features cm-async,cm-more-async-builtins`;
  5. run `component new --skip-validation` and `wasm-tools validate` with the
     same feature set;
  6. verify all seven marker names and values;
  7. execute the ABI binary for every mode except `repeat` through `repeat`,
     requiring the mode label, expected item observation, exact drop counts,
     and `table-empty=true`.

  Use an explicit project-local temporary root (`${TMPDIR:-$repo_root/.tmp/do-tmp}`)
  and remove only the script-owned temporary directory on exit.

- [ ] **Step 6: Run and commit the oracle.**

  Run:

  ```bash
  bash examples/p3-runtime/test_g6_2_owned_record_producer_abi.sh
  cargo check --locked --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml \
    --bin do-p3-g6-2-owned-record-producer-abi \
    --bin do-p3-g6-2-owned-record-producer
  git diff --check
  ```

  Expected: assembly, validation, all ten modes, and `cargo check` pass; no
  source file outside this task is staged. Commit with:

  ```bash
  git add examples/p3-runtime/wit/g6-2-owned-record-producer.wit \
    examples/p3-runtime/g6-2-owned-record-producer-canonical.wat \
    examples/p3-runtime/test_g6_2_owned_record_producer_abi.sh \
    examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_producer.rs \
    examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_producer_abi.rs \
    examples/p3-runtime/rust-host-runner/Cargo.toml
  git commit -m "Add G6.2 owned-record lifecycle oracle"
  ```

### Task 2: Add the manifest shape and hash-pinned registry row

**Files:**
- Modify: `src/build/p3_async_manifest.zig:LoweringShape`, shape declarations,
  `lowering_shape`, descriptor parser, and descriptor validation tests
- Modify: `src/build/p3_async_registry.json` (one descriptor row)

**Interfaces:**
- Consumes the canonical WIT hash and ABI facts proven by Task 1.
- Produces `OwnedRecordStreamProducerShape` with `element`, `stream_index`,
  `method`, `stream`, `record_layout`, and `producer` fields for the emitter.

- [ ] **Step 1: Add a manifest unit test that initially fails.**

  Add a test beside the existing producer descriptor tests that loads the
  registry after the row is present and asserts:

  ```zig
  try std.testing.expectEqualStrings(
      "6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace",
      descriptor.wit_sha256.?,
  );
  switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
      .owned_record_stream_producer => |shape| {
          try std.testing.expectEqualStrings("resource-entry", shape.element);
          try std.testing.expectEqual(@as(usize, 0), shape.stream_index);
          try std.testing.expectEqual(@as(u32, 4), shape.record_layout.byte_size);
          try std.testing.expectEqual(@as(u32, 0), shape.record_layout.fields[0].offset);
          try std.testing.expectEqual(@as(u32, 1), shape.producer.stream_capacity);
      },
      else => return error.TestUnexpectedResult,
  }
  ```

  Run `zig test src/build/p3_async_manifest.zig` and retain the failure until
  the shape and row are implemented.

- [ ] **Step 2: Add the shape type and dispatch variant.**

  Add this type next to the existing producer shapes and add the union variant:

  ```zig
  pub const OwnedRecordStreamProducerShape = struct {
      element: []const u8,
      stream_index: usize,
      method: StreamOperation,
      stream: StreamCanonical,
      record_layout: RecordLayout,
      producer: ProducerCanonical,
  };
  ```

  Add `owned_record_stream_producer: OwnedRecordStreamProducerShape` to
  `LoweringShape`. In `lowering_shape`, recognize only effect
  `record-resource-stream-producer` and return the exact validator result.

- [ ] **Step 3: Validate the descriptor fail-closed.**

  Implement `valid_owned_record_stream_producer_descriptor` with exact checks
  for locator/member/effect, one parameter `stream<resource-entry>`, result
  `Result<nil,error-code>`, the pinned hash and WIT metadata, canonical
  `(i32,i32)->i32` task-return facts, no `future`, `future_input`,
  `result_payload`, or error payload metadata, the four-byte single-ticket
  record, direct stream element, producer source module/name and `(i32)->i32`
  source ABI, `runtime_mode_param == "u32"`, terminal `task-return`, and
  capacity `1`. Validate all stream operation names and arities exactly:

  ```zig
  if (!valid_named_stream_operation(stream.new, "[stream-new-0]consume-via-stream", &.{}, &.{"i64"}) or
      !valid_named_stream_operation(stream.cancel_read, "[stream-cancel-read-0]consume-via-stream", &.{"i32"}, &.{"i32"}) or
      !valid_named_stream_operation(stream.cancel_write, "[stream-cancel-write-0]consume-via-stream", &.{"i32"}, &.{"i32"}) or
      !valid_named_stream_operation(stream.drop_readable, "[stream-drop-readable-0]consume-via-stream", &.{"i32"}, &.{}) or
      !valid_named_stream_operation(stream.drop_writable, "[stream-drop-writable-0]consume-via-stream", &.{"i32"}, &.{}) or
      !valid_named_stream_operation(stream.read, "[async-lower][stream-read-0]consume-via-stream", &.{"i32", "i32", "i32"}, &.{"i32"}) or
      !valid_named_stream_operation(stream.write, "[async-lower][stream-write-0]consume-via-stream", &.{"i32", "i32", "i32"}, &.{"i32"})) return null;
  ```

  Use the existing `valid_named_stream_operation` helper and return `null` on
  the first mismatch.

- [ ] **Step 4: Add the exact JSON row.**

  Add one row for `do:g6-2-owned-record-producer@0.1.0` with effect
  `record-resource-stream-producer`, params containing exactly
  `stream<resource-entry>`,
  result `Result<nil,error-code>`, the pinned hash, WIT package/interface/
  operation/world/parameter, the canonical core/completion facts, a
  `record_layout` containing only `ticket` (`i32`, offset `0`, own ticket drop),
  a `producer` containing source module
  `do:g6-2-owned-record-producer/source@0.1.0`, source import `make-ticket`,
  source core types `i32 -> i32`, resource drop `[resource-drop]ticket`,
  capacity `1`, terminal `task-return`, and `runtime_mode_param: "u32"`, plus
  the seven named stream operations. Do not add `list_resource_layout`.

- [ ] **Step 5: Add drift tests and run the manifest suite.**

  Add tests for a changed hash, changed direct element to
  `list<resource-entry>`, changed record byte size, changed ownership from
  `own` to `borrow`, changed sink import name, and changed completion mode.
  Each test must assert `lowering_shape(...) == null` while neighboring
  descriptors remain valid.

  Run:

  ```bash
  zig test src/build/p3_async_manifest.zig
  git diff --check
  ```

- [ ] **Step 6: Commit only manifest files.**

  ```bash
  git add src/build/p3_async_manifest.zig src/build/p3_async_registry.json
  git commit -m "Register G6.2 owned-record producer ABI"
  ```

### Task 3: Implement the isolated exact Do analyzer and emitter

**Files:**
- Create: `src/build/codegen_component_owned_record_stream_producer.zig`
- Create: `src/build/owned_record_stream_producer_template.wat`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/sema_imports.zig`

**Interfaces:**
- Consumes `OwnedRecordStreamProducerShape` from Task 2 and the exact Do
  source form in the spec.
- Produces `OwnedRecordStreamProducerPlan.analyze(tokens, registry)`,
  `emit_component_wat_for_tokens`, and `emit_component_wit` with error
  `UnsupportedP3OwnedRecordStreamProducer`.

- [ ] **Step 1: Add analyzer unit tests that initially fail.**

  In the new module, add a positive exact-source test plus negative tests for:
  `StreamWriter<[ResourceEntry]>`, `StreamWriter<OtherEntry>`, a `borrowed`
  record field, a second host binding, a changed resource path, an async
  `make_ticket`, a non-sentinel producer body, and an `@await` intrinsic. Each
  negative test must assert `error.UnsupportedP3OwnedRecordStreamProducer`.

- [ ] **Step 2: Implement exact token admission.**

  Define `OwnedRecordStreamProducerPlan` with descriptor, source/sink binding
  names, `Ticket`, `ResourceEntry`, `ProducerError`, root `produce`, and mode
  names. Reuse the existing lexer token helpers, but require the parameter
  tokens to be exactly `StreamWriter < ResourceEntry >` (no square brackets),
  the result tokens to be exactly `Result < nil , ProducerError >`, and the
  sentinel function body to be exactly `return Ok()`. Count top-level
  functions and reject every extra binding, declaration, token `async`, or
  intrinsic `@async`, `@await`, or `@cancel`.

- [ ] **Step 3: Implement internal record/resource validation.**

  Build a `wit_abi_types.AbiType.resource("ticket", .own)` and a record with
  one `ticket` field. Check the manifest record byte size/offset and the
  producer capacity before emitting. Return the dedicated unsupported error
  on any allocation, field, or canonical mismatch.

- [ ] **Step 4: Implement the hand-authored emitter.**

  Embed `owned_record_stream_producer_template.wat`, substitute only verified
  descriptor import names, record offset/size, capacity, seed, and cleanup
  markers, and return the template bytes. The emitted function must:

  ```text
  make stream -> make ticket(111) -> store ticket at record offset
  -> await one stream write -> clear guest slot iff transfer succeeded
  -> terminal result/error/cancel cleanup -> stream/task/frame cleanup
  ```

  Emit WIT from the pinned contract with world
  `owned-record-producer`; do not synthesize a list or add a public ownership
  declaration. Assert the WAT contains no `__arc_` marker.

- [ ] **Step 5: Wire target discovery and emission.**

  In `codegen_component_async.zig`, import the module, add target
  `owned_record_stream_producer`, dispatch it in both Component WAT and WIT
  switches, and add exact descriptor/binding discovery beside the existing
  producer routes. Preserve the existing ordering and map the module error to
  `UnsupportedP3AsyncComponent`.

  In `sema_imports.zig`, add only the new effect to the private known-effect
  predicate and add an exact `owned_record_stream_producer_signature_matches`
  branch. Do not change generic `StreamWriter<T>` or `@host_async_func`
  semantics.

- [ ] **Step 6: Run focused Zig tests and commit.**

  ```bash
  zig test src/build/codegen_component_owned_record_stream_producer.zig
  zig test src/build/codegen_component_async.zig
  zig test src/build/sema_imports.zig
  git diff --check
  ```

  Commit only the new emitter/template and the two routing files:

  ```bash
  git add src/build/codegen_component_owned_record_stream_producer.zig \
    src/build/owned_record_stream_producer_template.wat \
    src/build/codegen_component_async.zig src/build/sema_imports.zig
  git commit -m "Add exact owned-record producer lowering"
  ```

### Task 4: Lock the Do source boundary with positive and negative fixtures

**Files:**
- Create: `examples/p3-runtime/g6-2-owned-record-producer.do`
- Create: `src/build/test/compile_ok/691_g6_2_owned_record_producer_component.do`
- Create: `src/build/test/compile_ok/691_g6_2_owned_record_producer_component.expect`
- Create: `src/build/test/compile_err/691_g6_2_owned_record_producer_unregistered.do`
- Create: `src/build/test/compile_err/691_g6_2_owned_record_producer_unregistered.expect`
- Create: `src/build/test/compile_err/692_g6_2_owned_record_producer_list_element.do`
- Create: `src/build/test/compile_err/692_g6_2_owned_record_producer_list_element.expect`
- Create: `src/build/test/compile_err/693_g6_2_owned_record_producer_borrowed.do`
- Create: `src/build/test/compile_err/693_g6_2_owned_record_producer_borrowed.expect`
- Create: `src/build/test/compile_err/694_g6_2_owned_record_producer_extra_field.do`
- Create: `src/build/test/compile_err/694_g6_2_owned_record_producer_extra_field.expect`
- Create: `src/build/test/compile_err/695_g6_2_owned_record_producer_reordered_field.do`
- Create: `src/build/test/compile_err/695_g6_2_owned_record_producer_reordered_field.expect`
- Create: `src/build/test/compile_err/696_g6_2_owned_record_producer_body.do`
- Create: `src/build/test/compile_err/696_g6_2_owned_record_producer_body.expect`
- Create: `src/build/test/compile_err/697_g6_2_owned_record_producer_async_source.do`
- Create: `src/build/test/compile_err/697_g6_2_owned_record_producer_async_source.expect`
- Create: `src/build/test/compile_err/698_g6_2_owned_record_producer_second_sink.do`
- Create: `src/build/test/compile_err/698_g6_2_owned_record_producer_second_sink.expect`
- Create: `src/build/test/compile_err/699_g6_2_owned_record_producer_wrong_result.do`
- Create: `src/build/test/compile_err/699_g6_2_owned_record_producer_wrong_result.expect`

**Interfaces:**
- Consumes the analyzer and emitter from Task 3.
- Produces regression contracts that reject descriptor drift before WAT and
  accept exactly one positive source.

- [ ] **Step 1: Add the canonical positive source.**

  Create `examples/p3-runtime/g6-2-owned-record-producer.do` with the exact Do
  source in the spec. The compile fixture may contain the same source and its
  `.expect` must include:

  ```text
  # build-arg: --p3-async-component
  do:g6-2-owned-record-producer/sink@0.1.0
  (func (export "[async-lift]produce")
  [producer-record-transfer]
  [producer-resource-drop-exactly-once]
  ```

- [ ] **Step 2: Add negative fixtures.**

  Each `.expect` starts with `# build-arg: --p3-async-component`. Use
  `UnknownP3AsyncHostDescriptor` for the unregistered locator, use
  `P3AsyncHostSignatureMismatch` for a list element or borrowed field that is
  rejected at host signature validation, and use
  `UnsupportedP3OwnedRecordStreamProducer` for extra/reordered fields, body
  statements, async source, duplicate sink, or wrong result. Each `.do` file
  changes exactly one property from the positive source.

- [ ] **Step 3: Run focused fixture cases.**

  ```bash
  DO_BIN="$PWD/bin/do" ./src/build/test/run_tests.sh
  ```

  Before the full run, invoke the positive and each negative case directly
  with `bin/do build` and verify that positive output is non-empty while every
  negative command exits non-zero and contains only its expected diagnostic.

- [ ] **Step 4: Commit fixture contracts.**

  ```bash
  git add examples/p3-runtime/g6-2-owned-record-producer.do \
    src/build/test/compile_ok/691_g6_2_owned_record_producer_component.do \
    src/build/test/compile_ok/691_g6_2_owned_record_producer_component.expect \
    src/build/test/compile_err/691_g6_2_owned_record_producer_unregistered.* \
    src/build/test/compile_err/692_g6_2_owned_record_producer_list_element.* \
    src/build/test/compile_err/693_g6_2_owned_record_producer_borrowed.* \
    src/build/test/compile_err/694_g6_2_owned_record_producer_extra_field.* \
    src/build/test/compile_err/695_g6_2_owned_record_producer_reordered_field.* \
    src/build/test/compile_err/696_g6_2_owned_record_producer_body.* \
    src/build/test/compile_err/697_g6_2_owned_record_producer_async_source.* \
    src/build/test/compile_err/698_g6_2_owned_record_producer_second_sink.* \
    src/build/test/compile_err/699_g6_2_owned_record_producer_wrong_result.*
  git commit -m "Add owned-record producer admission fixtures"
  ```

### Task 5: Verify generated Component and all Rust/Wasmtime lifecycle paths

**Files:**
- Create: `examples/p3-runtime/test_do_g6_2_owned_record_producer.sh`
- Create: `examples/p3-runtime/test_rust_g6_2_owned_record_producer.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_producer_abi.rs`
  only if generated Component output needs a named export adapter

**Interfaces:**
- Consumes the positive Do source, private emitter, pinned WIT, and Task 1
  Rust oracle.
- Produces a generated Component that passes Core parse, WIT embed, Component
  validation, and all ready/pending/error/cancel/early-drop/repeat rows.

- [ ] **Step 1: Add the Do-to-Component gate.**

  `test_do_g6_2_owned_record_producer.sh` must compile the positive source with
  `--p3-async-component --p3-wit-output`, assert the package/world/direct
  stream signature, assert the record/capacity/transfer markers, reject
  neighboring producer package strings, parse Core-WAT, embed the generated
  WIT with world `owned-record-producer`, create the Component, and validate it
  using `cm-async,cm-more-async-builtins`. It must also verify the generated
  WIT hash equals the pinned value.

- [ ] **Step 2: Add the generated Rust/Wasmtime gate.**

  `test_rust_g6_2_owned_record_producer.sh` must compile the Do source,
  assemble and validate the generated Component, then run
  `do-p3-g6-2-owned-record-producer` for modes:

  ```text
  ready pending sink-error-before sink-error-after
  cancel-before-transfer cancel-after-transfer
  early-drop-before-transfer early-drop-after-transfer repeat invalid
  ```

  For each output require the exact expected observation from the spec,
  `resource-created=1`, `resource-drops=1` for every valid invocation,
  `stream-drops=1`, `future-drops=1`, the expected pending/cancel count, and
  `table-empty=true`. For `repeat`, require two creations and two drops in the
  same store. For `invalid`, require zero creations and zero drops.

- [ ] **Step 3: Run both gates with explicit caches.**

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache" \
    bash examples/p3-runtime/test_do_g6_2_owned_record_producer.sh
  TMPDIR="$PWD/.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache" \
    bash examples/p3-runtime/test_rust_g6_2_owned_record_producer.sh
  ```

- [ ] **Step 4: Commit generated gates.**

  ```bash
  git add examples/p3-runtime/test_do_g6_2_owned_record_producer.sh \
    examples/p3-runtime/test_rust_g6_2_owned_record_producer.sh \
    examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_producer_abi.rs
  git commit -m "Verify generated owned-record producer component"
  ```

### Task 6: Prove GC/ARC equivalence, update documentation, and run promotion gates

**Files:**
- Create: `examples/p3-runtime/test_g6_2_owned_record_producer_equivalence.sh`
- Modify: `examples/p3-runtime/README.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/master_plan.md`
- Modify: `doc/pending_blocked.md`
- Modify: `CHANGELOG.md`
- Modify: `src/build/test/check_gc_semantic_equivalence.sh` only to add the
  measured row, preserving all existing rows and counts

**Interfaces:**
- Consumes all green artifacts and runtime counters from Tasks 1–5.
- Produces a promoted private G6.2 row with explicit residual boundaries and
  a clean full-regression/release evidence record.

- [ ] **Step 1: Add the equivalence oracle.**

  Run the same ten mode rows through the canonical hand-authored Component and
  the compiler-generated Component. Compare result, received ticket seeds,
  pending polls, cancellation observation, stream/future drops, resource
  creations/drops, and final table emptiness. Require a line in the form:

  ```text
  GC/ARC direct owned-record producer equivalence passed modes=10 resources=1/1 drops=1/1 table-empty=true
  ```

  A mismatch exits non-zero and leaves the migration row unpromoted.

- [ ] **Step 2: Add the user-facing probe README entry.**

  Document the three commands
  `test_g6_2_owned_record_producer_abi.sh`,
  `test_do_g6_2_owned_record_producer.sh`, and
  `test_rust_g6_2_owned_record_producer.sh`, the direct-record-only scope, the
  ten modes, and the exactly-once cleanup invariant. State explicitly that
  public ownership syntax and generic producer lowering remain unavailable.

- [ ] **Step 3: Update status documents from evidence.**

  Add one dated entry to `doc/roadmap_status.md` and matching concise updates
  to `doc/start_here.md`, `doc/master_plan.md`, and `doc/pending_blocked.md`.
  Record the WIT hash, record layout, stream capacity, tool versions, mode
  matrix, exact resource/table counters, and the unchanged pending boundaries.
  Remove no unrelated pending row and do not claim full G6.2 or full GC
  cutover.

- [ ] **Step 4: Add a changelog entry.**

  Add the date, descriptor, selected direct-record scope, verification commands,
  and the fact that the route is private and fail-closed. Do not describe this
  as public `own<T>`/`borrow<T>`/`ref<T>` support.

- [ ] **Step 5: Run the complete verification set.**

  ```bash
  cd src && zig test main.zig
  cd ..
  TMPDIR="$PWD/.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache" \
    ./src/build/test/run_tests.sh
  ./examples/p3-runtime/test_g6_2_owned_record_producer_abi.sh
  ./examples/p3-runtime/test_do_g6_2_owned_record_producer.sh
  ./examples/p3-runtime/test_rust_g6_2_owned_record_producer.sh
  ./examples/p3-runtime/test_g6_2_owned_record_producer_equivalence.sh
  ./src/build/test/check_gc_semantic_equivalence.sh
  ./src/build/test/run_release_smoke.sh
  git diff --check
  ```

  Expected: the existing baseline remains green, every new gate is green,
  `ResourceTable` is empty for every terminal, and no ARC symbol appears in
  generated output. If any command fails, preserve its output, stop promotion,
  and keep the descriptor private.

- [ ] **Step 6: Commit the evidence and documentation.**

  Stage only the files listed by this task and commit:

  ```bash
  git add examples/p3-runtime/test_g6_2_owned_record_producer_equivalence.sh \
    examples/p3-runtime/README.md doc/roadmap_status.md doc/start_here.md \
    doc/master_plan.md doc/pending_blocked.md CHANGELOG.md \
    src/build/test/check_gc_semantic_equivalence.sh
  git commit -m "Promote G6.2 direct owned-record producer evidence"
  ```

## Plan self-review

- Spec coverage: the WIT contract and hash are covered by Task 1; manifest and
  canonical ABI by Task 2; exact Do admission and fail-closed negative cases by
  Tasks 3–4; Component and Rust lifecycle rows by Task 5; equivalence,
  documentation, and release gates by Task 6.
- Scope: every task stays on one private direct-record descriptor; lists,
  variants, borrowed payloads, public ownership syntax, arbitrary expressions,
  and unrestricted async lowering remain explicitly outside the route.
- Type consistency: the manifest uses `OwnedRecordStreamProducerShape`; the
  emitter consumes that shape; the Do sink is
  `StreamWriter<ResourceEntry>`; the WIT sink is `stream<resource-entry>`; the
  Rust consumer item is `ResourceEntry`; the record field is one owned
  `ticket` handle.
- Boundary consistency: transfer occurs only on successful write; all
  pre-transfer paths use guest cleanup, all post-transfer paths use host
  cleanup, and cancellation never implies rollback.
- Verification consistency: canonical assembly precedes manifest admission;
  generated Component validation precedes runtime promotion; full regression,
  equivalence, and release smoke are the final gates.
