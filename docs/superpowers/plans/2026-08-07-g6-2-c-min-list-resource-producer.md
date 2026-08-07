# G6.2 C-min List/Resource Producer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one fail-closed, descriptor-bounded producer slice that sends exactly one `stream<list<resource-entry>>` item whose records own `ticket` resources, while preserving the value-oriented Do surface and existing cleanup invariants.

**Architecture:** Measure the producer input ABI independently with a hand-authored WIT/Core-WAT/Rust probe. Represent the measured list layout, resource transfer, and async cleanup as pure Zig plans, then register one private descriptor and emit the existing frame/callback ABI through an exact-shape compiler adapter. The producer admits only modes `0`, `1`, and `3`, one capacity-one item, and one sink terminal; all generic list/producer/resource forms remain rejected.

**Tech Stack:** Zig compiler (`src/build`), WIT/component-model async canonical ABI, hand-authored Core WAT, `wasm-tools`, Rust/Wasmtime host runner, shell gates, Do fixtures, and the repository regression harness.

## Global Constraints

- Keep `own<T>`, `borrow<T>`, `ref<T>`, pointers, references, and explicit lifetime syntax out of the Do language.
- Do not implement generic `list<T>` producer lowering, arbitrary producer expressions, nested lists, variant elements, borrowed fields, or a scheduler.
- Reuse the existing frame/callback ABI and child-before-parent cleanup order.
- Registry facts must come from the pinned producer probe; do not infer producer input layout from the existing consumer probe.
- Invalid `mode` must return before allocating a list or creating a resource.
- Valid modes are exactly `0`, `1`, and `3`; no dynamic list length is admitted.
- A transferred ticket/list is never released by the guest after transfer; queued-but-untransferred storage remains guest-owned.
- Cancellation follows existing WIT/Wasmtime semantics and does not roll back external host effects.
- Preserve all unrelated dirty and untracked work in the checkout.

---

### Task 1: Add the producer canonical WIT contract

**Files:**
- Create: `examples/p3-runtime/wit/g6-2-c-min-list-resource-producer.wit`
- Inspect: `examples/p3-runtime/wit/record-resource-list-stream-canonical.wit`

**Interfaces:**
- Produces the private package/world names and operation signatures consumed by the hand-authored WAT and Rust runner.
- The exact shape is:

```wit
package do:g6-2-c-min-producer@0.1.0;

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
  consume-via-stream: async func(data: stream<list<resource-entry>>) -> result<_, error-code>;
}

world c-min-producer {
  import source;
  import sink;
  export produce: async func(mode: u32) -> result<_, error-code>;
}
```

- [x] **Step 1: Write the WIT file with the exact private package, world, resource, record, stream, and async signatures above.**
- [x] **Step 2: Parse the WIT with the pinned toolchain.**

Run: `wasm-tools component wit examples/p3-runtime/wit/g6-2-c-min-list-resource-producer.wit`

Expected: parse succeeds without introducing a borrowed or nested payload shape.

- [x] **Step 3: Record the package hash used by the registry task.**

Run: `sha256sum examples/p3-runtime/wit/g6-2-c-min-list-resource-producer.wit`

Expected: one stable hash is copied verbatim into the descriptor; no guessed hash is accepted.

Observed: `wasm-tools 1.255.0 (76e20611d 2026-07-30)` parsed the package with
exit status 0. The source hash is
`8decd27aeca4a1f1863544860caec230a1fc50259336a893de79413c6f9ec3f7`.

---

### Task 2: Measure the producer canonical ABI and runtime cleanup

**Files:**
- Create: `examples/p3-runtime/g6-2-c-min-list-resource-producer-canonical.wat`
- Create: `examples/p3-runtime/test_g6_2_c_min_list_resource_producer_abi.sh`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_c_min_list_resource_producer_abi.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` only if the new binary needs a manifest entry
- Reuse: `examples/p3-runtime/test_record_resource_list_stream_abi.sh` and `examples/p3-runtime/rust-host-runner/src/bin/record_resource_list_stream_abi.rs` for component assembly and statistics conventions

**Interfaces:**
- The Core WAT exports the producer `c-min-producer` world and emits stable comments/markers for list pointer, length, element stride, ticket offset, allocation size, queue transition, and cleanup states.
- The Rust runner exposes one command taking `<component> <mode>` and prints machine-checkable counts for entries, resource creation/drops, list releases, stream/future drops, cancellation, and `ResourceTable` emptiness.
- The runner covers `ready-empty`, `ready-one`, `ready-three`, `pending`, `sink-error`, `invalid-mode`, `cancel-before-transfer`, `cancel-after-transfer`, `malformed-len`, and `duplicate-drop`.

- [x] **Step 1: Write the failing shell gate and Rust mode enum before implementing the WAT.**

Required assertions: `0/1/3` produce `[ ]`, `[1]`, `[1,2,3]`; invalid mode creates zero tickets; pending and sink error clean once; both cancellation points clean once; malformed length and duplicate release trap; every successful/error/cancel run ends with an empty `ResourceTable`.

- [x] **Step 2: Run the new shell gate to verify it fails because the canonical WAT and runner do not exist.**

Run: `bash examples/p3-runtime/test_g6_2_c_min_list_resource_producer_abi.sh`

Expected: FAIL at the missing probe files, not a silently skipped test.

- [x] **Step 3: Implement the hand-authored Core WAT using the measured consumer offsets only as an initial hypothesis, then expose the producer-specific markers and ownership transitions.**

The WAT must model guest list allocation, `make-ticket` calls, one queue slot, transfer clearing, sink completion, cancellation cleanup, and exactly-once release. It must not use compiler-generated output as its measurement source.

- [x] **Step 4: Implement the Rust/Wasmtime host behavior.**

Use `ResourceTable` for `ticket`, a source `make-ticket` callback, a sink stream consumer with pending/ready/error behavior, explicit drop counters, and an async component store configured with component-model async, more-async-builtins, and concurrency support. Treat a non-empty table or duplicate drop as failure.

- [x] **Step 5: Run the producer ABI gate and component validation.**

Run: `bash examples/p3-runtime/test_g6_2_c_min_list_resource_producer_abi.sh`

Expected: `wasm-tools parse`, component embedding/validation, all mode matrices, malformed-input traps, and exact cleanup counters pass. The script must print the measured pointer/length/stride/ticket facts.

Observed: `bash examples/p3-runtime/test_g6_2_c_min_list_resource_producer_abi.sh`
passed with `ready-empty`, `ready-one`, `ready-three`, `pending`, `sink-error`,
`early-drop`, `invalid-mode`, `cancel-before-transfer`, and
`cancel-after-transfer`. The two Core-WAT mutations also trap with
`unknown handle index 0` and `unknown handle index 4`. Every admitted terminal
path reports `table-empty=true`; the probe prints pointer `64`, length `68`,
stride `4`, ticket offset `0`, and stream capacity `1`.

The cancellation rows deliberately use guest-side subtask cancellation before
transfer and host child-drop after transfer. Wasmtime does not cancel a store
guest task merely because the `call_concurrent` future is dropped, so this gate
does not claim root-task hard cancellation.

---

### Task 3: Add pure list payload layout support

**Files:**
- Modify: `src/build/wit_abi_layout.zig`
- Test: `src/build/wit_abi_layout.zig`
- Inspect: `src/build/wit_abi_types.zig`, `src/build/p3_async_manifest.zig`

**Interfaces:**
- Add a pure `ListLayoutMeasurement`/`ListLayoutPlan` API for a list whose element is a fixed record with one owned resource slot. The plan must expose pointer and length word offsets, element stride/alignment, ticket slot offset, capacity bound, allocation/free actions, and an owned-slot iterator.
- Reject wrong root kinds, zero stride, misaligned offsets, lengths above the descriptor bound, nested/borrowed element layouts, and missing owned slots with existing `LayoutError` style errors.
- Preserve scalar, record, variant, and existing consumer list behavior byte-for-byte.

- [x] **Step 1: Add failing unit tests for the measured list facts and invalid layouts.**

Cover pointer `64`, length `68`, stride `4`, ticket offset `0`, accepted lengths `0/1/3`, rejection of `2`/`4`/arbitrary dynamic lengths, and rejection of nested/borrowed elements.

- [x] **Step 2: Run the focused layout tests before implementation.**

Run: `cd src && zig test build/wit_abi_layout.zig --test-filter 'list resource producer'`

Expected: the new tests fail while existing layout tests pass.

- [x] **Step 3: Implement the smallest pure constructor/validator and owned-slot enumeration API.**

Keep allocation and release actions declarative; do not emit WAT or import codegen modules from this leaf.

- [x] **Step 4: Run focused and existing layout tests.**

Run: `cd src && zig test build/wit_abi_layout.zig`

Expected: all tests pass, including existing scalar/record/variant measurements.

Observed: the pre-implementation focused command failed with undeclared
`ListLayoutMeasurement`/`ListLayoutPlan`, then the implemented focused suite
passed 6/6. The full `zig test build/wit_abi_layout.zig` passed 19/19 and
`zig test build/wit_abi_types.zig` passed 5/5. The API remains pure: it only
validates the fixed record/owned-resource shape, copies the closed length set,
and enumerates relative ticket slots; it emits no WAT and does not register a
compiler descriptor.

---

### Task 4: Extend ownership planning for queued and transferred list entries

**Files:**
- Modify: `src/build/wit_abi_ownership.zig`
- Test: `src/build/wit_abi_ownership.zig`
- Inspect: `src/build/codegen_ownership.zig`, `doc/memory.md`

**Interfaces:**
- Extend the pure ownership state domain with `guest_owned`, `queued`, `transferred`, and `finalized` states for each list allocation and owned ticket slot.
- Add operations for allocate, create-ticket, enqueue, transfer, clear-source-slot, release-list, release-ticket, cancel, and terminal finalize.
- `join_states` must reject a `maybe` owner after branches/loops; transferred entries must not generate guest release actions; cleanup ordering must be child tickets/list before stream/future/frame.

- [x] **Step 1: Add failing tests for mode cardinality ownership, backpressure, transfer, invalid mode, partial creation failure, cancellation before/after transfer, and duplicate release.**
- [x] **Step 2: Run `cd src && zig test build/wit_abi_ownership.zig --test-filter 'list producer'` and confirm only the new tests fail.**
- [x] **Step 3: Implement pure transition and join validation without adding WAT emission or public Do ownership syntax.**
- [x] **Step 4: Run the full ownership unit suite.**

Run: `cd src && zig test build/wit_abi_ownership.zig`

Expected: existing own/borrow/branch/early-drop tests and new list producer tests pass.

Observed: the pre-implementation focused command failed at the missing
`ListProducerOwnershipPlan`/state types. The implemented focused list-producer
suite passed 6/6; the full ownership suite passed 17/17. The plan models
`unallocated`, `guest_owned`, `queued`, `transferred`, and `finalized` states,
rejects cardinality `2`, releases only live guest tickets on pre-transfer
cancellation, clears but never releases transferred tickets, and emits
child-ticket/list actions before stream/future/frame terminal drops. Both the
generic and list-specific state joins reject `maybe` ownership.

---

### Task 5: Extend the async frame/queue/cancel plan

**Files:**
- Modify: `src/build/wit_abi_async.zig`
- Test: `src/build/wit_abi_async.zig`
- Inspect: `src/build/codegen_component_async_plan.zig`, `src/build/codegen_component_stream_writer.zig`

**Interfaces:**
- Add a bounded producer frame plan containing one writer/readable endpoint, one list storage slot, one sink future, one queue slot, waitable membership, callback states, and terminal action.
- Expose guarded transitions for `allocate -> queue -> transfer -> await -> finalize`, backpressure without a second item, cancellation before/after transfer, early drop, and child-before-parent cleanup.
- Keep existing endpoint state and cancellation semantics intact for all current future/stream tests.

- [x] **Step 1: Add failing unit tests for queue occupancy, transfer ownership, cancellation joins, and cleanup order.**
- [x] **Step 2: Run `cd src && zig test build/wit_abi_async.zig --test-filter 'list producer'` and verify the new tests fail only at the missing transitions.**
- [x] **Step 3: Implement the bounded frame plan as pure data and validation.**
- [x] **Step 4: Run `cd src && zig test build/wit_abi_async.zig` and the existing component async plan tests.**

Run: `cd src && zig test build/wit_abi_async.zig && zig test build/codegen_component_async_plan.zig`

Expected: no existing async regression.

Observed: the pre-implementation focused command failed at the missing
`ListProducerFramePlan`. The implemented frame suite passed 4/4; the full
`wit_abi_async` suite passed 13/13 and `codegen_component_async_plan` passed
156/156. The plan keeps one queue slot, tracks list/source-slot transfer,
waitable membership, sink future and callback state, and emits cleanup in
`clear-source-slots -> release-list -> drop-future -> unregister-waitable ->
drop-writer -> drop-frame -> terminal-finalize` order. Existing async behavior
remains unchanged.

---

### Task 6: Register the private producer descriptor and manifest validation

**Files:**
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/sema_imports.zig`
- Test: `src/build/p3_async_manifest.zig`
- Test: `src/build/sema_imports.zig` if its module contains focused tests

**Interfaces:**
- Add one descriptor for locator `do:g6-2-c-min-producer@0.1.0`, member `consume-via-stream`, and one lowering shape named `record_resource_list_stream_producer` (or the repository-equivalent exact enum name chosen consistently in this task).
- Store the WIT hash, world, source/sink operation signatures, stream/future canonical imports, resource-drop import, list layout facts, max items `3`, and producer terminal metadata.
- Add fail-closed validation for package/member/signatures/world/hash/layout/resource paths. Keep the existing consumer `record_resource_list_stream_reader` descriptor untouched.

- [x] **Step 1: Add failing manifest tests for the valid producer descriptor, wrong hash, wrong stream element, wrong list offsets, borrowed entry, unknown locator, and extra queue item.**
- [x] **Step 2: Run `cd src && zig test build/p3_async_manifest.zig --test-filter 'C-min producer'` and confirm the valid case is not admitted yet.**
- [x] **Step 3: Add the JSON descriptor and parser/validator branch using the producer probe's measured values.**
- [x] **Step 4: Update sema import-shape dispatch to recognize only the new exact descriptor and reject broader producer signatures with `UnknownP3AsyncHostDescriptor`/the established unsupported diagnostic.**
- [x] **Step 5: Run the manifest and sema suites.**

Run: `cd src && zig test build/p3_async_manifest.zig && zig test build/sema_imports.zig`

Expected: valid descriptor passes; tampered/unregistered shapes remain rejected.

Observed: the producer manifest and sema gates are green. `zig test build/p3_async_manifest.zig`
passed `79/79`; `zig test build/sema_imports.zig` passed `122/122`. The sema
matcher admits only `StreamWriter<[ResourceEntry]> -> Result<nil, ErrorCode>` for
the registered `consume-via-stream` descriptor and rejects drifted elements,
error types, and locators. `git diff --check` is clean. Compiler emission and
Do source admission remain Task 7.

---

### Task 7: Build the exact Do admission and emitter adapter

**Files:**
- Modify: `src/build/codegen_component_async_plan.zig`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/codegen_component_stream_writer.zig` only at the existing producer emission boundary
- Modify: `src/build/codegen_pipeline.zig` only if the new plan must be wired through the established callback/hook path
- Create only if needed by the existing architecture: `src/build/codegen_component_list_resource_producer.zig`
- Tests: `src/build/codegen_component_async_plan.zig` and any new emitter unit-test file

**Interfaces:**
- Admit only a Do function equivalent to `async produce(mode u32) -> Result<nil, ErrorCode>` with the registered source `make-ticket`, one registered sink call, one stream item, and one terminal await/cancel path.
- Map `mode == 0/1/3` to literal cardinalities and ticket seeds `none`, `1`, and `1,2,3`; reject all other modes before WAT emission.
- Consume `ListLayoutPlan`, `OwnershipPlan`, and `AsyncFramePlan`; do not add a second descriptor-specific state machine or a generic list producer template.
- Emit stable WAT markers for list pointer/length, stride, ticket slots, queue state, callback states, transfer clearing, and child-before-parent cleanup.

- [x] **Step 1: Add positive/negative plan unit tests before implementation.**

Positive: exact `produce(mode)` shape for modes `0/1/3`. Negative: arbitrary list length, two stream items, nested list, borrowed field, unknown descriptor, use-after-transfer, branch/loop maybe ownership, and synchronous fallthrough.

- [x] **Step 2: Run the new plan tests and confirm exact-shape cases fail before the adapter is wired.**
- [x] **Step 3: Implement parser/admission and plan construction with early guards.**
- [x] **Step 4: Implement the minimal emitter path through the existing frame/callback hooks.**
- [x] **Step 5: Run focused Zig tests and compile the positive Do fixture to inspect WAT markers.**

Run: `cd src && zig test build/codegen_component_async_plan.zig && zig test build/codegen_component_async.zig`

Observed: `codegen_component_list_resource_producer.zig` passed `139/139`,
`codegen_component_async.zig` passed `438/438`, and the generated WAT/WIT
markers matched the pinned producer facts.

---

### Task 8: Add Do positive and negative fixtures

**Files:**
- Create: `examples/p3-runtime/g6-2-c-min-list-resource-producer.do`
- Create: `examples/p3-runtime/g6-2-c-min-list-resource-producer-invalid-mode.do` if compile-time mode rejection is represented separately
- Create: `src/build/test/check/447_g6_2_c_min_list_resource_producer.do`
- Create: `src/build/test/compile_err/447_g6_2_c_min_list_resource_producer_unregistered.do`
- Create: `src/build/test/compile_err/447_g6_2_c_min_list_resource_producer_unregistered.expect`
- Create: `src/build/test/compile_err/448_g6_2_c_min_list_resource_producer_borrowed.do`
- Create: `src/build/test/compile_err/448_g6_2_c_min_list_resource_producer_borrowed.expect`
- Create: `src/build/test/compile_err/449_g6_2_c_min_list_resource_producer_dynamic_length.do`
- Create: `src/build/test/compile_err/449_g6_2_c_min_list_resource_producer_dynamic_length.expect`
- Create: `examples/p3-runtime/test_do_g6_2_c_min_list_resource_producer.sh`

**Interfaces:**
- Positive fixture uses only named Do `Ticket`/`ResourceEntry` values and the registered host/stream shape; it never spells `own`, `borrow`, `ref`, pointer, or lifetime syntax.
- Negative fixtures assert stable fail-closed diagnostics and do not rely on parser errors.

- [x] **Step 1: Add fixtures and expected diagnostics before enabling the emitter gate.**
- [x] **Step 2: Run each negative fixture with `./bin/do check` and verify the expected diagnostic substring.**
- [x] **Step 3: Run the positive shell gate through WAT generation, `wasm-tools parse`, component embedding, and marker assertions.**
- [x] **Step 4: Confirm existing `test_do_record_resource_list_stream_boundary.sh` still rejects the consumer-unregistered shape and existing producer tests remain unchanged.**

---

### Task 9: Add the Rust/Wasmtime producer runtime gate

**Files:**
- Create or complete: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_c_min_list_resource_producer.rs`
- Create: `examples/p3-runtime/test_rust_g6_2_c_min_list_resource_producer.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` only if required by the binary target

**Interfaces:**
- Run the compiler-generated component for modes `0/1/3`, pending, sink error, cancellation before/after transfer, and early drop.
- Observe stream/future/resource drop counts, source-created ticket ids, sink-received ids, table emptiness, and trap-vs-result behavior.
- Verify cancellation stops new writes and does not claim rollback of an already submitted sink effect.

- [x] **Step 1: Add the runner and shell assertions using the canonical probe's counters.**
- [x] **Step 2: Run the Rust gate against the positive compiler component.**

Run: `bash examples/p3-runtime/test_rust_g6_2_c_min_list_resource_producer.sh`

Expected: every matrix row has exactly-once cleanup and the expected `Ok`/`Err`/trap classification.

- [x] **Step 3: Run rustfmt on the new runner and targeted binary tests.**

Run: `cargo fmt --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml --all -- --check`

Observed: the new runner passes `rustfmt --edition 2021 --check`; repository-wide
`cargo fmt --check` still reports pre-existing formatting drift in unrelated
Rust binaries.

---

### Task 10: Full verification and documentation/status gate

**Files:**
- Modify: `doc/roadmap_status.md`
- Modify: `doc/pending_blocked.md` only if fresh evidence changes the C-min row
- Modify: `doc/host_abi_blockers.md` only if the producer blocker is actually closed
- Modify: `doc/design/2026-08-07-g6-2-c-min-list-resource-producer-architecture.md` and `docs/superpowers/specs/2026-08-07-g6-2-c-min-list-resource-producer-design.md` only for implementation evidence/status links

**Interfaces:**
- Documentation must call C-min a private bounded slice and must not mark generic producer, generic list, borrowed resource, or public ownership syntax complete.
- Status entries must cite exact commands and observed results, distinguishing passed, blocked, and deferred gates.

- [x] **Step 1: Run focused Zig unit tests.**

Run: `cd src && zig test build/wit_abi_types.zig && zig test build/wit_abi_layout.zig && zig test build/wit_abi_ownership.zig && zig test build/wit_abi_async.zig && zig test build/p3_async_manifest.zig && zig test build/sema_imports.zig && zig test build/codegen_component_async_plan.zig`

- [x] **Step 2: Run canonical and compiler/runtime C-min gates.**

Run: `bash examples/p3-runtime/test_g6_2_c_min_list_resource_producer_abi.sh && bash examples/p3-runtime/test_do_g6_2_c_min_list_resource_producer.sh && bash examples/p3-runtime/test_rust_g6_2_c_min_list_resource_producer.sh`

- [x] **Step 3: Run the standard full regression.**

Run: `./src/build/test/run_tests.sh`

Expected: all existing tests and the new fixtures pass.

- [x] **Step 4: Run ReleaseSmall smoke and hygiene checks.**

Run: `./src/build/test/run_tests.sh --wasm` if supported by the current harness, `cd src && zig build -Doptimize=ReleaseSmall`, and `git diff --check`.

Expected: no new warnings, malformed WAT, or whitespace errors.

- [x] **Step 5: Update status docs only from fresh output, review the diff, and record residual non-goals.**

Required residuals: generic list producer, arbitrary producer expressions, borrowed/nested payloads, public ownership syntax, and general async lowering remain pending.
