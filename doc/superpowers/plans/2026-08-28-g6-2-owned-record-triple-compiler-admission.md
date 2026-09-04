# G6.2 ResourceTriple Compiler Admission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:executing-plans` (or `superpowers:subagent-driven-development`)
> to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** Admit exactly the measured fixed `ResourceTriple` producer to the
private `--p3-async-component` compiler route, with fail-closed descriptor and
source-shape validation plus canonical/generated Component and lifecycle
evidence.

**Architecture:** Add one manifest descriptor and one dedicated lowering module
for the three top-level owned `ticket` fields. The module emits the already
measured canonical WAT shape and generated WIT only after matching the pinned
descriptor and the complete source topology; it does not generalize the pair
route or introduce a public ownership type. Compiler output is admitted only
after negative drift fixtures, Component validation, and the ten-mode
Rust/Wasmtime cleanup matrix pass.

**Tech Stack:** Zig `0.16.0`, `wasm-tools 1.255.0`, Rust/Cargo `1.97.1`,
Wasmtime `47.0.2`, Bash gates, and the existing `do` regression harness.

**Spec:** `doc/superpowers/specs/2026-08-28-g6-2-owned-record-triple-producer-design.md`

## Global Constraints

- The only new descriptor is `do:g6-2-owned-record-triple-producer@0.1.0` /
  member `consume-via-stream`, with WIT SHA-256
  `73fd57dc8f34f13023b48f2b82e439b212eab52192886f0d07a37d86e63658b1`.
- The accepted stream element is exactly `resource-triple` with three
  `own<ticket>` fields `left`, `middle`, `right`, 12-byte size, alignment 4,
  offsets `0/4/8`, and stream capacity `1`.
- The source call is exactly `(i32) -> (i32)` and the producer export accepts
  `(mode,left-seed,middle-seed,right-seed)` as four `u32` words.
- Presence bits are independent of handle values: `left=1`, `middle=2`,
  `right=4`, `transferred=8`; transfer is atomic after a complete stream write;
  pre-transfer cleanup is `right -> middle -> left`.
- The route remains private and opt-in behind `--p3-async-component`; do not
  add public `own<T>`, `borrow<T>`, `ref<T>`, `Option`, or `Result` syntax.
- Do not admit generic producers, arbitrary producer expressions, nested
  producers, borrowed/list/variant payloads, general filesystem async, or a
  full GC cutover.
- Existing direct, static-pair, parameterized-pair, list, scalar, variant, and
  filesystem descriptors and their WIT hashes must remain byte-compatible.
- Keep the migration inventory at `complete_rows=15 pending_rows=15` with its
  deliberate exit status `1`; this route is not a GC semantic-equivalence row.
- Use project-local temporary paths when needed:
  `TMPDIR="$PWD/.tmp/do-tmp"`, `ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache"`,
  and `ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache"`.
- Stage only this route, its tests, and synchronized documentation. Do not push
  from this plan without a separate explicit delivery request.

## File Map

| Path | Responsibility |
| --- | --- |
| `src/build/p3_async_manifest.zig` | Parse, validate, expose, and test the exact triple descriptor shape. |
| `src/build/p3_async_registry.json` | Store the hash-pinned canonical descriptor and ABI facts. |
| `src/build/owned_record_triple_stream_producer_template.wat` | Checked-in compiler template, byte-identical to the measured canonical WAT. |
| `src/build/codegen_component_owned_record_triple_stream_producer.zig` | Triple source matcher, internal layout checks, WAT/WIT emission, and unit tests. |
| `src/build/codegen_component_async.zig` | Target enum, classification, dispatch, and dispatch tests. |
| `src/build/test/compile_ok/712_g6_2_owned_record_triple_component.do` | Positive compiler fixture. |
| `src/build/test/compile_ok/712_g6_2_owned_record_triple_component.expect` | Positive fixture build flag and stable output markers. |
| `src/build/test/compile_err/712_g6_2_triple_wrong_arity.do` through `724_g6_2_triple_old_descriptor.do` | One-contract-fact-per-file fail-closed source mutations. |
| `src/build/test/compile_err/*.expect` for the above | Stable diagnostic assertions. |
| `examples/p3-runtime/g6-2-owned-record-triple-producer.do` | Compiler source consumed by the black-box Component gates. |
| `examples/p3-runtime/test_do_g6_2_owned_record_triple_producer.sh` | Positive Do/WIT/WAT/Component admission gate. |
| `examples/p3-runtime/test_do_g6_2_owned_record_triple_producer_negative.sh` | Negative source-shape and descriptor gate. |
| `examples/p3-runtime/test_rust_g6_2_owned_record_triple_producer.sh` | Generated Component Rust/Wasmtime lifecycle gate. |
| `examples/p3-runtime/test_g6_2_owned_record_triple_producer_equivalence.sh` | Canonical/generated WAT and ten-mode observation parity. |
| `doc/start_here.md`, `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/master_plan.md`, `examples/p3-runtime/README.md`, `CHANGELOG.md` | Record private compiler admission and preserve remaining blockers. |

### Task 1: Add the hash-pinned manifest descriptor

**Files:**

- Modify: `src/build/p3_async_manifest.zig` (`LoweringShape`, shape structs,
  `lowering_shape`, descriptor validator, and manifest tests).
- Modify: `src/build/p3_async_registry.json` (one descriptor entry only).
- Test: `src/build/p3_async_manifest.zig`.

**Interfaces:**

- Add `OwnedRecordTripleStreamProducerShape` with fields
  `element`, `stream_index`, `method`, `stream`, `record_layout`, and
  `producer`, matching the existing dedicated producer-shape records.
- Add the union case
  `.record_resource_triple_stream_producer` and return it only for effect
  `record-resource-triple-stream-producer`.
- The validator must require locator
  `do:g6-2-owned-record-triple-producer@0.1.0`, member
  `consume-via-stream`, parameter `stream<resource-triple>`, result
  `Result<nil,error-code>`, the pinned hash, WIT package/interface/operation/
  world/parameter, and the exact canonical imports.

- [ ] **Step 1: Add the descriptor entry with exact facts.**

  Insert one JSON object next to the existing owned-record producer entries:

  ```json
  {
    "locator": "do:g6-2-owned-record-triple-producer@0.1.0",
    "member": "consume-via-stream",
    "effect": "record-resource-triple-stream-producer",
    "params": ["stream<resource-triple>"],
    "result": "Result<nil,error-code>",
    "resource": null,
    "wit_sha256": "73fd57dc8f34f13023b48f2b82e439b212eab52192886f0d07a37d86e63658b1",
    "canonical": {
      "core_params": ["i32", "i32"],
      "core_results": ["i32"],
      "completion_params": ["i32", "i32"],
      "completion": "task-return",
      "async_import_module": "do:g6-2-owned-record-triple-producer/sink@0.1.0",
      "async_import_name": "[async-lower]consume-via-stream",
      "record_layout": {
        "name": "resource-triple",
        "byte_size": 12,
        "fields": [
          {"name": "left", "core_type": "i32", "offset": 0},
          {"name": "middle", "core_type": "i32", "offset": 4},
          {"name": "right", "core_type": "i32", "offset": 8}
        ],
        "source_fields": [
          {"name": "left", "source_type": "ticket", "storage": ["left"], "ownership": "own", "resource": "ticket", "drop_import": "[resource-drop]ticket"},
          {"name": "middle", "source_type": "ticket", "storage": ["middle"], "ownership": "own", "resource": "ticket", "drop_import": "[resource-drop]ticket"},
          {"name": "right", "source_type": "ticket", "storage": ["right"], "ownership": "own", "resource": "ticket", "drop_import": "[resource-drop]ticket"}
        ]
      },
      "producer": {
        "source_module": "do:g6-2-owned-record-triple-producer/source@0.1.0",
        "source_import_name": "make-ticket",
        "source_core_params": ["i32"],
        "source_core_results": ["i32"],
        "resource_drop_import": "[resource-drop]ticket",
        "stream_capacity": 1,
        "terminal": "task-return",
        "runtime_mode_param": "u32"
      },
      "stream": {
        "element": "resource-triple",
        "new": {"import_name": "[stream-new-0]consume-via-stream", "core_params": [], "core_results": ["i64"]},
        "cancel_read": {"import_name": "[stream-cancel-read-0]consume-via-stream", "core_params": ["i32"], "core_results": ["i32"]},
        "cancel_write": {"import_name": "[stream-cancel-write-0]consume-via-stream", "core_params": ["i32"], "core_results": ["i32"]},
        "drop_readable": {"import_name": "[stream-drop-readable-0]consume-via-stream", "core_params": ["i32"], "core_results": []},
        "drop_writable": {"import_name": "[stream-drop-writable-0]consume-via-stream", "core_params": ["i32"], "core_results": []},
        "read": {"import_name": "[async-lower][stream-read-0]consume-via-stream", "core_params": ["i32", "i32", "i32"], "core_results": ["i32"]},
        "write": {"import_name": "[async-lower][stream-write-0]consume-via-stream", "core_params": ["i32", "i32", "i32"], "core_results": ["i32"]}
      }
    },
    "wit": {
      "package": "do:g6-2-owned-record-triple-producer@0.1.0",
      "interface": "sink",
      "operation": "consume-via-stream",
      "world": "owned-record-triple-producer",
      "parameter": "data"
    }
  }
  ```

- [ ] **Step 2: Add exact shape validation.**

  Require all of the following before returning the shape: record name
  `resource-triple`; three fields with core types/offsets
  `(left,i32,0)`, `(middle,i32,4)`, `(right,i32,8)`; three source fields in the
  same order with `ownership=own`, `resource=ticket`, and the same drop import;
  no `result_payload`, `result_area_payload`, `future_owned`, error variants,
  list layout, scalar-list producer, parameterized producer, future, variant,
  or ticket-drop side channel; and all seven stream operation signatures shown
  above. The producer must have no runtime count, batch count, or batch lengths.

- [ ] **Step 3: Add drift tests and run them.**

  Add tests that clone the registered descriptor and independently corrupt the
  WIT hash, package/world, element type, record byte size, middle offset, right
  offset, field count, ownership, source module, stream write import, and stream
  operation signature. Each mutation must make `lowering_shape` return `null`.

  Run:

  ```bash
  (cd src && zig test build/p3_async_manifest.zig)
  ```

  Expected: all manifest tests pass, the new shape is observable only for the
  exact descriptor, and the existing pair/list descriptors still classify as
  their original shapes.

- [ ] **Step 4: Commit the isolated manifest change.**

  ```bash
  git add src/build/p3_async_manifest.zig src/build/p3_async_registry.json
  git commit -m "feat: register fixed resource triple producer descriptor"
  ```

### Task 2: Implement the closed triple lowering and dispatch

**Files:**

- Create: `src/build/owned_record_triple_stream_producer_template.wat` by
  copying the checked-in canonical WAT
  `examples/p3-runtime/g6-2-owned-record-triple-producer-canonical.wat`.
- Create: `src/build/codegen_component_owned_record_triple_stream_producer.zig`.
- Modify: `src/build/codegen_component_async.zig`.
- Test: the new module and `src/build/codegen_component_async.zig`.

**Interfaces:**

```zig
pub const ProducerError = error{UnsupportedP3OwnedRecordTripleStreamProducer};

pub const OwnedRecordTripleStreamProducerPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    source_host_name: []const u8,
    sink_host_name: []const u8,
    ticket_type_name: []const u8,
    record_type_name: []const u8,
    error_type_name: []const u8,
    root_name: []const u8,
    mode_name: []const u8,
    layout: p3_async_manifest.RecordLayout,
    producer: p3_async_manifest.ProducerCanonical,
};

pub fn analyze(tokens: []const lexer.Token,
    registry: p3_async_manifest.Registry) ProducerError!OwnedRecordTripleStreamProducerPlan;
pub fn emit_component_wat(allocator: std.mem.Allocator,
    plan: OwnedRecordTripleStreamProducerPlan) ![]u8;
pub fn emit_component_wat_for_tokens(allocator: std.mem.Allocator,
    tokens: []const lexer.Token) ![]u8;
pub fn emit_component_wit(allocator: std.mem.Allocator,
    plan: OwnedRecordTripleStreamProducerPlan) ![]u8;
pub fn emit_component_wit_for_tokens(allocator: std.mem.Allocator,
    tokens: []const lexer.Token) ![]u8;
```

- [ ] **Step 1: Add and verify the template.**

  Copy the canonical file byte-for-byte, then run:

  ```bash
  cmp examples/p3-runtime/g6-2-owned-record-triple-producer-canonical.wat \
    src/build/owned_record_triple_stream_producer_template.wat
  if grep -nE '__arc_|ref\.null|struct\.new|array\.new' \
    src/build/owned_record_triple_stream_producer_template.wat; then exit 1; fi
  ```

  Expected: `cmp` succeeds, no forbidden ARC or Wasm-GC-reference marker is
  present, and the markers are exactly `[producer-record-byte-size] 12`,
  offsets `0/4/8`, `[producer-input-word-count] 4`, and seed order
  `left then middle then right`.

- [ ] **Step 2: Implement the exact source matcher.**

  `analyze` must accept exactly two host bindings named `make_ticket` and
  `consume`; the source locator/member/signature must be
  `do:g6-2-owned-record-triple-producer/source@0.1.0`, `make-ticket`,
  `(u32) -> Ticket`; the sink locator/member/signature must be the descriptor,
  `consume-via-stream`, and
  `(StreamWriter<ResourceTriple>) -> Result<nil, ProducerError>`.

  Require one exact `Ticket` resource at
  `do:g6-2-owned-record-triple-producer/source/ticket`, one `ResourceTriple`
  record with exactly the ordered fields `.left Ticket`, `.middle Ticket`,
  `.right Ticket`, one `ProducerError error = Io | Pipe | InvalidMode`, one
  `produce` and one empty `start`. Require the producer signature
  `produce(mode u32, left_seed u32, middle_seed u32, right_seed u32) ->
  Result<nil, ProducerError>` and reject every `async` token and `@async`,
  `@await`, or `@cancel` intrinsic. Reject extra top-level declarations,
  additional host bindings, borrowed fields, list/variant fields, reordered
  fields, and any non-empty producer body other than `return Ok()`.

- [ ] **Step 3: Validate the internal ABI and ownership plan.**

  Construct `AbiType.resource(..., .own)` and a three-field record, then use
  `wit_abi_layout.LayoutPlan.record` to assert byte size `12`, alignment `4`,
  field offsets `0/4/8`, and three owned source fields. Validate the stream
  operations and `ProducerCanonical` facts from the descriptor before emitting.
  Preserve the independent mask invariant and reject a plan if any source field
  is not `own` or any field/drop order differs.

- [ ] **Step 4: Implement WAT/WIT emission.**

  `emit_component_wat` returns the template only after validation and rejects
  output containing `__arc_`. `emit_component_wit` returns exactly:

  ```wit
  package do:g6-2-owned-record-triple-producer@0.1.0;

  interface types {
    enum error-code { io, pipe, invalid-mode }
    resource ticket {}
    record resource-triple {
      left: own<ticket>,
      middle: own<ticket>,
      right: own<ticket>,
    }
  }

  interface source {
    use types.{ticket};
    make-ticket: func(seed: u32) -> own<ticket>;
  }

  interface sink {
    use types.{error-code, resource-triple};
    consume-via-stream: async func(
      data: stream<resource-triple>
    ) -> result<_, error-code>;
  }

  world owned-record-triple-producer {
    use types.{error-code};
    import source;
    import sink;
    export produce: async func(
      mode: u32,
      left-seed: u32,
      middle-seed: u32,
      right-seed: u32
    ) -> result<_, error-code>;
  }
  ```

- [ ] **Step 5: Wire the target dispatcher.**

  Add target `owned_record_triple_stream_producer`, import the new module, and
  route both `emit_component_wat` and `emit_component_wit` through it. In
  `target_for_tokens_with_graph`, classify the triple only after the exact
  descriptor-backed matcher succeeds. Map only
  `UnsupportedP3OwnedRecordTripleStreamProducer` to
  `UnsupportedP3AsyncComponent`; do not catch it as a generic pair/list route.

- [ ] **Step 6: Add unit and dispatch tests.**

  Test the exact positive source, output markers, WIT world, no ARC marker, and
  `Target.owned_record_triple_stream_producer`. Test mutations for a two-field
  record, borrowed middle field, reordered fields, a fifth field, wrong seed
  type, wrong seed order, an async intrinsic, and an unregistered descriptor;
  every mutation must return the dedicated producer error before WAT emission.

  Run:

  ```bash
  (cd src && zig test build/codegen_component_owned_record_triple_stream_producer.zig)
  (cd src && zig test build/codegen_component_async.zig)
  ```

  Expected: the new unit tests pass and all existing dispatcher tests remain
  green with no change to pair or list target selection.

- [ ] **Step 7: Commit the lowering unit.**

  ```bash
  git add src/build/owned_record_triple_stream_producer_template.wat \
    src/build/codegen_component_owned_record_triple_stream_producer.zig \
    src/build/codegen_component_async.zig
  git commit -m "feat: add private resource triple component lowering"
  ```

### Task 3: Add positive and negative compiler admission fixtures

**Files:**

- Create: `examples/p3-runtime/g6-2-owned-record-triple-producer.do`.
- Create: `examples/p3-runtime/test_do_g6_2_owned_record_triple_producer.sh`.
- Create: `examples/p3-runtime/test_do_g6_2_owned_record_triple_producer_negative.sh`.
- Create: `src/build/test/compile_ok/712_g6_2_owned_record_triple_component.do` and
  `.expect`.
- Create: `src/build/test/compile_err/712_g6_2_triple_wrong_arity.do` through
  `724_g6_2_triple_old_descriptor.do`, with matching `.expect` files.

**Interfaces:** The positive source is the only source topology admitted by
Task 2. Shape mutations must fail before WAT; the wrong marker must report
`InvalidImportDecl`; an unregistered locator must report
`UnknownP3AsyncHostDescriptor`.

- [ ] **Step 1: Add the exact positive source.**

  Use this source in both the example and compile fixture:

  ```do
  make_ticket = @host_func("do:g6-2-owned-record-triple-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
  consume = @host_async_func("do:g6-2-owned-record-triple-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceTriple>) -> Result<nil, ProducerError>)
  Ticket = @wasi_resource("do:g6-2-owned-record-triple-producer/source/ticket", { .id i64 })
  ResourceTriple {
      .left Ticket
      .middle Ticket
      .right Ticket
  }
  ProducerError error = Io | Pipe | InvalidMode

  produce(mode u32, left_seed u32, middle_seed u32, right_seed u32) -> Result<nil, ProducerError> {
      return Ok()
  }

  start() {}
  ```

- [ ] **Step 2: Add the thirteen one-fact negative fixtures.**

  Each file starts from the positive source and changes exactly the indicated
  fragment:

  | File | Exact mutation | Expected diagnostic |
  | --- | --- | --- |
  | `712_g6_2_triple_wrong_arity` | Remove `right_seed u32` from `produce`. | `UnsupportedP3AsyncComponent` |
  | `713_g6_2_triple_seed_order` | Change the parameter order to `right_seed u32, middle_seed u32`. | `UnsupportedP3AsyncComponent` |
  | `714_g6_2_triple_non_u32_seed` | Change `middle_seed u32` to `middle_seed u64`. | `UnsupportedP3AsyncComponent` |
  | `715_g6_2_triple_renamed_source` | Change `make_ticket` to `make`. | `UnsupportedP3AsyncComponent` |
  | `716_g6_2_triple_renamed_sink` | Change `consume` to `consume_stream`. | `UnsupportedP3AsyncComponent` |
  | `717_g6_2_triple_borrowed_field` | Change `.middle Ticket` to `.middle borrow<Ticket>`. | `UnsupportedP3AsyncComponent` |
  | `718_g6_2_triple_extra_field` | Add `.extra Ticket` after `.right Ticket`. | `UnsupportedP3AsyncComponent` |
  | `719_g6_2_triple_reordered_field` | Swap `.middle Ticket` and `.right Ticket`. | `UnsupportedP3AsyncComponent` |
  | `720_g6_2_triple_wrong_marker` | Change `@host_async_func` on `consume` to `@host_func`. | `InvalidImportDecl` |
  | `721_g6_2_triple_wrong_result` | Change `Result<nil, ProducerError>` on `produce` to `Result<u32, ProducerError>`. | `UnsupportedP3AsyncComponent` |
  | `722_g6_2_triple_async_intrinsic` | Replace the `return Ok()` body with `pending Future<Ticket> = @async(make_ticket(left_seed)); _ = @await(pending); return Ok()`. | `UnsupportedP3AsyncComponent` |
  | `723_g6_2_triple_unregistered_descriptor` | Change the sink locator to `do:g6-2-owned-record-triple-unknown@0.1.0`. | `UnknownP3AsyncHostDescriptor` |
  | `724_g6_2_triple_old_descriptor` | Change the sink locator to `do:g6-2-owned-record-pair-producer@0.1.0`. | `UnsupportedP3AsyncComponent` |

- [ ] **Step 3: Add stable compile expectations.**

  The positive `.expect` contains only the build flag, the sink instance,
  `(func (export "[async-lift]produce")`, and markers
  `[producer-record-byte-size] 12`, `[producer-record-middle-offset] 4`,
  `[producer-record-right-offset] 8`, `[producer-input-word-count] 4`,
  `[producer-record-transfer]`, and
  `[producer-resource-drop-exactly-once]`. Each negative `.expect` contains
  `# build-arg: --p3-async-component` and exactly its diagnostic substring.

- [ ] **Step 4: Implement and run the Do gates.**

  The positive shell gate must build with
  `--p3-async-component --p3-wit-output`, compare generated WIT byte-for-byte
  with `examples/p3-runtime/wit/g6-2-owned-record-triple-producer.wit`, verify
  the pinned hash and all identifiers, reject neighboring descriptor names and
  `__arc_`, parse the WAT, embed the WIT using world
  `owned-record-triple-producer` and features `cm-async,cm-more-async-builtins`,
  create the Component with `--skip-validation`, and validate it. The negative
  gate builds every file with the same flag and checks the exact diagnostic
  table above.

  Run:

  ```bash
  bash -n examples/p3-runtime/test_do_g6_2_owned_record_triple_producer.sh \
    examples/p3-runtime/test_do_g6_2_owned_record_triple_producer_negative.sh
  bash examples/p3-runtime/test_do_g6_2_owned_record_triple_producer.sh
  bash examples/p3-runtime/test_do_g6_2_owned_record_triple_producer_negative.sh
  ```

  Expected: positive assembly/validation succeeds and all thirteen negative
  cases fail closed with no generated Component.

- [ ] **Step 5: Commit the compiler fixtures.**

  ```bash
  git add examples/p3-runtime/g6-2-owned-record-triple-producer.do \
    examples/p3-runtime/test_do_g6_2_owned_record_triple_producer.sh \
    examples/p3-runtime/test_do_g6_2_owned_record_triple_producer_negative.sh \
    src/build/test/compile_ok/712_g6_2_owned_record_triple_component.* \
    src/build/test/compile_err/712_g6_2_triple_* \
    src/build/test/compile_err/713_g6_2_triple_* \
    src/build/test/compile_err/714_g6_2_triple_* \
    src/build/test/compile_err/715_g6_2_triple_* \
    src/build/test/compile_err/716_g6_2_triple_* \
    src/build/test/compile_err/717_g6_2_triple_* \
    src/build/test/compile_err/718_g6_2_triple_* \
    src/build/test/compile_err/719_g6_2_triple_* \
    src/build/test/compile_err/720_g6_2_triple_* \
    src/build/test/compile_err/721_g6_2_triple_* \
    src/build/test/compile_err/722_g6_2_triple_* \
    src/build/test/compile_err/723_g6_2_triple_* \
    src/build/test/compile_err/724_g6_2_triple_*
  git commit -m "test: gate resource triple compiler admission"
  ```

### Task 4: Prove generated lifecycle and canonical parity

**Files:**

- Modify: `examples/p3-runtime/test_rust_g6_2_owned_record_triple_producer.sh`
  so it builds and runs the generated Component while retaining the canonical
  ABI gate as a separate prerequisite.
- Create: `examples/p3-runtime/test_g6_2_owned_record_triple_producer_equivalence.sh`.
- Test: existing Rust binaries
  `do-p3-g6-2-owned-record-triple-producer-abi` and
  `do-p3-g6-2-owned-record-triple-producer` in
  `examples/p3-runtime/rust-host-runner/`.

**Interfaces:** The scripts consume the positive source, pinned WIT, canonical
WAT, generated WAT/WIT, and the existing two Rust runners. They must compare
stable observations, not only process exit status.

- [ ] **Step 1: Build the generated Component.**

  Use `bin/do build` with the positive source, produce WAT/WIT in a temporary
  directory, assert the WIT hash, assemble with the exact world and async
  features, and run `wasm-tools validate --features cm-async,cm-more-async-builtins`.
  Require `cmp generated.wat examples/p3-runtime/g6-2-owned-record-triple-producer-canonical.wat`.

- [ ] **Step 2: Run all ten lifecycle modes with explicit inputs.**

  Invoke the generated component with the existing ABI runner using these
  rows, preserving the exact expected seed order and result:

  | Mode | `(left,middle,right)` | Received | Result |
  | --- | --- | --- | --- |
  | `ready` | `(111,222,333)` | `[111,222,333]` | `Ok(())` |
  | `pending` | `(0,4294967295,1)` | `[0,4294967295,1]` | `Ok(())` |
  | `sink-error-before` | `(444,555,666)` | `[]` | `Err(Pipe)` |
  | `sink-error-after` | `(777,888,999)` | `[777,888,999]` | `Err(Pipe)` |
  | `cancel-before-transfer` | `(1001,1002,1003)` | `[]` | `Err(Pipe)` |
  | `cancel-after-transfer` | `(2001,2002,2003)` | `[2001,2002,2003]` | `Err(Pipe)` |
  | `early-drop-before-transfer` | `(3001,3002,3003)` | `[]` | `Err(Pipe)` |
  | `early-drop-after-transfer` | `(4001,4002,4003)` | `[4001,4002,4003]` | `Err(Pipe)` |
  | `repeat` | `(111,222,333)` then `(444,555,666)` | `[111,222,333,444,555,666]` | `Ok(())` |
  | `invalid` | `(9,10,11)` | `[]` | `Err(InvalidMode)` |

  For each valid single invocation require `resource-created=3`,
  `resource-drops=3`, one host callback, one stream drop, one future drop, and
  `table-empty=true`; `pending` has two polls; before-transfer cancellation and
  early-drop have zero polls; after-transfer cancellation and early-drop have
  one poll. Each cancel/early-drop row requires one `cancel-calls`, one
  `pending-future-drops`, and zero future completions. `repeat` requires `6/6`
  resources/drops, two callbacks, two stream/future drops, and two completions.
  `invalid` requires all allocation, callback, poll, cancellation, drop, and
  completion counters to be zero.

- [ ] **Step 3: Compare canonical and generated observations.**

  Assemble both Components with the same pinned WIT, run the ten rows through
  `do-p3-g6-2-owned-record-triple-producer-abi`, and `diff -u` each canonical
  output against its generated output. The equivalence gate must also check the
  layout line `record-offset:64 record-byte-size:12 left-offset:0
  middle-offset:4 right-offset:8 stream-capacity:1` and
  `table-empty=true`.

- [ ] **Step 4: Run the Rust/Wasmtime gates.**

  ```bash
  bash examples/p3-runtime/test_g6_2_owned_record_triple_producer_abi.sh
  bash examples/p3-runtime/test_rust_g6_2_owned_record_triple_producer.sh
  bash examples/p3-runtime/test_g6_2_owned_record_triple_producer_equivalence.sh
  ```

  Expected: canonical ABI and generated lifecycle both pass all ten rows, and
  the parity gate reports no observation difference.

- [ ] **Step 5: Commit the lifecycle gates.**

  ```bash
  git add examples/p3-runtime/test_rust_g6_2_owned_record_triple_producer.sh \
    examples/p3-runtime/test_g6_2_owned_record_triple_producer_equivalence.sh
  git commit -m "test: verify generated resource triple lifecycle"
  ```

### Task 5: Run the release baseline and synchronize status

**Files:**

- Modify only current-state sections of `doc/start_here.md`,
  `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/master_plan.md`,
  `examples/p3-runtime/README.md`, and `CHANGELOG.md`.
- Test: full compiler, release, inventory, and all triple gates.

- [ ] **Step 1: Run focused and full verification.**

  ```bash
  (cd src && zig test main.zig)
  TMPDIR="$PWD/.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache" \
  NODE_BIN="$(command -v bun)" WASM_TOOLS="$(command -v wasm-tools)" \
    ./src/build/test/run_tests.sh
  (cd src && zig build -Doptimize=ReleaseSmall)
  bash src/build/test/run_release_smoke.sh
  bash -n examples/p3-runtime/test_g6_2_owned_record_triple_producer_abi.sh \
    examples/p3-runtime/test_rust_g6_2_owned_record_triple_producer.sh \
    examples/p3-runtime/test_g6_2_owned_record_triple_producer_equivalence.sh
  set +e
  bash src/build/test/check_gc_migration_inventory.sh
  inventory_status=$?
  set -e
  test "$inventory_status" -eq 1
  ```

  The inventory command is expected to print
  `summary complete_rows=15 pending_rows=15` and exit `1`; capture that status
  explicitly and do not turn it into a green result. All compiler/release gates
  must have zero failures, and the triple gates must use `wasm-tools 1.255.0`.

- [ ] **Step 2: Synchronize documentation from fresh output.**

  Record the descriptor/hash, exact 12-byte layout and offsets, four-word input,
  private compiler admission, negative fixture count, generated/canonical
  parity, ten-mode cleanup observations, and the actual current regression
  counts. State explicitly that generic producer/resource lowering, arbitrary
  expressions, borrowed/list/variant payloads, public ownership syntax, general
  filesystem async, and full GC cutover remain pending. Do not add the triple to
  the 15-row ARC/GC inventory or claim full WASI completion.

- [ ] **Step 3: Review scope and staged paths.**

  ```bash
  git diff --check
  git status --short
  git diff --stat
  rg -n 'own<T>|borrow<T>|ref<T>|generic producer|complete_rows=15 pending_rows=15|73fd57dc8f34f13023b48f2b82e439b212eab52192886f0d07a37d86e63658b1' \
    doc/start_here.md doc/roadmap_status.md doc/pending_blocked.md doc/master_plan.md \
    examples/p3-runtime/README.md CHANGELOG.md
  ```

  Preserve the pre-existing unrelated modification to
  `doc/superpowers/plans/2026-08-28-g6-2-next-stage-admission-review.md`; do not
  stage or rewrite it.

- [ ] **Step 4: Commit the synchronized evidence.**

  ```bash
  git add doc/start_here.md doc/roadmap_status.md doc/pending_blocked.md \
    doc/master_plan.md examples/p3-runtime/README.md CHANGELOG.md
  git commit -m "docs: record resource triple compiler admission"
  ```

## Stop Conditions And Rollback

- A descriptor/hash mismatch, source-shape acceptance outside the exact table,
  missing negative diagnostic, WAT drift, ARC/Wasm-GC-reference marker,
  Component validation failure, lifecycle counter mismatch, or non-empty
  `ResourceTable` stops promotion immediately.
- If the route fails, keep the standalone triple probe and its existing design
  evidence, remove only uncommitted triple compiler artifacts, and leave all
  existing pair/list routes and the inventory unchanged.
- A failing full regression or release smoke is a release blocker; do not weaken
  expectations or hide the failure in documentation.
- The existing unrelated plan diff is never a rollback target.

## Acceptance

This stage is complete only when Tasks 1–5 have fresh evidence: the exact
manifest shape is fail-closed, the positive source emits the pinned WAT/WIT, all
thirteen negative fixtures reject their one mutation, canonical and generated
Components are byte/parity equivalent across ten modes, Rust/Wasmtime observes
exactly-once cleanup and `table-empty=true`, the full regression and release
smoke pass, and the migration inventory remains `complete_rows=15
pending_rows=15` with exit `1`. No public ownership syntax or generic lowering
is part of this acceptance.
