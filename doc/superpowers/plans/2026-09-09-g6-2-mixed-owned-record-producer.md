# G6.2 Mixed Owned-Record Producer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admit one private, hash-pinned `stream<mixed-entry>` producer whose record contains `code: u32` followed by `ticket: own<ticket>`, and prove canonical layout, transfer, cleanup, and generated/canonical lifecycle equivalence without widening general producer lowering.

**Architecture:** Keep the existing immutable `ProducerContract` and descriptor-specific producer routes. Add a separate manifest row and a dedicated mixed-record plan/emitter that accepts only the exact sentinel Do adapter from the design spec. A hand-authored canonical WIT/Core-WAT probe defines the ABI; the generated route must produce byte-for-byte WIT parity and equivalent ten-mode Rust/Wasmtime observations.

**Tech Stack:** Zig 0.16.0, Do lexer/sema/codegen, WAT/WIT Component assembly, current-only `wasm-tools` 1.258.0, Wasmtime 48.0.1, Rust/Cargo 1.97.1, and the existing Bash regression harness.

**Spec:** `doc/superpowers/specs/2026-09-09-g6-2-mixed-owned-record-producer-design.md`

## Global Constraints

- Keep `--p3-async-component` opt-in and preserve every existing direct, pair, parameterized-pair, triple, nested, list, dynamic-list, batched-list, and scalar-list route.
- Admit only package `do:g6-2-owned-record-mixed-producer@0.1.0`, world `owned-record-mixed-producer`, source member `make-ticket`, sink member `consume-via-stream`, export member `produce`, and descriptor effect `record-resource-mixed-stream-producer`.
- Use the exact WIT source and Do sentinel from the spec; compute and pin the WIT SHA-256 in the manifest row and reject any drift before WAT emission.
- Measure and assert `MixedEntry` alignment 4, size 8, `code` `i32` offset 0, and `ticket` `i32` offset 4. The scalar field has no ownership bit; the ticket is leaf bit 0 with `[resource-drop]ticket`.
- Use stream capacity 1, one synchronous `(i32) -> (i32)` ticket source, one mixed record per valid invocation, and `mode=255` rejection before all allocations.
- Preserve the existing complete-record transfer commit point and exactly-once cleanup on ready, pending, sink error, cancellation, early drop, repeat, and invalid paths. Handle value 0 remains valid when the presence bit is set.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, `borrow_mut<T>`, pointer, lifetime, generic producer IR, arbitrary producer expressions, variants, lists, nested payloads, borrowed payloads, or changes to cancellation/GC semantics.
- Use only current toolchain artifacts under `toolchain/toolchain.lock.json`; do not add compatibility fallbacks for older `wasm-tools` or Wasmtime.
- Preserve unrelated worktree changes and keep generated/build artifacts out of the repository root.

## File Map

- Modify `src/build/p3_async_manifest.zig` and `src/build/p3_async_registry.json` with the isolated manifest shape and exact descriptor row.
- Modify `src/build/sema_imports.zig` only for the new descriptor admission/signature matcher.
- Create `src/build/codegen_component_mixed_owned_record_stream_producer.zig` and `src/build/mixed_owned_record_stream_producer_template.wat` for the fixed canonical WAT fragments.
- Modify `src/build/codegen_component_producer_contract.zig` to represent and validate the mixed record through the existing immutable contract boundary.
- Modify `src/build/codegen_component_async.zig` and the narrow component dispatch module to install the new target and WIT/WAT emitter without changing existing routes.
- Create `examples/p3-runtime/wit/g6-2-owned-record-mixed-producer.wit`, `examples/p3-runtime/g6-2-owned-record-mixed-producer.do`, and `examples/p3-runtime/g6-2-owned-record-mixed-producer-canonical.wat`.
- Create `examples/p3-runtime/test_g6_2_mixed_owned_record_producer_abi.sh`, `examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer.sh`, `examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer_negative.sh`, `examples/p3-runtime/test_rust_g6_2_mixed_owned_record_producer.sh`, and `examples/p3-runtime/test_g6_2_mixed_owned_record_producer_equivalence.sh`.
- Create `examples/p3-runtime/rust-host-runner/src/bin/g6_2_mixed_owned_record_producer_abi.rs` and `g6_2_mixed_owned_record_producer.rs`; add only their explicit Cargo bin entries.
- Create `src/build/test/check/761_g6_2_mixed_owned_record_producer_component.do`, `src/build/test/compile_ok/761_g6_2_mixed_owned_record_producer_component.do`, and the exact drift fixtures `762_g6_2_mixed_owned_record_producer_missing_code.do`, `763_g6_2_mixed_owned_record_producer_reordered_fields.do`, `764_g6_2_mixed_owned_record_producer_borrowed_ticket.do`, `765_g6_2_mixed_owned_record_producer_wrong_marker.do`, `766_g6_2_mixed_owned_record_producer_wrong_source.do`, `767_g6_2_mixed_owned_record_producer_wrong_body.do`, `768_g6_2_mixed_owned_record_producer_nested_payload.do`, `769_g6_2_mixed_owned_record_producer_wrong_capacity.do`, and `770_g6_2_mixed_owned_record_producer_extra_binding.do` under `src/build/test/compile_err`, each with a matching `.expect` file.
- Update `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/start_here.md`, `README.md`, and `CHANGELOG.md` only after fresh gate output confirms the route state.

### Task 1: Add RED contract and admission tests

**Files:**
- Modify: `src/build/codegen_component_producer_contract.zig` unit tests for the mixed contract.
- Create: `src/build/test/check/761_g6_2_mixed_owned_record_producer_component.do` and `src/build/test/compile_ok/761_g6_2_mixed_owned_record_producer_component.do`.
- Create: the nine exact drift fixtures and `.expect` files listed in the File Map under `src/build/test/compile_err`.
- Create: `examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer.sh` and its negative counterpart.

**Interfaces:**
- The positive adapter declares `MixedEntry { .code u32 .ticket Ticket }`, one `@host_func` source, one `@host_async_func` sink, one `@wasi_resource`, one error declaration, sentinel `produce(mode u32) -> Result<nil, ProducerError>`, and empty `start()`.
- Before the manifest row exists, the positive fixture must fail closed with `UnknownP3AsyncHostDescriptor`; no WAT file may be emitted.
- Negative fixtures change exactly one fact: missing/reordered/extra field, wrong scalar type, borrowed/non-resource ticket, wrong host marker/signature/member/effect/capacity/hash, second binding, non-sentinel body, helper/branch/`@async`/`@await`/`@cancel`, nested/list/variant payload, or source arity/result.

- [ ] **Step 1: Write the exact positive Do and WIT fixtures used by the failing gate.**

  Use the spec's source shape, including:

  ```do
  make_ticket = @host_func("do:g6-2-owned-record-mixed-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
  consume = @host_async_func("do:g6-2-owned-record-mixed-producer@0.1.0", "consume-via-stream", (StreamWriter<MixedEntry>) -> Result<nil, ProducerError>)
  Ticket = @wasi_resource("do:g6-2-owned-record-mixed-producer/source/ticket", { .id i64 })
  MixedEntry { .code u32 .ticket Ticket }
  ProducerError error = Io | Pipe | InvalidMode
  produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
  start() {}
  ```

- [ ] **Step 2: Add contract RED assertions before adding any production route.**

  Assert that the future mixed contract must validate a `record` payload with fields `code:i32@0` and `ticket:i32@4`, byte size 8/alignment 4, exactly one leaf at path `ticket` with bit 0 and drop import `[resource-drop]ticket`, no parents, source `(i32)->(i32)`, sink capacity 1, and terminal cleanup. Include a mutation where `code` is incorrectly represented as an ownership leaf and require `InvalidOwnershipPath`/`DuplicateOwnershipBit` rather than silently accepting it.

- [ ] **Step 3: Run the RED commands and record the expected failure.**

  ```bash
  DO_LIB_ROOT="$PWD/lib" ./bin/do build --p3-async-component \
    "$PWD/examples/p3-runtime/g6-2-owned-record-mixed-producer.do" \
    -o /tmp/g6-2-mixed-before-admission.wat
  ./examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer.sh
  ```

  Expected: the build exits non-zero with the existing fail-closed unknown-descriptor diagnostic and does not create `/tmp/g6-2-mixed-before-admission.wat`; the contract test fails because the mixed shape is not yet implemented. Fix test typos and rerun until this is the feature-missing failure, not a shell/parser error.

- [ ] **Step 4: Commit only the RED fixtures/tests.**

  ```bash
  git diff --check
  git add src/build/codegen_component_producer_contract.zig \
    src/build/test/check/761_g6_2_mixed_owned_record_producer_component.do \
    src/build/test/compile_ok/761_g6_2_mixed_owned_record_producer_component.do \
    src/build/test/compile_err/762_g6_2_mixed_owned_record_producer_missing_code.do \
    src/build/test/compile_err/762_g6_2_mixed_owned_record_producer_missing_code.expect \
    src/build/test/compile_err/763_g6_2_mixed_owned_record_producer_reordered_fields.do \
    src/build/test/compile_err/763_g6_2_mixed_owned_record_producer_reordered_fields.expect \
    src/build/test/compile_err/764_g6_2_mixed_owned_record_producer_borrowed_ticket.do \
    src/build/test/compile_err/764_g6_2_mixed_owned_record_producer_borrowed_ticket.expect \
    src/build/test/compile_err/765_g6_2_mixed_owned_record_producer_wrong_marker.do \
    src/build/test/compile_err/765_g6_2_mixed_owned_record_producer_wrong_marker.expect \
    src/build/test/compile_err/766_g6_2_mixed_owned_record_producer_wrong_source.do \
    src/build/test/compile_err/766_g6_2_mixed_owned_record_producer_wrong_source.expect \
    src/build/test/compile_err/767_g6_2_mixed_owned_record_producer_wrong_body.do \
    src/build/test/compile_err/767_g6_2_mixed_owned_record_producer_wrong_body.expect \
    src/build/test/compile_err/768_g6_2_mixed_owned_record_producer_nested_payload.do \
    src/build/test/compile_err/768_g6_2_mixed_owned_record_producer_nested_payload.expect \
    src/build/test/compile_err/769_g6_2_mixed_owned_record_producer_wrong_capacity.do \
    src/build/test/compile_err/769_g6_2_mixed_owned_record_producer_wrong_capacity.expect \
    src/build/test/compile_err/770_g6_2_mixed_owned_record_producer_extra_binding.do \
    src/build/test/compile_err/770_g6_2_mixed_owned_record_producer_extra_binding.expect \
    examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer.sh \
    examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer_negative.sh
  git commit -m "Add RED tests for mixed owned-record producer"
  ```

### Task 2: Land the canonical WIT/Core-WAT probe and manifest RED/GREEN boundary

**Files:**
- Create: `examples/p3-runtime/wit/g6-2-owned-record-mixed-producer.wit`
- Create: `examples/p3-runtime/g6-2-owned-record-mixed-producer-canonical.wat`
- Create: `examples/p3-runtime/test_g6_2_mixed_owned_record_producer_abi.sh`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_mixed_owned_record_producer_abi.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Modify: `src/build/p3_async_manifest.zig`, `src/build/p3_async_registry.json`

**Interfaces:**
- Canonical WIT is the exact package/world from the spec, ending in a final newline.
- Canonical WAT contains explicit markers for `producer-record-byte-size=8`, `producer-record-alignment=4`, `producer-record-code-offset=0`, `producer-record-ticket-offset=4`, `producer-stream-capacity=1`, `producer-ticket-seed`, `producer-record-transfer`, and `producer-resource-drop-exactly-once`; it has no Wasm GC reference type at the Component boundary.
- The manifest exposes one private `LoweringShape.record_resource_mixed_stream_producer` row with exact package, world, effect, source/sink signatures, WIT hash, and canonical async import names. Existing rows remain byte-for-byte unchanged.

- [ ] **Step 1: Write the canonical WIT and hand-authored WAT probe.**

  WIT must contain:

  ```wit
  package do:g6-2-owned-record-mixed-producer@0.1.0;

  interface types {
    enum error-code { io, pipe, invalid-mode }
    resource ticket {}
    record mixed-entry { code: u32, ticket: own<ticket> }
  }
  ```

  Add the exact `source`, `sink`, and `owned-record-mixed-producer` world from the spec. The WAT probe must write `code` at linear-memory offset 0, the ticket handle at offset 4, and place the complete-record transfer marker after both stores.

- [ ] **Step 2: Extend the manifest parser with a failing row assertion.**

  Add the enum case and parser/validator test for `record-resource-mixed-stream-producer`; before adding the JSON row, assert lookup returns null and the RED adapter still fails closed. Then add only the exact row and pin the SHA-256 produced by:

  ```bash
  sha256sum examples/p3-runtime/wit/g6-2-owned-record-mixed-producer.wit
  ```

- [ ] **Step 3: Implement the canonical ABI runner and ABI gate.**

  The Rust runner must use a fresh `Store` for each mode and report the ordered `(code, seed)` observations, resource create/drop counts, pending polls, stream/future/task cleanup, cancellation, and `table-empty=true`. It must recognize `ready`, `pending`, `sink-error-before`, `sink-error-after`, `cancel-before-transfer`, `cancel-after-transfer`, `early-drop-before-transfer`, `early-drop-after-transfer`, `repeat`, and `invalid`.

- [ ] **Step 4: Run the canonical probe gate with current tools.**

  ```bash
  ./examples/p3-runtime/test_g6_2_mixed_owned_record_producer_abi.sh
  ```

  Expected: WIT hash, canonical markers, `wasm-tools` parse/embed/new-component/validate, and all ten runner modes pass. Any layout mismatch, component validation failure, GC reference, or non-empty table is a stop condition; record the failure in `doc/pending_blocked.md` and do not admit the compiler route.

- [ ] **Step 5: Commit the canonical probe and exact manifest row.**

  ```bash
  git diff --check
  git add examples/p3-runtime/wit/g6-2-owned-record-mixed-producer.wit \
    examples/p3-runtime/g6-2-owned-record-mixed-producer-canonical.wat \
    examples/p3-runtime/test_g6_2_mixed_owned_record_producer_abi.sh \
    examples/p3-runtime/rust-host-runner/src/bin/g6_2_mixed_owned_record_producer_abi.rs \
    examples/p3-runtime/rust-host-runner/Cargo.toml \
    src/build/p3_async_manifest.zig src/build/p3_async_registry.json
  git commit -m "Add mixed owned-record canonical ABI probe"
  ```

### Task 3: Add the immutable mixed contract and dedicated emitter

**Files:**
- Modify: `src/build/codegen_component_producer_contract.zig`
- Create: `src/build/codegen_component_mixed_owned_record_stream_producer.zig`
- Create: `src/build/mixed_owned_record_stream_producer_template.wat` for the fixed canonical WAT fragments.
- Modify: `src/build/codegen_component_async.zig` only for isolated target dispatch.

**Interfaces:**
- `MixedOwnedRecordStreamProducerPlan.analyze(tokens, registry) !MixedOwnedRecordStreamProducerPlan` accepts only the exact adapter and returns the normalized `ProducerContract`.
- `emit_component_wat(allocator, plan) ![]u8` emits the measured canonical layout and lifecycle markers; `emit_component_wit(allocator, plan) ![]u8` emits the exact pinned WIT.
- `ProducerContract.payload` remains the existing `.record` variant; mixed ownership is represented by `RecordLayout.fields` plus one `OwnershipLeaf`, never by token re-inference or a new public ownership type.

- [ ] **Step 1: Add the mixed contract fixture test and rerun it to see the missing-shape failure.**

  Assert that the normalized contract has two fields, `code` offset 0 and `ticket` offset 4, one leaf only for `ticket`, `complete_write_required=true`, and the existing cleanup order. Assert that a zero handle is not an absence sentinel and that an attempted scalar ownership leaf is rejected.

- [ ] **Step 2: Implement the minimal contract conversion and validation.**

  Add only a private mixed shape to the same conversion boundary used by direct/pair/triple/nested/list routes. Reuse `RecordLayout`, `OwnershipTransferPlan`, and terminal validation. Do not add a generic record walker, arbitrary field ownership inference, or public syntax.

- [ ] **Step 3: Add the exact emitter template and target dispatch.**

  The emitter must allocate/write the record in canonical order, call the synchronous source once, store the handle at offset 4, transfer only after the complete record write succeeds, clear the ticket presence bit exactly once, and use the existing stream/task/future/frame cleanup helpers. The target switch must choose this emitter only for the new descriptor and leave all old target cases unchanged.

- [ ] **Step 4: Run focused Zig tests and generated output checks.**

  ```bash
  cd src && zig build test
  cd ../
  DO_LIB_ROOT="$PWD/lib" ./bin/do build \
    examples/p3-runtime/g6-2-owned-record-mixed-producer.do \
    --p3-async-component \
    --p3-wit-output /tmp/g6-2-mixed-generated.wit \
    -o /tmp/g6-2-mixed-generated.wat
  cmp /tmp/g6-2-mixed-generated.wit \
    examples/p3-runtime/wit/g6-2-owned-record-mixed-producer.wit
  ```

  Expected: focused tests pass, generated WIT is byte-identical, generated WAT contains the mixed markers, and no `__arc_` symbol or GC reference crosses the Component boundary.

- [ ] **Step 5: Commit the contract/emitter implementation.**

  ```bash
  git diff --check
  git add src/build/codegen_component_producer_contract.zig \
    src/build/codegen_component_mixed_owned_record_stream_producer.zig \
    src/build/mixed_owned_record_stream_producer_template.wat \
    src/build/codegen_component_async.zig
  git commit -m "Implement mixed owned-record producer lowering"
  ```

### Task 4: Close compiler positive and negative admission gates

**Files:**
- Modify: `src/build/sema_imports.zig` for the exact mixed signature matcher.
- Modify: `src/build/codegen_component_async.zig` for the exact mixed target branch and WIT dispatch.
- Modify: `examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer.sh` and `examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer_negative.sh` created in Task 1.

**Interfaces:**
- `sema_imports` admits the descriptor only through the new exact effect and signature matcher; public `@host` routes and existing descriptor diagnostics remain unchanged.
- Every negative fixture fails before WAT emission and reports the focused unsupported mixed-producer diagnostic, with no fallback to direct/pair/triple/nested/list routes.

- [ ] **Step 1: Add positive compiler assertions.**

  The positive gate must build with explicit `--p3-wit-output`, compare the generated WIT hash to the manifest, parse/assemble/validate the Component, and grep for the mixed record size/offset/transfer/drop markers.

- [ ] **Step 2: Add negative boundary assertions.**

  For each drift fixture, run `./bin/do build ... -o "$tmp/out.wat"`, require non-zero exit, match the expected diagnostic substring, and assert the output path does not exist. Also run an existing direct/pair/triple/nested/list fixture in the same script to prove route isolation.

- [ ] **Step 3: Run the compiler gates.**

  ```bash
  ./examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer.sh
  ./examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer_negative.sh
  ```

  Expected: positive assembly/validation succeeds; every listed drift is rejected before WAT; existing routes remain green. If a negative fixture emits WAT or reaches an older route, stop and fix admission before continuing.

- [ ] **Step 4: Commit compiler admission and fixtures.**

  ```bash
  git diff --check
  git add src/build/sema_imports.zig src/build/codegen_component_async.zig \
    examples/p3-runtime/g6-2-owned-record-mixed-producer.do \
    examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer.sh \
    examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer_negative.sh \
    src/build/test/check/761_g6_2_mixed_owned_record_producer_component.do \
    src/build/test/compile_ok/761_g6_2_mixed_owned_record_producer_component.do \
    src/build/test/compile_err/762_g6_2_mixed_owned_record_producer_missing_code.do \
    src/build/test/compile_err/762_g6_2_mixed_owned_record_producer_missing_code.expect \
    src/build/test/compile_err/763_g6_2_mixed_owned_record_producer_reordered_fields.do \
    src/build/test/compile_err/763_g6_2_mixed_owned_record_producer_reordered_fields.expect \
    src/build/test/compile_err/764_g6_2_mixed_owned_record_producer_borrowed_ticket.do \
    src/build/test/compile_err/764_g6_2_mixed_owned_record_producer_borrowed_ticket.expect \
    src/build/test/compile_err/765_g6_2_mixed_owned_record_producer_wrong_marker.do \
    src/build/test/compile_err/765_g6_2_mixed_owned_record_producer_wrong_marker.expect \
    src/build/test/compile_err/766_g6_2_mixed_owned_record_producer_wrong_source.do \
    src/build/test/compile_err/766_g6_2_mixed_owned_record_producer_wrong_source.expect \
    src/build/test/compile_err/767_g6_2_mixed_owned_record_producer_wrong_body.do \
    src/build/test/compile_err/767_g6_2_mixed_owned_record_producer_wrong_body.expect \
    src/build/test/compile_err/768_g6_2_mixed_owned_record_producer_nested_payload.do \
    src/build/test/compile_err/768_g6_2_mixed_owned_record_producer_nested_payload.expect \
    src/build/test/compile_err/769_g6_2_mixed_owned_record_producer_wrong_capacity.do \
    src/build/test/compile_err/769_g6_2_mixed_owned_record_producer_wrong_capacity.expect \
    src/build/test/compile_err/770_g6_2_mixed_owned_record_producer_extra_binding.do \
    src/build/test/compile_err/770_g6_2_mixed_owned_record_producer_extra_binding.expect
  git commit -m "Gate mixed owned-record producer admission"
  ```

### Task 5: Add generated Rust/Wasmtime lifecycle and canonical equivalence gates

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_mixed_owned_record_producer.rs`
- Create: `examples/p3-runtime/test_rust_g6_2_mixed_owned_record_producer.sh`
- Create: `examples/p3-runtime/test_g6_2_mixed_owned_record_producer_equivalence.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` only for explicit bin entries.

**Interfaces:**
- The generated runner uses the same `Ticket`, `MixedEntry`, `ErrorCode`, stream consumer, and resource-table accounting as the canonical ABI runner, but loads the compiler-generated Component.
- The ten-mode expectations are exact: `(7,111)`, `(9,222)`, `[]`, `(13,444)`, `[]`, `(17,666)`, `[]`, `(21,888)`, `(7,111),(7,111)`, and `[]` for `ready`, `pending`, `sink-error-before`, `sink-error-after`, `cancel-before-transfer`, `cancel-after-transfer`, `early-drop-before-transfer`, `early-drop-after-transfer`, `repeat`, and `invalid` respectively.

- [ ] **Step 1: Write the generated-runner assertions before wiring the generated component.**

  Require every mode to print its label, ordered `received=(code,seed)` data, result, creation/drop counts, pending polls, stream/future/task cleanup, cancellation count, and `table-empty=true`; require repeat to use one store and observe two creations/two drops.

- [ ] **Step 2: Implement the runner and generated Rust gate.**

  ```bash
  ./examples/p3-runtime/test_rust_g6_2_mixed_owned_record_producer.sh
  ```

  The script builds the component with current `wasm-tools`, builds Cargo with `--locked`, runs all ten modes, and fails on any count or payload mismatch.

- [ ] **Step 3: Implement canonical/generated equivalence.**

  Assemble the canonical and generated components separately, validate both, run the same runner binary for every mode, and `diff -u` their redacted output after confirming paths contain no host-specific values.

- [ ] **Step 4: Run equivalence and inspect cleanup evidence.**

  ```bash
  ./examples/p3-runtime/test_g6_2_mixed_owned_record_producer_equivalence.sh
  ```

  Expected: ten mode diffs are empty, ordered code/seed payloads match, every valid mode has exactly-once resource/stream/future/frame cleanup, invalid has zero allocations, and every mode reports `table-empty=true`.

- [ ] **Step 5: Commit Rust/runtime gates.**

  ```bash
  git diff --check
  git add examples/p3-runtime/rust-host-runner/Cargo.toml \
    examples/p3-runtime/rust-host-runner/src/bin/g6_2_mixed_owned_record_producer.rs \
    examples/p3-runtime/test_rust_g6_2_mixed_owned_record_producer.sh \
    examples/p3-runtime/test_g6_2_mixed_owned_record_producer_equivalence.sh
  git commit -m "Verify mixed owned-record producer lifecycle"
  ```

### Task 6: Update inventories, run the full regression, and deliver

**Files:**
- Modify: `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/start_here.md`, `README.md`, `CHANGELOG.md`, and the mixed design/spec only where fresh evidence requires synchronization.
- Verify: `toolchain/toolchain.lock.json`, `src/build/test/run_tests.sh`, all existing G6.2 scripts, and GC migration inventory.

**Interfaces:**
- Documentation records the route as a private bounded capability, not generic producer support, and records any remaining pinned-toolchain or broader P3 blocker separately.
- The final inventory preserves the expected GC migration status `complete_rows=15 pending_rows=15` and does not mark unrelated routes complete.

- [ ] **Step 1: Run the focused and full verification set.**

  ```bash
  ./examples/p3-runtime/test_g6_2_mixed_owned_record_producer_abi.sh
  ./examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer.sh
  ./examples/p3-runtime/test_do_g6_2_mixed_owned_record_producer_negative.sh
  ./examples/p3-runtime/test_rust_g6_2_mixed_owned_record_producer.sh
  ./examples/p3-runtime/test_g6_2_mixed_owned_record_producer_equivalence.sh
  ./examples/p3-runtime/test_g6_2_general_producer_contract.sh
  ./examples/p3-runtime/test_g6_2_general_producer_contract_negative.sh
  ./src/build/test/run_tests.sh
  cd src && zig build -Doptimize=ReleaseSmall
  ```

  Expected: all commands pass with no unrecorded warnings, generated output remains outside the repository root, and the current-only toolchain versions match the lock file.

- [ ] **Step 2: Perform the documentation/inventory update from command output.**

  Record the exact new descriptor, WIT hash, measured offsets, ten-mode evidence, and explicit non-goals. If any gate is blocked, leave the route pending and record the command, observed failure, impact, and next condition in `doc/pending_blocked.md`; do not call a partial implementation complete.

- [ ] **Step 3: Run final repository checks.**

  ```bash
  git diff --check
  git status --short --branch
  git log -1 --oneline
  ```

  Inspect that only intended files changed, no cache/bundle/temp output is staged, and all generated artifacts are in temporary directories or ignored paths.

- [ ] **Step 4: Commit the synchronized docs and push `main`.**

  ```bash
  git add doc/roadmap_status.md doc/pending_blocked.md doc/start_here.md \
    README.md CHANGELOG.md
  git commit -m "Close mixed owned-record producer gates"
  git fetch origin main
  git rebase origin/main
  git push origin HEAD:main
  ```

  If `origin/main` advanced, resolve only the relevant rebase conflicts, rerun the full verification set, then push. Report the exact pushed commit and any residual blocker; do not claim remote parity without `git status --short --branch` showing no ahead/behind difference.

## Self-Review Checklist

- [ ] Every requirement in the design spec has a task: exact WIT/hash, measured layout, scalar-vs-resource ownership separation, transfer commit point, ten lifecycle modes, negative drift boundary, no GC reference, current-toolchain validation, generated/canonical equivalence, and existing-route/GC regression.
- [ ] No task introduces public ownership syntax, generic producer expressions, variant/list/nested generalization, or a compatibility fallback.
- [ ] Every production change follows a failing test and every test command states the expected result.
- [ ] Function/type names match across tasks: `MixedOwnedRecordStreamProducerPlan`, `ProducerContract.payload.record`, `record_resource_mixed_stream_producer`, and the explicit Rust/Bash filenames.
- [ ] `git diff --check` is run before each commit and before delivery.
