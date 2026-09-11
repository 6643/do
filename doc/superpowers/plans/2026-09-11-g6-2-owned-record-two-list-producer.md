# G6.2 Private Two-List Owned-Record Producer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (recommended) or superpowers:subagent-driven-development to implement this plan task-by-task with verification checkpoints.

**Goal:** Add one private, hash-pinned `stream<two-list-entry>` producer route that transfers one owned ticket and releases two independent `list<u32>` backing allocations exactly once on every terminal path.

**Architecture:** Keep the route isolated behind a new manifest effect, analyzer, and emitter module. Reuse the immutable `ProducerContract` and its existing stream/ownership lifecycle rules, adding two explicit `ListAllocation` facts without widening any generic producer predicate. Validate the canonical WIT/Core-WAT probe before registering the descriptor, then prove generated Do output with current `wasm-tools`, Rust, and Wasmtime gates.

**Tech Stack:** Zig `0.16.0`, `wasm-tools 1.258.0`, Wasmtime `48.0.1`, Rust/Cargo `1.97.1`, Bash gates, and the existing `do` compiler harness.

**Spec:** `doc/superpowers/specs/2026-09-11-g6-2-owned-record-two-list-producer-design.md`

## Global Constraints

- Admit only the exact private descriptor `do:g6-2-owned-record-two-list-producer@0.1.0` under `--p3-async-component`.
- Keep the WIT field order `first: list<u32>`, `second: list<u32>`, `ticket: own<ticket>` and the measured record target `20` bytes/alignment `4`.
- Keep `first.ptr/len` at `0/4`, `second.ptr/len` at `8/12`, `ticket` at `16`, list stride `4`, list capacity `3`, and stream capacity `1`; stop promotion on measured drift.
- Use two distinct `ListAllocation` paths (`first`, `second`) and one ownership leaf (`ticket`, bit `0`); never use handle value `0` as absence.
- Commit transfer only after the complete record write; before transfer release `second`, `first`, then the ticket; after transfer the guest releases both lists and the host drops the lifted ticket.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, `borrow_mut<T>`, pointer, lifetime, generic producer IR, arbitrary producer expressions, nested/variant/list-of-resource/borrowed payloads, or a default-route fallback.
- Preserve every existing G6.2 route byte-for-byte and keep the GC inventory at `complete_rows=15 pending_rows=15` with deliberate exit `1`.
- Use repository-local temporary/cache paths when a gate builds artifacts: `TMPDIR="$PWD/.tmp/do-tmp"`, `ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/g6-2-two-list-zig-cache/local"`, and `ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/g6-2-two-list-zig-cache/global"`.
- Do not stage unrelated worktree files; pushing is a separate explicit delivery action.

## File Map

Create these files:

- `examples/p3-runtime/g6-2-owned-record-two-list-producer.do` — exact Do sentinel adapter.
- `examples/p3-runtime/wit/g6-2-owned-record-two-list-producer.wit` — exact pinned WIT source.
- `examples/p3-runtime/g6-2-owned-record-two-list-producer-canonical.wat` — hand-authored canonical Core WAT and layout markers.
- `examples/p3-runtime/test_g6_2_two_list_owned_record_producer_abi.sh` — canonical parse/embed/component validation and hash gate.
- `examples/p3-runtime/test_do_g6_2_two_list_owned_record_producer.sh` — generated Do WAT/WIT gate.
- `examples/p3-runtime/test_do_g6_2_two_list_owned_record_producer_negative.sh` — fail-closed negative gate.
- `examples/p3-runtime/test_rust_g6_2_two_list_owned_record_producer.sh` — generated Rust/Wasmtime lifecycle gate.
- `examples/p3-runtime/rust-host-runner/src/bin/g6_2_two_list_owned_record_producer_abi.rs` — canonical probe runner.
- `examples/p3-runtime/rust-host-runner/src/bin/g6_2_two_list_owned_record_producer.rs` — generated component lifecycle runner.
- `src/build/codegen_component_two_list_owned_record_stream_producer.zig` — private analyzer and WAT/WIT emitter.
- `src/build/codegen_component_two_list_owned_record_stream_producer_test.zig` — analyzer/emitter unit tests.
- `src/build/two_list_owned_record_stream_producer_template.wat` — generated Core WAT template.
- `src/build/test/check/782_g6_2_two_list_owned_record_producer_component.do` — positive classification fixture.
- `src/build/test/compile_ok/782_g6_2_two_list_owned_record_producer_component.do` and `.expect` — positive compile fixture.
- `src/build/test/compile_err/783_g6_2_two_list_owned_record_producer_missing_first.do` and `.expect`.
- `src/build/test/compile_err/784_g6_2_two_list_owned_record_producer_missing_second.do` and `.expect`.
- `src/build/test/compile_err/785_g6_2_two_list_owned_record_producer_reordered_fields.do` and `.expect`.
- `src/build/test/compile_err/786_g6_2_two_list_owned_record_producer_wrong_first_type.do` and `.expect`.
- `src/build/test/compile_err/787_g6_2_two_list_owned_record_producer_wrong_second_type.do` and `.expect`.
- `src/build/test/compile_err/788_g6_2_two_list_owned_record_producer_borrowed_ticket.do` and `.expect`.
- `src/build/test/compile_err/789_g6_2_two_list_owned_record_producer_wrong_marker.do` and `.expect`.
- `src/build/test/compile_err/790_g6_2_two_list_owned_record_producer_wrong_source.do` and `.expect`.
- `src/build/test/compile_err/791_g6_2_two_list_owned_record_producer_wrong_body.do` and `.expect`.
- `src/build/test/compile_err/792_g6_2_two_list_owned_record_producer_nested_payload.do` and `.expect`.
- `src/build/test/compile_err/793_g6_2_two_list_owned_record_producer_wrong_stream.do` and `.expect`.
- `src/build/test/compile_err/794_g6_2_two_list_owned_record_producer_extra_binding.do` and `.expect`.
- `src/build/test/compile_err/795_g6_2_two_list_owned_record_producer_wrong_capacity.do` and `.expect`.

Modify these files:

- `src/build/p3_async_manifest.zig` and `src/build/p3_async_registry.json` — new measured shape, parser/freeing, validator, and pinned descriptor row.
- `src/build/codegen_component_producer_contract.zig` — two-list contract builder and static allocation facts.
- `src/build/codegen_component_async.zig` — target enum, dispatch, classification, and unit tests.
- `src/build/sema_imports.zig` — strict async signature and stream-effect admission branch.
- `src/main.zig` — import the new unit-test module into the test root.
- `examples/p3-runtime/rust-host-runner/Cargo.toml` — explicit binary entries for the two runners.
- `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/start_here.md`, `doc/g5b_async_resource_coverage.md`, and `CHANGELOG.md` — record the closed private gate without changing public capability counts.

### Task 1: Write RED fixtures and unit-test expectations

**Files:**
- Create the Do sentinel and positive/negative fixtures listed above.
- Create `src/build/codegen_component_two_list_owned_record_stream_producer_test.zig`.
- Modify `src/main.zig` to import the new test module.

**Interfaces:**
- The positive sentinel contains exactly two host bindings, one `Ticket` resource, one `TwoListEntry` record, one `ProducerError` declaration, `produce(mode u32)`, and `start()`.
- The analyzer test exports `TwoListOwnedRecordStreamProducerPlan.analyze(tokens, registry)` and emits through `emit_component_wat` / `emit_component_wit` once the implementation exists.
- Every negative fixture changes one fact and must eventually fail with `UnsupportedP3AsyncComponent` before an output file is created.

- [ ] **Step 1: Add the positive sentinel and check fixture.**

```do
make_ticket = @host_func("do:g6-2-owned-record-two-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
consume = @host_async_func("do:g6-2-owned-record-two-list-producer@0.1.0", "consume-via-stream", (StreamWriter<TwoListEntry>) -> Result<nil, ProducerError>)
Ticket = @wasi_resource("do:g6-2-owned-record-two-list-producer/source/ticket", { .id i64 })
TwoListEntry {
    .first [u32]
    .second [u32]
    .ticket Ticket
}
ProducerError error = Io | Pipe | InvalidMode
produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
start() {}
```

- [ ] **Step 2: Add the positive compile fixture and expected build marker.**

Use the same sentinel text in `782_g6_2_two_list_owned_record_producer_component.do`; its `.expect` contains `--p3-async-component` and the successful output marker used by adjacent G6.2 component fixtures.

- [ ] **Step 3: Add one-fact negative fixtures 783–795.**

Remove `first`, remove `second`, swap the fields, change `first` to `[u8]`, change `second` to `[i64]`, change `ticket` to a borrowed resource spelling, change the source marker to `@host_async_func`, change source locator/arity, add a producer statement, nest the record, change the stream element, add a third host binding, and change the required capacity fact. Each `.expect` contains `--p3-async-component` and `UnsupportedP3AsyncComponent`.

- [ ] **Step 4: Add unit tests for positive classification and one changed list fact.**

The positive test loads `782`, tokenizes it, loads `p3_async_registry.json`, and asserts that the plan type is the new plan. The negative test changes `first` from `[u32]` to `[u8]` in an in-memory source and asserts `error.UnsupportedP3TwoListOwnedRecordStreamProducer`.

- [ ] **Step 5: Run RED tests and commit only test artifacts.**

```bash
cd src
zig test main.zig --test-filter 'two-list owned-record producer'
```

Expected result: the new test module fails because the new analyzer module and manifest shape are not implemented yet. Commit the fixtures and test module with:

```bash
git diff --check
git add src/main.zig src/build/codegen_component_two_list_owned_record_stream_producer_test.zig \
  src/build/test/check/782_g6_2_two_list_owned_record_producer_component.do \
  src/build/test/compile_ok/782_g6_2_two_list_owned_record_producer_component.* \
  src/build/test/compile_err/78{3,4,5,6,7,8,9}_g6_2_two_list_owned_record_producer_* \
  src/build/test/compile_err/79{0,1,2,3,4,5}_g6_2_two_list_owned_record_producer_*
git commit -m "Add RED tests for two-list producer"
```

### Task 2: Add the canonical WIT/Core-WAT probe

**Files:**
- Create `examples/p3-runtime/wit/g6-2-owned-record-two-list-producer.wit`.
- Create `examples/p3-runtime/g6-2-owned-record-two-list-producer-canonical.wat`.
- Create `examples/p3-runtime/test_g6_2_two_list_owned_record_producer_abi.sh`.
- Create `examples/p3-runtime/rust-host-runner/src/bin/g6_2_two_list_owned_record_producer_abi.rs`.
- Modify `examples/p3-runtime/rust-host-runner/Cargo.toml` with binary `do-p3-g6-2-two-list-owned-record-producer-abi`.

**Interfaces:**
- The WIT file is exactly the WIT block in the spec and ends with one final newline.
- Canonical WAT exports the measured layout markers and uses only linear-memory `i32` fields at the canonical boundary.
- The ABI runner invokes a fresh Wasmtime `Store` per mode and reports both list payloads, ticket seed, list release counts, resource drops, and `table-empty=true`.

- [ ] **Step 1: Add the exact WIT source.**

Use package `do:g6-2-owned-record-two-list-producer@0.1.0`, world `owned-record-two-list-producer`, record `two-list-entry`, and the source/sink signatures from the spec. Do not reorder fields or normalize whitespace.

- [ ] **Step 2: Write the hand-authored canonical WAT.**

The module must write `first.ptr/len` at `0/4`, `second.ptr/len` at `8/12`, and the ticket at `16`; allocate separate backing spans for both lists; place `[producer-record-transfer]` only after the complete record write; and expose markers `[producer-record-byte-size] 20`, `[producer-record-alignment] 4`, `[producer-first-pointer-offset] 0`, `[producer-first-length-offset] 4`, `[producer-second-pointer-offset] 8`, `[producer-second-length-offset] 12`, `[producer-ticket-offset] 16`, `[producer-list-stride] 4`, `[producer-list-capacity] 3`, `[producer-stream-capacity] 1`, `[producer-list-release-exactly-once]`, and `[producer-resource-drop-exactly-once]`. It must contain no `(ref ...)`, `array`, `struct`, or `__arc_` marker.

- [ ] **Step 3: Add the ABI shell gate.**

```bash
TMPDIR="$PWD/.tmp/do-tmp" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/g6-2-two-list-zig-cache/local" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/g6-2-two-list-zig-cache/global" \
bash examples/p3-runtime/test_g6_2_two_list_owned_record_producer_abi.sh
```

The gate runs `do-toolchain probe`, verifies the WIT SHA-256, checks every marker and the no-GC-reference boundary, runs `parse-core`, `embed-component --features component-async`, `new-component`, `validate-component`, and then the canonical Rust runner for all ten lifecycle rows. It must stop on any layout drift or duplicate cleanup.

- [ ] **Step 4: Record the measured hash and commit the probe.**

Copy the hash printed by `sha256sum examples/p3-runtime/wit/g6-2-owned-record-two-list-producer.wit` into the manifest task; do not invent a hash. Commit only the WIT, canonical WAT, ABI shell gate, runner source, and Cargo entry.

### Task 3: Add the manifest shape and pinned registry row

**Files:**
- Modify `src/build/p3_async_manifest.zig`.
- Modify `src/build/p3_async_registry.json`.
- Modify `src/build/codegen_component_two_list_owned_record_stream_producer_test.zig`.

**Interfaces:**
- Add `TwoListOwnedRecordStreamProducerShape` carrying `element`, `stream_index`, `method`, `stream`, `record_layout`, and `producer`.
- Add `LoweringShape.record_resource_two_list_owned_record_stream_producer` and return it only for effect `record-resource-two-list-owned-record-stream-producer`.
- Keep `RecordListLayout` unchanged for the old one-list route; the two list offsets live in the record fields and contract allocation facts.

- [ ] **Step 1: Add a RED registry lookup assertion.**

Load the new locator from the registry test and assert that it is absent before the row is added; keep the existing list-owned-record descriptor lookup unchanged.

- [ ] **Step 2: Add the exact descriptor row after Task 2's hash is known.**

Use locator `do:g6-2-owned-record-two-list-producer@0.1.0`, member `consume-via-stream`, effect `record-resource-two-list-owned-record-stream-producer`, params `[
"stream<two-list-entry>"
]`, result `Result<nil,error-code>`, world `owned-record-two-list-producer`, and the measured WIT hash. The canonical object records core params `i32,i32`, result `i32`, record fields `first:i32@0`, `second:i32@8`, `ticket:i32@16`, producer source `(i32)->(i32)`, stream capacity `1`, terminal `task-return`, and the standard stream operation imports.

- [ ] **Step 3: Implement parse, free, and fail-closed validation.**

Parse the new shape through existing allocator ownership rules. Accept only the exact package/world/effect/hash/member, `stream<two-list-entry>`, record `20/4`, both list fields with `list<u32>` source metadata, ticket ownership `own`, source module/member/signature, capacity `1`, and operation names. Reject missing canonical members, unknown fields, zero/duplicate offsets, changed hash, changed stream operations, or collision with any existing effect.

- [ ] **Step 4: Run focused manifest tests.**

```bash
cd src
zig test build/p3_async_manifest.zig --test-filter 'two-list owned-record producer'
```

Expected result: the exact row is selected, the old one-list row still selects its old effect, and each single-field mutation returns no lowering shape.

- [ ] **Step 5: Commit the manifest change.**

```bash
git diff --check
git add src/build/p3_async_manifest.zig src/build/p3_async_registry.json \
  src/build/codegen_component_two_list_owned_record_stream_producer_test.zig
git commit -m "Register two-list owned-record producer shape"
```

### Task 4: Extend the immutable producer contract

**Files:**
- Modify `src/build/codegen_component_producer_contract.zig`.
- Modify `src/build/codegen_component_two_list_owned_record_stream_producer_test.zig`.

**Interfaces:**
- Add `two_list_owned_record_ticket_leaves` with one leaf at `ticket`, handle offset `16`, drop import `[resource-drop]ticket`, bit `0`.
- Add `two_list_owned_record_allocations` with two `ListAllocation` entries for `first` (`0/4`) and `second` (`8/12`), both `u32`, stride `4`, capacity `3`, release `cabi_realloc`.
- Add `build_two_list_owned_record_contract(...)` and select it only for `record_resource_two_list_owned_record_stream_producer`.

- [ ] **Step 1: Write contract RED assertions.**

Assert that the plan has `ownership.leaves.len == 1`, `ownership.leaves[0].handle_offset == 16`, `list_allocations.len == 2`, paths `first` and `second`, offsets `0/4` and `8/12`, and no ownership/list path overlap.

- [ ] **Step 2: Implement the exact builder.**

Require descriptor hash equality with the Task 2 hash, record descriptor identity, `record_layout` field order and offsets, producer source `(i32)->(i32)`, stream capacity `1`, `runtime_mode_param == "u32"`, no count/batch metadata, and the new sink module/import. Construct `ProducerContract` with `.payload = .{ .record = layout }`, the new ownership plan, two list allocations, and `terminal_from_stream("task-return", stream)`.

- [ ] **Step 3: Run contract tests.**

```bash
cd src
zig test build/codegen_component_producer_contract_test.zig --test-filter 'two-list owned-record'
```

Expected result: the exact contract validates and any allocation duplication, path overlap, missing drop import, or record drift is rejected.

- [ ] **Step 4: Commit the contract change.**

```bash
git diff --check
git add src/build/codegen_component_producer_contract.zig \
  src/build/codegen_component_two_list_owned_record_stream_producer_test.zig
git commit -m "Add two-list producer contract"
```

### Task 5: Implement the private analyzer and emitter

**Files:**
- Create `src/build/codegen_component_two_list_owned_record_stream_producer.zig`.
- Create `src/build/two_list_owned_record_stream_producer_template.wat`.
- Modify `src/build/codegen_component_two_list_owned_record_stream_producer_test.zig`.

**Interfaces:**
- Export `ProducerError = error{UnsupportedP3TwoListOwnedRecordStreamProducer}`.
- Export `TwoListOwnedRecordStreamProducerPlan` with `analyze(tokens, registry)`, `emit_component_wat(allocator, plan)`, `emit_component_wat_for_tokens(allocator, tokens)`, `emit_component_wit(allocator, plan)`, and `emit_component_wit_for_tokens(allocator, tokens)`.
- The emitter returns the template only after `validate_internal_plan` proves the descriptor hash, record layout, two list allocations, ownership leaf, stream operations, and terminal contract.

- [ ] **Step 1: Implement strict token admission.**

Require the exact two host bindings, resource declaration, `TwoListEntry` fields in order, `ProducerError`, sentinel `produce`, empty `start`, exactly seven top-level declarations, two top-level functions, no `async` token, and no `@async`, `@await`, or `@cancel`. Reject all negative fixtures before WAT/WIT allocation.

- [ ] **Step 2: Implement internal plan validation.**

Validate the new effect, exact descriptor hash, record `20/4`, field offsets `0/8/16`, source metadata `list<u32>`, two allocation entries, one ticket leaf, stream capacity `1`, source signature `(i32)->(i32)`, and no ARC marker in the template output.

- [ ] **Step 3: Implement the Core WAT template.**

Use a frame with record slot and two list pointer/length pairs. Allocate and fill each list independently, write both pairs and the ticket into the record slot, and set transfer state only after the complete write. On guest cleanup release `second` then `first` then ticket if its presence bit remains. On transferred cleanup release both lists and leave ticket drop to the host. Preserve all stream/task/future/frame cleanup markers and no GC reference boundary.

- [ ] **Step 4: Implement exact generated WIT.**

Return the pinned WIT text from the spec and assert byte equality with the checked-in probe file.

- [ ] **Step 5: Run focused emitter tests and commit.**

```bash
cd src
zig test build/codegen_component_two_list_owned_record_stream_producer_test.zig
```

Expected result: positive plan/emission tests pass, changed element/layout tests return `UnsupportedP3TwoListOwnedRecordStreamProducer`, generated WAT has both list markers and no `__arc_`, and generated WIT equals the probe.

```bash
git diff --check
git add src/build/codegen_component_two_list_owned_record_stream_producer.zig \
  src/build/two_list_owned_record_stream_producer_template.wat \
  src/build/codegen_component_two_list_owned_record_stream_producer_test.zig
git commit -m "Emit private two-list producer route"
```

### Task 6: Wire sema and Component dispatch

**Files:**
- Modify `src/build/codegen_component_async.zig`.
- Modify `src/build/sema_imports.zig`.
- Modify `src/main.zig` only if the test import was not already committed in Task 1.

**Interfaces:**
- Add target enum value `record_resource_two_list_owned_record_stream_producer`.
- Route the new lowering shape to the new emitter for WAT and WIT, classify it as an async invocation/stream effect, and keep all old target order and behavior unchanged.
- Add a dedicated `two_list_owned_record_stream_producer_signature_matches` branch that accepts only `StreamWriter<TwoListEntry> -> Result<nil,ProducerError>` under `@host_async_func`.

- [ ] **Step 1: Add RED dispatch assertions.**

Extend the async unit tests to assert that `782` classifies to the new target, that `emit_component_wat` contains `[producer-second-pointer-offset] 8`, and that an old one-list fixture still classifies to its original target.

- [ ] **Step 2: Add the manifest import and target branches.**

Import the new emitter module, add the enum case, add WAT/WIT switch branches, add `target_for_descriptor` mapping, and add the target in the existing classification tests. Do not collapse the new case into the old one-list effect.

- [ ] **Step 3: Add the sema signature/effect branch.**

Add the new shape to the stream-effect allowlist and dispatch only when the binding marker is `host_async_func`. Reject `host_func`, wrong stream element, wrong result, extra parameters, or any public ownership syntax.

- [ ] **Step 4: Run compiler-focused gates.**

```bash
cd src
zig test main.zig --test-filter 'two-list producer'
```

Then compile the positive and all negative fixtures with the standard harness entrypoint and assert negative outputs do not exist.

- [ ] **Step 5: Commit dispatch and sema changes.**

```bash
git diff --check
git add src/build/codegen_component_async.zig src/build/sema_imports.zig src/main.zig
git commit -m "Admit two-list producer in Component compiler"
```

### Task 7: Add generated Rust/Wasmtime lifecycle evidence

**Files:**
- Create `examples/p3-runtime/rust-host-runner/src/bin/g6_2_two_list_owned_record_producer.rs`.
- Create `examples/p3-runtime/test_rust_g6_2_two_list_owned_record_producer.sh`.
- Modify `examples/p3-runtime/rust-host-runner/Cargo.toml` with binary `do-p3-g6-2-two-list-owned-record-producer`.

**Interfaces:**
- The runner exposes mode, received `(first, second, ticket_seed)` tuples, result, resource-created/drops, two list allocation/release counts, stream/future drops, cancellation/pending counts, and `table-empty=true`.
- Use ten modes: ready, pending, sink-error-before, sink-error-after, cancel-before-transfer, cancel-after-transfer, early-drop-before-transfer, early-drop-after-transfer, repeat, and invalid.
- Valid modes create one ticket and two list allocations; repeat creates two of each; invalid creates none.

- [ ] **Step 1: Add the lifecycle runner.**

Implement a fresh component `Store` per mode, record list values independently, record ticket seed, instrument `cabi_realloc` for each list release, and assert host ticket drop exactly once after transfer. Assert pre-transfer paths observe no payload and post-transfer paths observe both lists.

- [ ] **Step 2: Add the generated gate.**

The shell gate builds the Do source, compares generated WIT with the probe and its measured hash, checks all record/list markers and no `__arc_`, runs `parse-core`, `embed-component`, `new-component`, `validate-component`, builds the runner with `cargo build --locked`, and invokes all ten modes.

- [ ] **Step 3: Run the generated gate.**

```bash
TMPDIR="$PWD/.tmp/do-tmp" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/g6-2-two-list-zig-cache/local" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/g6-2-two-list-zig-cache/global" \
bash examples/p3-runtime/test_rust_g6_2_two_list_owned_record_producer.sh
```

Expected result: all ten modes pass, both list releases and ticket drops are exactly once per valid invocation, cancellation has one pending-future drop where applicable, and every mode reports `table-empty=true`.

- [ ] **Step 4: Commit the Rust lifecycle gate.**

```bash
git diff --check
git add examples/p3-runtime/rust-host-runner/Cargo.toml \
  examples/p3-runtime/rust-host-runner/src/bin/g6_2_two_list_owned_record_producer.rs \
  examples/p3-runtime/test_rust_g6_2_two_list_owned_record_producer.sh
git commit -m "Verify two-list producer lifecycle"
```

### Task 8: Add Do/Component gates and negative coverage

**Files:**
- Create `examples/p3-runtime/test_do_g6_2_two_list_owned_record_producer.sh`.
- Create `examples/p3-runtime/test_do_g6_2_two_list_owned_record_producer_negative.sh`.

**Interfaces:**
- The positive Do gate verifies generated WIT byte parity, the measured hash, all layout/transfer/cleanup markers, Component assembly, and no ARC or GC-reference boundary.
- The negative gate compiles fixtures 783–795 with `--p3-async-component`, requires `UnsupportedP3AsyncComponent`, and verifies that neither `.wat` nor `.wit` is emitted.

- [ ] **Step 1: Add the positive Do gate.**

Use `DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$source" --p3-async-component --p3-wit-output "$wit" -o "$wat"`; compare WIT bytes; check record size `20`, both pointer/length offsets, ticket offset `16`, list stride/capacity, stream capacity, transfer, list-release, and resource-drop markers; then run current `do-toolchain parse-core`, `embed-component --features component-async`, `new-component`, and `validate-component`.

- [ ] **Step 2: Add the negative gate.**

For each fixture, use a unique temporary output path, capture stderr, require a non-zero build, require `UnsupportedP3AsyncComponent`, and assert that output WAT/WIT files are absent. Also assert that no old G6.2 route marker was emitted.

- [ ] **Step 3: Run both gates and the fixture harness.**

```bash
bash examples/p3-runtime/test_do_g6_2_two_list_owned_record_producer.sh
bash examples/p3-runtime/test_do_g6_2_two_list_owned_record_producer_negative.sh
./src/build/test/run_tests.sh
```

Expected result: both focused gates pass and the full harness remains green without changing existing counts except for the new positive/negative fixtures.

- [ ] **Step 4: Commit the Do gates.**

```bash
git diff --check
git add examples/p3-runtime/test_do_g6_2_two_list_owned_record_producer.sh \
  examples/p3-runtime/test_do_g6_2_two_list_owned_record_producer_negative.sh
git commit -m "Add two-list producer admission gates"
```

### Task 9: Synchronize status documents and run the release gate

**Files:**
- Modify `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/start_here.md`, `doc/g5b_async_resource_coverage.md`, and `CHANGELOG.md`.

**Interfaces:**
- State the exact private descriptor, WIT hash, `20/4` record layout, two list allocation paths, ticket offset `16`, lifecycle matrix, and current-toolchain evidence.
- Keep generic producer, borrowed/variant payload, arbitrary expression, public ownership syntax, and general async/resource lowering listed as pending; do not increment the public capability inventory.

- [ ] **Step 1: Add the closed-gate evidence.**

Record the focused gate commands and observed results: canonical/generated parity, `10` lifecycle modes, two list releases per repeat, one ticket drop per invocation, `table-empty=true`, no `__arc_`, and full regression counts.

- [ ] **Step 2: Run document drift checks.**

```bash
git diff --check
rg -n "g6-2-owned-record-two-list-producer|two-list-entry|record-resource-two-list" \
  doc/roadmap_status.md doc/pending_blocked.md doc/start_here.md doc/g5b_async_resource_coverage.md CHANGELOG.md
```

Ensure no document says this route opens generic lists, ownership syntax, or the public capability inventory.

- [ ] **Step 3: Run the complete verification matrix.**

```bash
./src/build/test/run_tests.sh
(cd src && zig test main.zig)
(cd src && zig build -Doptimize=ReleaseSmall)
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_g6_2_two_list_owned_record_producer_abi.sh
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_do_g6_2_two_list_owned_record_producer.sh
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_do_g6_2_two_list_owned_record_producer_negative.sh
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_rust_g6_2_two_list_owned_record_producer.sh
```

Expected result: all focused gates pass, the standard harness remains `14/14 steps`, standalone Zig tests pass, ReleaseSmall smoke succeeds, and no existing route or inventory count changes.

- [ ] **Step 4: Commit documentation and final verification evidence.**

```bash
git diff --check
git add doc/roadmap_status.md doc/pending_blocked.md doc/start_here.md \
  doc/g5b_async_resource_coverage.md CHANGELOG.md
git commit -m "Close G6.2 two-list producer gate"
git status --short
```

The final working tree must be clean before any separately authorized push.
