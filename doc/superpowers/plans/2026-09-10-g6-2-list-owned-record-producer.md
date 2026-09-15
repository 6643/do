
# G6.2 List-Owned-Record Producer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Admit one private, hash-pinned stream<list-entry> producer whose record contains values: list<u32> followed by ticket: own<ticket>, and prove layout, list release, resource transfer, cleanup, and generated/canonical lifecycle equivalence.

**Architecture:** Keep the existing GC-first runtime and immutable ProducerContract. Add a distinct manifest shape and a dedicated emitter that accepts only the exact sentinel adapter in the design spec. Extend the internal contract with measured list-backing allocation facts so list release is explicit, while keeping all existing descriptor-specific routes unchanged.

**Tech Stack:** Zig 0.16.0, Do lexer/sema/codegen, current-only wasm-tools and Wasmtime from toolchain/toolchain.lock.json, Rust/Cargo 1.97.1, WIT/Core-WAT Component probes, and the existing Bash regression harness.

**Spec:** doc/superpowers/specs/2026-09-10-g6-2-list-owned-record-producer-design.md

## Current-toolchain revalidation (2026-09-15)

The route was rechecked against the repository-pinned current toolchain after
the original implementation pass: Zig `0.16.0`, `wasm-tools 1.258.0`,
Wasmtime `48.0.1`, and Rust/Cargo `1.97.1`. The canonical ABI gate, positive
and negative Do/Component gates, generated Rust/Wasmtime ten-mode lifecycle
gate, and canonical/generated equivalence gate all pass. This is a current
revalidation record; it does not widen the fixed-shape route or retroactively
mark historical RED steps as rerun.

## Global Constraints

- Keep --p3-async-component opt-in and preserve every existing direct, pair, parameterized-pair, triple, nested, list, dynamic-list, batched-list, scalar-list, and mixed scalar/owned route.
- Admit only package do:g6-2-owned-record-list-producer@0.1.0, world owned-record-list-producer, source member make-ticket, sink member consume-via-stream, export member produce, and effect record-resource-list-owned-record-stream-producer.
- Use the exact WIT and Do sentinel from the spec; calculate and pin the WIT SHA-256 in the manifest row and reject hash drift before WAT emission.
- Measure and assert record alignment 4, size 12, values.ptr offset 0, values.len offset 4, ticket offset 8, list stride 4, capacity 3, and no Wasm GC reference at the Component boundary.
- Treat list backing storage as a separate cleanup fact; it is not an ownership leaf, presence bit, or null-handle sentinel.
- Use one synchronous source (i32) -> (i32), one capacity-one stream, at most one record per invocation, and mode=255 rejection before stream, task, ticket, or list allocation.
- Preserve complete-record transfer as the only ownership commit point and exactly-once cleanup on ready, pending, sink error, cancellation, early drop, repeat, and invalid paths.
- Do not add public own<T>, borrow<T>, ref<T>, borrow_mut<T>, pointer, lifetime, generic producer IR, arbitrary producer expressions, variants, nested payloads, list-of-resource elements, or compatibility fallbacks.
- Use project-local temporary/cache paths: TMPDIR="$PWD/.tmp/do-tmp", ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache", and ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache".
- Preserve unrelated worktree changes; stage only files belonging to this plan. Do not run reset, clean, checkout, broad formatting, or a compatibility-toolchain fallback.

## File Map

- Modify src/build/p3_async_manifest.zig: add RecordListLayout, ListOwnedRecordStreamProducerShape, parser/free logic, exact descriptor validator, and LoweringShape dispatch.
- Modify src/build/p3_async_registry.json: add one exact manifest row after the canonical probe hash is known.
- Modify src/build/codegen_component_producer_contract.zig: add measured ListAllocation facts, validation, and the private list-owned-record conversion branch.
- Create src/build/codegen_component_list_owned_record_stream_producer.zig: exact token matcher, normalized plan, WIT emitter, and WAT adapter.
- Create src/build/list_owned_record_stream_producer_template.wat: fixed canonical core WAT and lifecycle markers.
- Modify src/build/codegen_component_async.zig: isolated target enum, analyzer dispatch, WIT/WAT dispatch, and focused tests.
- Modify src/main.zig: import the new focused producer-contract test into the full Zig test root.
- Create examples/p3-runtime/wit/g6-2-owned-record-list-producer.wit, examples/p3-runtime/g6-2-owned-record-list-producer.do, and examples/p3-runtime/g6-2-owned-record-list-producer-canonical.wat.
- Create examples/p3-runtime/test_g6_2_list_owned_record_producer_abi.sh, test_do_g6_2_list_owned_record_producer.sh, test_do_g6_2_list_owned_record_producer_negative.sh, test_rust_g6_2_list_owned_record_producer.sh, and test_g6_2_list_owned_record_producer_equivalence.sh.
- Create Rust bins examples/p3-runtime/rust-host-runner/src/bin/g6_2_list_owned_record_producer_abi.rs and g6_2_list_owned_record_producer.rs; add only explicit Cargo bin entries.
- Create check/compile fixtures src/build/test/check/771_g6_2_list_owned_record_producer_component.do, src/build/test/compile_ok/771_g6_2_list_owned_record_producer_component.do, and compile-error fixtures 772 through 781, each with a matching .expect.
- Update doc/roadmap_status.md, doc/pending_blocked.md, doc/start_here.md, README.md, and CHANGELOG.md only after all gates are green.

## Execution Order

~~~mermaid
flowchart TD
    A[RED adapter and contract tests] --> B[Canonical WIT/WAT probe]
    B --> C[Manifest schema and pinned row]
    C --> D[Normalized list allocation contract]
    D --> E[Dedicated emitter and target dispatch]
    E --> F[Positive and negative compiler gates]
    F --> G[Component and Rust/Wasmtime lifecycle parity]
    G --> H[Full regression and documentation]
    H --> I[Push main]
~~~

### Task 1: Add RED adapter, boundary fixtures, and contract tests

**Files:**
- Create examples/p3-runtime/g6-2-owned-record-list-producer.do
- Create src/build/test/check/771_g6_2_list_owned_record_producer_component.do
- Create src/build/test/compile_ok/771_g6_2_list_owned_record_producer_component.do
- Create src/build/test/compile_err/772_g6_2_list_owned_record_producer_missing_values.do through 781_g6_2_list_owned_record_producer_wrong_list_type.do, with matching .expect files
- Create examples/p3-runtime/test_do_g6_2_list_owned_record_producer.sh and test_do_g6_2_list_owned_record_producer_negative.sh
- Create src/build/codegen_component_list_owned_record_stream_producer_test.zig

**Interfaces:**
- The positive adapter contains two host bindings, one Ticket resource, one ListEntry { .values [u32] .ticket Ticket }, one ProducerError, the sentinel produce(mode u32) -> Result<nil, ProducerError>, and empty start().
- Before the manifest row exists, the positive build fails with UnknownP3AsyncHostDescriptor during the existing semantic import gate and emits no WAT. After the exact row is registered, the same adapter reaches component admission and must fail with UnsupportedP3AsyncComponent until the dedicated route is implemented.
- Each negative changes one fact: missing/reordered/extra field, wrong list type, borrowed/non-resource ticket, wrong marker/source/body, nested payload, wrong stream shape, or extra binding. Before manifest registration each negative observes UnknownP3AsyncHostDescriptor; after registration each must reach UnsupportedP3AsyncComponent and emit no WAT.
- The new Zig test imports the not-yet-created producer plan and asserts the desired record/list facts; its initial failure must identify the missing module or plan, not a typo.

- [ ] Step 1: Write the exact positive adapter and check fixture.

~~~do
make_ticket = @host_func("do:g6-2-owned-record-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
consume = @host_async_func("do:g6-2-owned-record-list-producer@0.1.0", "consume-via-stream", (StreamWriter<ListEntry>) -> Result<nil, ProducerError>)
Ticket = @wasi_resource("do:g6-2-owned-record-list-producer/source/ticket", { .id i64 })
ListEntry {
    .values [u32]
    .ticket Ticket
}
ProducerError error = Io | Pipe | InvalidMode
produce(mode u32) -> Result<nil, ProducerError> {
    return Ok()
}
start() {}
~~~

- [ ] Step 2: Add the ten negative fixtures and stable expectations.

  772 removes .values; 773 swaps the two fields; 774 changes .ticket to a borrowed resource spelling; 775 changes the source marker to @host_async_func; 776 changes the source module or arity; 777 adds a statement to produce; 778 changes the record to a nested record; 779 changes StreamWriter<ListEntry> to another stream element; 780 adds a third host binding; 781 changes .values to [u8]. Each .expect contains # build-arg: --p3-async-component and UnsupportedP3AsyncComponent.

- [ ] Step 3: Write the RED shell gates.

~~~bash
TMPDIR="$PWD/.tmp/do-tmp" DO_LIB_ROOT="$PWD/lib" \
  ./bin/do build --p3-async-component \
  examples/p3-runtime/g6-2-owned-record-list-producer.do \
  -o "$PWD/.tmp/do-tmp/g6-2-list-before-admission.wat"
~~~

  The command must fail before creating the output. The positive shell gate must assert that failure and the negative gate must compile all ten fixtures with no WAT output.

- [ ] Step 4: Run RED and fix only fixture/test mistakes.

~~~bash
(cd src && zig test build/codegen_component_list_owned_record_stream_producer_test.zig)
bash examples/p3-runtime/test_do_g6_2_list_owned_record_producer.sh
bash examples/p3-runtime/test_do_g6_2_list_owned_record_producer_negative.sh
~~~

  Expected result: the Zig test fails because the plan module does not exist, and the adapter gates fail closed with UnknownP3AsyncHostDescriptor until the manifest row is introduced.

- [ ] Step 5: Commit only RED artifacts.

~~~bash
git diff --check
git add examples/p3-runtime/g6-2-owned-record-list-producer.do \
  examples/p3-runtime/test_do_g6_2_list_owned_record_producer.sh \
  examples/p3-runtime/test_do_g6_2_list_owned_record_producer_negative.sh \
  src/build/codegen_component_list_owned_record_stream_producer_test.zig \
  src/build/test/check/771_g6_2_list_owned_record_producer_component.do \
  src/build/test/compile_ok/771_g6_2_list_owned_record_producer_component.do \
  src/build/test/compile_err/772_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/773_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/774_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/775_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/776_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/777_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/778_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/779_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/780_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/781_g6_2_list_owned_record_producer_*
git commit -m "Add RED tests for list-owned-record producer"
~~~

### Task 2: Add the canonical WIT/Core-WAT probe and Rust ABI runner

**Files:**
- Create examples/p3-runtime/wit/g6-2-owned-record-list-producer.wit
- Create examples/p3-runtime/g6-2-owned-record-list-producer-canonical.wat
- Create examples/p3-runtime/test_g6_2_list_owned_record_producer_abi.sh
- Create examples/p3-runtime/rust-host-runner/src/bin/g6_2_list_owned_record_producer_abi.rs and g6_2_list_owned_record_producer.rs
- Modify examples/p3-runtime/rust-host-runner/Cargo.toml

**Interfaces:**
- WIT is the exact text in the spec and ends with one final newline.
- Canonical WAT contains markers [producer-record-byte-size] 12, [producer-record-alignment] 4, [producer-record-values-pointer-offset] 0, [producer-record-values-length-offset] 4, [producer-record-ticket-offset] 8, [producer-list-stride] 4, [producer-list-capacity] 3, [producer-record-transfer], [producer-list-release-exactly-once], and [producer-resource-drop-exactly-once].
- The Rust runner derives ListEntry { values: Vec<u32>, ticket: Resource<Ticket> }, uses a fresh Store per mode, observes ordered (values, seed) payloads, and asserts an empty ResourceTable after every terminal path.

- [ ] Step 1: Add the exact WIT source.

  Use the package do:g6-2-owned-record-list-producer@0.1.0, interfaces types, source, and sink, and world owned-record-list-producer exactly as written in the spec. Do not reorder fields or normalize whitespace.

- [ ] Step 2: Write the hand-authored canonical WAT.

  The WAT must allocate the list backing span, write values.ptr/values.len at record offsets 0/4, write the ticket handle at offset 8, and place the transfer marker only after the complete record write. It must release the list span on every terminal path and drop the ticket only when the presence bit remains set. It must contain no ref $, array, or struct GC boundary type.

- [ ] Step 3: Write the ten-mode Rust host runner.

  Modes are ready, pending, sink-error-before, sink-error-after, cancel-before-transfer, cancel-after-transfer, early-drop-before-transfer, early-drop-after-transfer, repeat, and invalid. The expected payload table is []/111, [11,22]/222, [12]/333, [13,14,15]/444, [16]/555, [17,18]/666, [19,20,21]/777, [22,23]/888 (repeat twice), and no payload for invalid. The runner checks source-call count, host-call count, pending poll count, stream/future cleanup, ticket drops, cancellation count, list release count, and table-empty=true.

- [ ] Step 4: Write and run the current-toolchain ABI gate.

~~~bash
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_g6_2_list_owned_record_producer_abi.sh
~~~

  The gate runs bin/do-toolchain probe, sha256sum for WIT, current parse-core, embed-component --features component-async, new-component, and validate-component. It then runs all ten Rust modes. Any layout mismatch, Component rejection, GC reference, duplicate cleanup, or non-empty table stops promotion.

- [ ] Step 5: Record the measured hash and commit the probe only.

  Store the WIT SHA-256 printed by the gate in the task evidence and commit the WIT, canonical WAT, ABI script, Rust bins, and explicit Cargo entries. Do not add the manifest row until the probe is green.

### Task 3: Add the manifest schema and exact pinned descriptor

**Files:**
- Modify src/build/p3_async_manifest.zig
- Modify src/build/p3_async_registry.json
- Modify src/build/codegen_component_list_owned_record_stream_producer_test.zig

**Interfaces:**
- Add LoweringShape.record_resource_list_owned_record_stream_producer carrying ListOwnedRecordStreamProducerShape.
- Add RecordListLayout { pointer_offset: u32, length_offset: u32, element_stride: u32, max_items: u32 } and parse it from JSON key record_list_layout.
- The exact validator accepts only the package, world, effect, WIT hash, stream<list-entry>, record layout 12/4 with values:i32@0 and ticket:i32@8 plus list offsets/length at 0/4, capacity 3, source (i32)->(i32), resource drop [resource-drop]ticket, and the existing stream operation imports.
- Existing record_resource_list_stream_producer remains the old stream<list<resource-entry>> shape and is not changed.

- [ ] Step 1: Add the RED parser/lookup assertion.

  Load the current registry and assert that the new effect has no lowering shape before its JSON row exists. Keep the positive adapter failure from Task 1 unchanged.

- [ ] Step 2: Add the exact row using the measured hash.

  The row uses locator do:g6-2-owned-record-list-producer@0.1.0, member consume-via-stream, effect record-resource-list-owned-record-stream-producer, params ["stream<list-entry>"], result Result<nil,error-code>, world owned-record-list-producer, and the measured WIT hash from Task 2. Its canonical record fields are values:i32@0 and ticket:i32@8; its record_list_layout is pointer_offset=0, length_offset=4, element_stride=4, max_items=3; producer source is make-ticket from the source instance, stream capacity is 1, terminal is task-return.

- [ ] Step 3: Implement parse, free, and exact validation.

  Parse and deallocate record_list_layout with existing allocator ownership rules. Reject unknown fields, zero stride/capacity, pointer/length collision, changed hash, changed source/sink operation, changed stream operations, extra canonical values, or any old descriptor collision.

- [ ] Step 4: Run focused manifest tests.

~~~bash
(cd src && zig test build/p3_async_manifest.zig --test-filter 'list-owned-record producer')
~~~

  Expected: the new exact row is selected, the old list-resource row is still selected by its own locator/effect, and every drift mutation returns no shape.

- [ ] Step 5: Commit the manifest row and parser.

~~~bash
git diff --check
git add src/build/p3_async_manifest.zig src/build/p3_async_registry.json \
  src/build/codegen_component_list_owned_record_stream_producer_test.zig
git commit -m "Register list-owned-record producer shape"
~~~

### Task 4: Extend the immutable producer contract with list allocation facts

**Files:**
- Modify src/build/codegen_component_producer_contract.zig
- Modify src/build/codegen_component_list_owned_record_stream_producer_test.zig

**Interfaces:**
- Add ListAllocation:

~~~zig
pub const ListAllocation = struct {
    path: []const []const u8,
    element_core_type: []const u8,
    pointer_offset: u32,
    length_offset: u32,
    element_stride: u32,
    max_items: u32,
    release_import: []const u8,
};
~~~

- Add list_allocations: []const ListAllocation = &.{} to ProducerContract.
- validate_contract must reject an empty path/type/import, pointer/length collision, zero stride/capacity, duplicate allocation paths, or an allocation path that is also an ownership leaf. Offset 0 is valid for a pointer field.
- Add a private list_owned_record conversion branch that creates one ownership leaf at handle offset 8 bit 0 and one list allocation at path values, pointer offset 0, length offset 4, stride 4, capacity 3, release import cabi_realloc.

- [ ] Step 1: Add RED assertions to the contract test.

  Construct the exact record layout and assert the scalar list has no ownership bit, the ticket leaf is the only leaf, list_allocations.len == 1, pointer offset 0 is accepted, and a duplicate path, pointer/length collision, zero stride, or list path reused as an ownership leaf is rejected.

- [ ] Step 2: Run the focused test to establish the missing contract behavior.

~~~bash
(cd src && zig test build/codegen_component_list_owned_record_stream_producer_test.zig)
~~~

  Expected: failure because ListAllocation and the new conversion branch do not yet exist.

- [ ] Step 3: Implement the minimal list allocation model and validator.

  Keep all existing contract defaults and routes byte-for-byte equivalent. Do not add a generic record walker or infer list facts from Do tokens. The new branch consumes only the manifest-measured layout.

- [ ] Step 4: Run contract and existing producer tests.

~~~bash
(cd src && zig test build/codegen_component_producer_contract.zig)
(cd src && zig test build/codegen_component_list_owned_record_stream_producer_test.zig)
~~~

- [ ] Step 5: Commit the contract extension.

~~~bash
git diff --check
git add src/build/codegen_component_producer_contract.zig \
  src/build/codegen_component_list_owned_record_stream_producer_test.zig
git commit -m "Model list allocation in producer contract"
~~~

### Task 5: Implement the exact plan, WAT template, and target dispatch

**Files:**
- Create src/build/codegen_component_list_owned_record_stream_producer.zig
- Create src/build/list_owned_record_stream_producer_template.wat
- Modify src/build/codegen_component_async.zig
- Modify src/build/codegen_component_list_owned_record_stream_producer_test.zig

**Interfaces:**
- Define ListOwnedRecordStreamProducerPlan with descriptor, binding names, type names, measured RecordLayout, RecordListLayout, ProducerCanonical, and normalized ProducerContract.
- ListOwnedRecordStreamProducerPlan.analyze(tokens, registry) !ListOwnedRecordStreamProducerPlan accepts only the exact adapter topology and exact new descriptor.
- emit_component_wat(allocator, plan) ![]u8 returns the embedded template only after validating the contract, layout, list allocation, and absence of __arc_.
- emit_component_wit(allocator, plan) ![]u8 returns the exact WIT text from the spec.
- Add one target enum case and dispatch only for record_resource_list_owned_record_stream_producer; old record_resource_list_stream_producer continues to use its old emitter.

- [ ] Step 1: Add RED plan/emitter tests.

  Assert exact target selection, two host bindings, one resource and record, no async intrinsic in the sentinel body, record layout 12/4, list facts 0/4/4/3, ticket offset 8, one list allocation, one ownership leaf, and rejection of a mutated field or descriptor.

- [ ] Step 2: Run RED focused tests.

~~~bash
(cd src && zig test build/codegen_component_list_owned_record_stream_producer_test.zig)
~~~

  Expected: failure because the plan/emitter module and target case are absent.

- [ ] Step 3: Implement the exact analyzer and normalized plan.

  Reuse existing token scanners for bindings, resources, records, errors, function declarations, and intrinsic counts. Require ListEntry, .values [u32], .ticket Ticket, exact source/sink locators and markers, exact produce/start, and the new manifest effect. Call producer_contract.producer_contract_from_descriptor only after all topology checks pass.

- [ ] Step 4: Implement the fixed WAT adapter.

  Copy only the lifecycle skeleton required by the measured template. Allocate list storage, write pointer/length/elements, write the resource handle, keep both list and ticket live while stream write is pending, release list then ticket before transfer, release list without ticket drop after transfer, and use existing stream/task/future/frame cleanup helpers. The template must include every marker from Task 2 and no ARC symbol.

- [ ] Step 5: Wire target selection and run focused generation tests.

~~~bash
(cd src && zig build test)
TMPDIR="$PWD/.tmp/do-tmp" DO_LIB_ROOT="$PWD/lib" ./bin/do build \
  --p3-async-component \
  examples/p3-runtime/g6-2-owned-record-list-producer.do \
  --p3-wit-output "$PWD/.tmp/do-tmp/g6-2-list-generated.wit" \
  -o "$PWD/.tmp/do-tmp/g6-2-list-generated.wat"
cmp "$PWD/.tmp/do-tmp/g6-2-list-generated.wit" \
  examples/p3-runtime/wit/g6-2-owned-record-list-producer.wit
~~~

  Expected: focused tests pass, generated WIT is byte-identical, WAT markers match the canonical template, and generated WAT has no __arc_.

- [ ] Step 6: Register the focused test in the full test root.

  Add `_ = @import("build/codegen_component_list_owned_record_stream_producer_test.zig");` beside the existing component producer tests in src/main.zig. Re-run `(cd src && zig test main.zig)` and confirm the new tests execute without changing unrelated test behavior.

- [ ] Step 7: Commit the adapter and dispatch.

~~~bash
git diff --check
git add src/build/codegen_component_list_owned_record_stream_producer.zig \
  src/build/list_owned_record_stream_producer_template.wat \
  src/build/codegen_component_async.zig \
  src/build/codegen_component_list_owned_record_stream_producer_test.zig \
  src/main.zig
git commit -m "Implement list-owned-record producer lowering"
~~~

### Task 6: Close positive and negative compiler admission gates

**Files:**
- Modify examples/p3-runtime/test_do_g6_2_list_owned_record_producer.sh
- Modify examples/p3-runtime/test_do_g6_2_list_owned_record_producer_negative.sh
- Modify src/build/test/compile_ok/771_g6_2_list_owned_record_producer_component.expect
- Modify src/build/test/compile_err/772 through 781 expectations only if actual stable diagnostics differ

**Interfaces:**
- Positive compile output contains the new sink module, all record/list markers, [producer-record-transfer], [producer-list-release-exactly-once], and [producer-resource-drop-exactly-once].
- Negative inputs fail before WAT with UnsupportedP3AsyncComponent; no old producer route matches them.
- Generated WIT hash equals the Task 2 measured hash.

- [ ] Step 1: Add the compile-ok marker expectations.

  Add # build-arg: --p3-async-component, the sink module name, record/list marker lines, and the generated [async-lift]produce marker to the .expect file.

- [ ] Step 2: Run the positive gate.

~~~bash
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_do_g6_2_list_owned_record_producer.sh
~~~

- [ ] Step 3: Run every negative fixture through the harness.

~~~bash
./src/build/test/run_tests.sh
~~~

  The ten new negatives must pass while all prior fixtures retain their existing diagnostics and output counts.

- [ ] Step 4: Run current Component validation on generated output.

  Use parse-core, embed-component --features component-async, new-component, and validate-component with generated WAT/WIT. Reject any GC reference, changed hash, or validator warning.

- [ ] Step 5: Commit compiler admission tests.

~~~bash
git diff --check
git add examples/p3-runtime/test_do_g6_2_list_owned_record_producer.sh \
  examples/p3-runtime/test_do_g6_2_list_owned_record_producer_negative.sh \
  src/build/test/compile_ok/771_g6_2_list_owned_record_producer.expect \
  src/build/test/compile_err/772_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/773_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/774_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/775_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/776_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/777_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/778_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/779_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/780_g6_2_list_owned_record_producer_* \
  src/build/test/compile_err/781_g6_2_list_owned_record_producer_*
git commit -m "Gate list-owned-record producer admission"
~~~

### Task 7: Prove generated/canonical Component and Rust/Wasmtime lifecycle equivalence

**Files:**
- Modify examples/p3-runtime/rust-host-runner/src/bin/g6_2_list_owned_record_producer.rs only for shared assertions
- Modify examples/p3-runtime/test_rust_g6_2_list_owned_record_producer.sh
- Modify examples/p3-runtime/test_g6_2_list_owned_record_producer_equivalence.sh

**Interfaces:**
- The lifecycle script runs the generated component through all ten modes and checks ordered values/seeds, exactly-once ticket cleanup, list-release marker, pending/cancel behavior, and table-empty=true.
- The equivalence script assembles canonical and generated Components with the current toolchain, runs the same Rust binary against both, and compares each mode's complete output byte-for-byte.

- [ ] Step 1: Add explicit lifecycle assertions.

  Assert ready receives ([],111), pending receives ([11,22],222) with one pending poll, sink-error-after receives ([12],333), transfer-before-cancel and early-drop receive no item, transfer-after-cancel/drop receives the expected item, repeat receives two identical items, and invalid has zero source/allocation/cleanup activity. Every mode reports one list release per invocation and an empty resource table.

- [ ] Step 2: Run generated Rust/Wasmtime lifecycle.

~~~bash
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_rust_g6_2_list_owned_record_producer.sh
~~~

- [ ] Step 3: Run canonical/generated parity.

~~~bash
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_g6_2_list_owned_record_producer_equivalence.sh
~~~

  Expected: ten mode outputs are identical; canonical and generated WIT are byte-identical; generated WAT has no ARC symbols; Component validation is green; every ResourceTable is empty.

- [ ] Step 4: Commit lifecycle and parity gates.

~~~bash
git diff --check
git add examples/p3-runtime/rust-host-runner/src/bin/g6_2_list_owned_record_producer.rs \
  examples/p3-runtime/test_rust_g6_2_list_owned_record_producer.sh \
  examples/p3-runtime/test_g6_2_list_owned_record_producer_equivalence.sh
git commit -m "Verify list-owned-record lifecycle parity"
~~~

### Task 8: Run the full gate, update status, and push main

**Files:**
- Modify only after green verification: doc/roadmap_status.md, doc/pending_blocked.md, doc/start_here.md, README.md, CHANGELOG.md

**Interfaces:**
- Documentation records the exact descriptor, measured WIT hash, record/list layout, mode matrix, cleanup counts, current toolchain, and unchanged non-goals.
- GC inventory remains complete_rows=15 pending_rows=15 with expected exit code 1; this private Component route does not close an ARC/GC inventory row.

- [ ] Step 1: Run focused and full verification.

~~~bash
TMPDIR="$PWD/.tmp/do-tmp" ./src/build/test/run_tests.sh
(cd src && zig test main.zig)
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_g6_2_list_owned_record_producer_abi.sh
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_do_g6_2_list_owned_record_producer_negative.sh
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_rust_g6_2_list_owned_record_producer.sh
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_g6_2_list_owned_record_producer_equivalence.sh
~~~

  Expected baseline remains 14/14 steps; 53/53 tests, zig test main.zig retains the pre-task count plus only the new focused unit tests, and the inventory command retains its deliberate exit 1.

- [ ] Step 2: Update status documents from actual output.

  Add one dated entry for the private fixed shape, the exact measured hash and offsets, ten-mode lifecycle result, and unchanged boundaries. Do not claim generic list/resource support, public ownership syntax, or GC inventory closure.

- [ ] Step 3: Run documentation and repository checks.

~~~bash
git diff --check
rg -n "TODO|TBD|implement later|Similar to Task" doc/superpowers/specs/2026-09-10-g6-2-list-owned-record-producer-design.md doc/superpowers/plans/2026-09-10-g6-2-list-owned-record-producer.md
git status --short --branch
~~~

- [ ] Step 4: Commit the verified status update.

~~~bash
git add doc/roadmap_status.md doc/pending_blocked.md doc/start_here.md README.md CHANGELOG.md
git commit -m "Close list-owned-record producer evidence"
~~~

- [ ] Step 5: Push all task commits to main and verify remote parity.

~~~bash
git push origin main
git status --short --branch
git log -1 --oneline
~~~

  Delivery requires a clean worktree and main...origin/main with no ahead/behind difference. If any gate fails, retain the failure evidence, leave the route private/pending, and do not push a false completion claim.

## Plan Self-Review

- Every spec requirement is assigned to Tasks 1-8: exact WIT/hash, measured layout, list-versus-resource ownership separation, transfer commit, list release, ten lifecycle modes, negative boundary, no GC reference, current-toolchain validation, generated/canonical parity, and unchanged existing routes.
- The new manifest effect and enum case are intentionally distinct from the existing record-resource-list-stream-producer route.
- The only new internal API is ListAllocation plus one private shape; no public ownership syntax or generic lowering is introduced.
- Every production code task has a preceding RED test step and an explicit command with expected result.
- No placeholder task wording, legacy-toolchain fallback, or unbounded producer admission is present.
