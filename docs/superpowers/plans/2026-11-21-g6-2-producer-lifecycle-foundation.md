# G6.2 Producer Lifecycle Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the existing resource-free scalar-list producer and direct owned-record producer through one validated lifecycle foundation without changing their source admission, WIT hashes, Core ABI, or runtime cleanup behavior.

**Architecture:** Add a small pure lifecycle transition module, then make the existing `LifecycleStateIR` carry validated normal, cancel, and early-drop paths. Extract the shared contract/frame/fragment validation from the direct pilot emitter into a reusable contract emitter entry point. Migrate the two existing golden routes one at a time and keep their route-specific source matchers and WAT fragments as compatibility adapters until later shape-family plans remove them.

**Tech Stack:** Zig 0.16.0, existing Do compiler test root, pinned WIT/Component fixtures, Bash ABI gates, Rust/Wasmtime lifecycle gates.

**Spec:** `docs/superpowers/specs/2026-11-21-g6-2-generic-producer-resource-design.md`

## Global Constraints

- Do not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax.
- Do not infer support for borrowed, list, variant, nested, or mixed resource payloads from a neighboring route without a measured ABI and runtime gate.
- Do not combine this work with D2 generic filesystem async, external HTTP provider generalization, GC migration inventory, root hard-cancel, or arbitrary producer expressions.
- Do not claim rollback of an external host side effect when cancellation occurs.
- Preserve fail-closed behavior for unknown descriptors, unknown status values, malformed lengths, duplicate release, and incomplete transfer.
- Keep the default compiler route unchanged until promotion criteria in the design are met.
- Preserve the production GC-first memory route; do not import legacy ARC or region release into production code.
- Keep route-specific WAT fragments and canonical hashes unchanged during this foundation phase.

## Review Focus

- Partial payload write before ownership transfer must release guest-owned leaves in reverse order and must not transfer a partial group. Test in `src/build/codegen_component_producer_state_ir_test.zig`.
- Pending cancellation and store early-drop must reach distinct terminal paths while releasing each live Component object once. Test in `src/build/codegen_component_producer_lifecycle_test.zig` and the existing Rust gates.
- Repeated calls and separate producer iterations must not reuse lifecycle state or presence masks. Test the state-path builder with two independent traces and the existing repeat runtime rows.
- Parent waitable cleanup must occur after child subtask/future/resource cleanup. Test cleanup-order validation in `src/build/codegen_component_producer_lifecycle_state_probe_test.zig`.
- A malformed descriptor or changed WIT hash must fail before WAT emission and must not fall back to another producer route. Test `src/build/codegen_component_producer_emitter_test.zig` and the existing negative shell gates.

## File Map

- Create `src/build/codegen_component_producer_lifecycle.zig`: pure lifecycle states, events, and transition/path validation.
- Create `src/build/codegen_component_producer_lifecycle_test.zig`: unit tests for legal and illegal lifecycle paths.
- Modify `src/build/codegen_component_producer_state_ir.zig`: attach validated lifecycle paths to `LifecycleStateIR` and use the shared transition validator.
- Modify `src/build/codegen_component_producer_state_ir_test.zig`: assert normal, cancel, early-drop, transfer, and cleanup path facts.
- Modify `src/build/codegen_component_producer_emitter.zig`: expose the shared contract emitter and keep route identity checks in the pilot wrapper.
- Modify `src/build/codegen_component_producer_emitter_test.zig`: exercise the shared entry point and preserve direct-route rejection/parity checks.
- Modify `src/build/codegen_component_owned_record_stream_producer.zig`: call the shared emitter after its source/descriptor admission.
- Modify `src/build/codegen_component_scalar_list_stream_producer.zig`: validate the same lifecycle contract and frame path before emitting its existing canonical template.
- Modify `src/main.zig`: import the new lifecycle unit test into the compiler test root.
- Verify `examples/p3-runtime/test_do_g6_2_owned_record_producer.sh`, `test_g6_2_owned_record_producer_equivalence.sh`, `test_rust_g6_2_owned_record_producer.sh`, `test_do_g6_2_scalar_list_producer.sh`, `test_g6_2_scalar_list_producer_abi.sh`, and `test_rust_g6_2_scalar_list_producer.sh`.
- Modify current status sections in `doc/pending_blocked.md`, `doc/master_plan.md`, `doc/start_here.md`, and `CHANGELOG.md` after all gates pass.

### Task 1: Add the pure lifecycle transition contract

**Files:**

- Create: `src/build/codegen_component_producer_lifecycle.zig`
- Create: `src/build/codegen_component_producer_lifecycle_test.zig`
- Modify: `src/main.zig:133-136` to import the new test module in the root `test` block.

**Interfaces:**

- Produces `State = enum { init, calling, pending, ready, error, cancelled, dropped }`.
- Produces `Event = enum { begin_call, poll_pending, complete_ready, complete_error, request_cancel, early_drop, cleanup, unknown_terminal }`.
- Produces `TransitionError` with explicit invalid-transition errors, including `AlreadyDropped`, `PendingRequired`, `TerminalRequired`, and `UnknownTerminal`.
- Produces `pub fn advance(state: State, event: Event) TransitionError!State`.
- Produces `pub fn validate_path(events: []const Event) TransitionError!State`.

- [ ] **Step 1: Write failing lifecycle tests.**

  In `codegen_component_producer_lifecycle_test.zig`, add tests named:

  - `normal pending ready cleanup reaches dropped`;
  - `pending cancellation cleanup reaches dropped`;
  - `pending early drop reaches dropped`;
  - `calling can complete directly without pending`;
  - `ready cannot be polled or cancelled`;
  - `dropped rejects every event`;
  - `cancel without pending is rejected`;
  - `cleanup before terminal is rejected`.

  Assert the exact final state `.dropped` for valid paths and the named error for invalid paths. `unknown_terminal` must fail closed with `UnknownTerminal` from every non-dropped state.

- [ ] **Step 2: Run the focused test and verify it fails.**

  Run:

  ```bash
  cd src && zig test build/codegen_component_producer_lifecycle_test.zig
  ```

  Expected: compilation fails because the lifecycle module and transition API do not exist yet.

- [ ] **Step 3: Implement `advance` and `validate_path`.**

  Keep the functions pure and table-driven. `poll_pending` may remain in
  `pending`; `early_drop` transitions `pending` directly to `dropped`; and
  `cleanup` transitions only `ready`, `error`, or `cancelled` to `dropped`.
  Do not encode descriptor-specific cleanup or host rollback in this module.

- [ ] **Step 4: Run the focused test and verify it passes.**

  Run the same `zig test` command. Expected: all lifecycle tests pass.

- [ ] **Step 5: Commit the isolated lifecycle contract.**

  ```bash
  git add src/build/codegen_component_producer_lifecycle.zig \
    src/build/codegen_component_producer_lifecycle_test.zig src/main.zig
  git commit -m "Add G6.2 producer lifecycle transitions"
  ```

### Task 2: Attach lifecycle paths to `LifecycleStateIR`

**Files:**

- Modify: `src/build/codegen_component_producer_state_ir.zig:40-60,148-208`.
- Modify: `src/build/codegen_component_producer_state_ir_test.zig`.

**Interfaces:**

- Consumes `lifecycle.State`, `lifecycle.Event`, `lifecycle.advance`, and `lifecycle.validate_path` from Task 1.
- Adds `pub const LifecyclePath = struct { events: [8]lifecycle.Event, len: u8, final_state: lifecycle.State }`.
- Adds `normal_path`, `cancel_path`, and `early_drop_path` fields to `LifecycleStateIR`.
- Produces `build_lifecycle_ir` output whose three paths end in `.dropped` and whose transfer/cleanup facts remain unchanged.

- [ ] **Step 1: Add failing state IR assertions.**

  Extend `codegen_component_producer_state_ir_test.zig` with tests named:

  - `producer lifecycle IR records normal ready cleanup path`;
  - `producer lifecycle IR records cancellation path without rollback`;
  - `producer lifecycle IR records early-drop path`;
  - `producer lifecycle IR rejects a path that cleans before terminal state`;
  - `producer lifecycle IR keeps one independent path per frame group`.

  Assert `.normal_path.final_state`, `.cancel_path.final_state`, and `.early_drop_path.final_state` are `.dropped`; assert the cancel path has no rollback marker; assert multiple transfer groups have distinct path/frame group indexes.

- [ ] **Step 2: Run the focused state IR tests and verify the new assertions fail.**

  ```bash
  cd src && zig test build/codegen_component_producer_state_ir_test.zig
  ```

  Expected: existing tests may pass, while the new assertions fail to compile because the fields and path construction are absent.

- [ ] **Step 3: Build the three paths from the existing contract facts.**

  In `build_lifecycle_ir`, derive paths from the validated `TerminalContract`, transfer groups, and frame facts. Use `begin_call -> complete_ready -> cleanup` for a direct ready route and `begin_call -> poll_pending -> complete_ready -> cleanup` for pending routes. Build the cancellation and early-drop variants from pending state. Invoke the Task 1 validator for every path and map any invalid transition to the existing `LifecycleError` family without swallowing the source error.

- [ ] **Step 4: Preserve existing ownership and cleanup validation.**

  Keep complete-write barriers, atomic transfer groups, reverse pre-transfer release, child-before-parent ordering, and `rolls_back_host_effects == false` checks. Add no new acceptance for borrowed, variant, or arbitrary producer shapes.

- [ ] **Step 5: Run focused and root tests.**

  ```bash
  cd src && zig test build/codegen_component_producer_state_ir_test.zig
  cd .. && mkdir -p .tmp/do-tmp/plan-zig-cache .tmp/do-tmp/plan-zig-gcache
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/plan-zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/plan-zig-gcache" \
  ./src/build/test/run_tests.sh
  ```

  Expected: focused state IR tests pass and the default harness has zero failures.

- [ ] **Step 6: Commit the IR integration.**

  ```bash
  git add src/build/codegen_component_producer_state_ir.zig \
    src/build/codegen_component_producer_state_ir_test.zig
  git commit -m "Validate G6.2 lifecycle paths in producer IR"
  ```

### Task 3: Extract the shared contract emitter entry point

**Files:**

- Modify: `src/build/codegen_component_producer_emitter.zig:1-80`.
- Modify: `src/build/codegen_component_producer_emitter_test.zig`.
- Modify: `src/build/codegen_component_owned_record_stream_producer.zig:160-180`.

**Interfaces:**

- Adds `pub const ContractEmitInput = struct { route_id: []const u8, descriptor_id: []const u8, contract: producer_contract.ProducerContract, frame_facts: facts.RouteFrameFacts, fragments: []const fragments.Fragment, template_wat: []const u8, canonical_wit_hash: []const u8 }`.
- Adds `pub fn emit_contract_wat(allocator: std.mem.Allocator, input: ContractEmitInput) PilotError![]u8`.
- `emit_contract_wat` performs generic contract validation, canonical frame-map construction, lifecycle IR construction, fragment marker ownership, ARC/GC forbidden-marker checks, and fragment assembly.
- `emit_pilot_wat` remains the direct route compatibility wrapper and retains direct identity, direct descriptor hash, direct admission, and byte-parity checks.

- [ ] **Step 1: Write failing shared-emitter tests.**

  In `codegen_component_producer_emitter_test.zig`, add tests named:

  - `shared contract emitter accepts direct route facts`;
  - `shared contract emitter rejects descriptor/hash mismatch`;
  - `shared contract emitter rejects lifecycle map mismatch`;
  - `shared contract emitter rejects unowned fragment marker`;
  - `pilot wrapper preserves direct byte parity`.

  The first test must compare the shared output byte-for-byte with `owned_record_stream_producer_template.wat`; the last test must retain the current pilot parity assertion.

- [ ] **Step 2: Run emitter tests and verify the new API is absent.**

  ```bash
  cd src && zig test build/codegen_component_producer_emitter_test.zig
  ```

  Expected: new tests fail to compile until `ContractEmitInput` and `emit_contract_wat` exist.

- [ ] **Step 3: Extract generic validation and assembly.**

  Move the route-independent body of `emit_pilot_wat` into `emit_contract_wat`. Preserve error mapping and allocator ownership. The shared function must compare the input descriptor ID to the frame facts and contract, but must not hard-code `owned-record-direct` or a direct WIT hash.

- [ ] **Step 4: Rebuild the pilot wrapper on the shared entry point.**

  Keep `validate_identity_and_hash` and `validate_direct_admission` in the direct adapter. Construct `ContractEmitInput` from `PilotFacts`, call `emit_contract_wat`, then perform the existing direct golden byte comparison.

- [ ] **Step 5: Run focused emitter tests and direct route gates.**

  ```bash
  cd src && zig test build/codegen_component_producer_emitter_test.zig
  cd ..
  bash examples/p3-runtime/test_do_g6_2_owned_record_producer.sh
  bash examples/p3-runtime/test_g6_2_owned_record_producer_equivalence.sh
  ```

  Expected: all commands pass, with unchanged WAT byte parity and no ARC or Wasm GC reference markers.

- [ ] **Step 6: Commit the shared emitter extraction.**

  ```bash
  git add src/build/codegen_component_producer_emitter.zig \
    src/build/codegen_component_producer_emitter_test.zig \
    src/build/codegen_component_owned_record_stream_producer.zig
  git commit -m "Route owned producer through shared contract emitter"
  ```

### Task 4: Migrate the resource-free scalar/list golden route

**Files:**

- Modify: `src/build/codegen_component_scalar_list_stream_producer.zig`.
- Verify: `src/build/codegen_component_producer_contract.zig` and `src/build/codegen_component_producer_state_ir.zig`.
- Verify: `examples/p3-runtime/test_do_g6_2_scalar_list_producer.sh`.
- Verify: `examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh`.
- Verify: `examples/p3-runtime/test_rust_g6_2_scalar_list_producer.sh`.

**Interfaces:**

- The existing `ScalarListStreamProducerPlan.contract` remains the source of truth for descriptor, sink capacity, list layout, allocation, and terminal cleanup.
- `emit_component_wat` must construct and validate the shared frame/lifecycle IR before returning the existing canonical scalar-list template.
- The route remains limited to `list<u32>`, pointer `64`, length `68`, stride `4`, maximum `3`, stream capacity `1`, and accepted lengths `0..3`.

- [ ] **Step 1: Add a focused assertion that scalar/list emission builds lifecycle IR.**

  Extend the existing scalar-list unit coverage or add a focused test in the module that asserts the contract produces no ownership leaves, one list allocation, and a dropped normal/cancel/early-drop path before WAT emission.

- [ ] **Step 2: Run the focused scalar/list test before implementation.**

  ```bash
  cd src && zig test build/codegen_component_scalar_list_stream_producer.zig
  ```

  Expected: the new assertion fails until emission invokes the shared state IR.

- [ ] **Step 3: Integrate the shared state IR without changing the template.**

  Replace duplicate scalar/list lifecycle checks with the normalized contract and `build_frame_map`/`build_lifecycle_ir` validation. Keep the canonical WAT bytes, list allocation offsets, accepted lengths, and route-specific admission checks unchanged.

- [ ] **Step 4: Run the scalar/list ABI and runtime gates.**

  ```bash
  cd src && zig test build/codegen_component_scalar_list_stream_producer.zig
  cd ..
  bash examples/p3-runtime/test_do_g6_2_scalar_list_producer.sh
  bash examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh
  bash examples/p3-runtime/test_rust_g6_2_scalar_list_producer.sh
  ```

  Expected: pointer `64`, length `68`, stride `4`, capacity `3`, exact list release, pending/ready/error/cancel/early-drop/repeat, and empty resource table observations remain unchanged.

- [ ] **Step 5: Commit the scalar/list migration.**

  ```bash
  git add src/build/codegen_component_scalar_list_stream_producer.zig
  git commit -m "Migrate scalar producer to lifecycle IR"
  ```

### Task 5: Lock negative boundaries and documentation status

**Files:**

- Modify: `src/build/codegen_component_producer_state_ir_test.zig` and `src/build/codegen_component_producer_emitter_test.zig` if any boundary assertions are still missing.
- Verify: existing negative fixtures for arbitrary producer expressions, shared leases, borrowed async payloads, seventh nesting, and sixth forwarding.
- Modify current sections only: `doc/pending_blocked.md`, `doc/master_plan.md`, `doc/start_here.md`, `CHANGELOG.md`.

**Interfaces:**

- No new public source capability.
- Existing unsupported cases continue to return their current diagnostics and produce no WAT.
- Documentation records this as internal foundation work; G6.2 general producer/resource support remains pending.

- [ ] **Step 1: Add or retain negative assertions for no fallback.**

  Assert that a changed descriptor ID, borrowed async payload, arbitrary producer body, or shared writer lease does not select the migrated scalar/direct route and does not emit a WAT artifact. Unknown terminal events are covered by Task 1's `UnknownTerminal` transition test.

- [ ] **Step 2: Run the focused boundary gates.**

  ```bash
  bash examples/p3-runtime/test_do_g6_general_boundary_rejection.sh
  bash examples/p3-runtime/test_do_borrowed_resource_rejection.sh
  ./bin/do check src/build/test/check/412_stream_writer_shared_lease.do
  (cd src && zig test build/p3_async_manifest.zig)
  ```

  Expected: all existing rejection diagnostics remain layer-correct and the seventh-level manifest rejection remains fail-closed.

- [ ] **Step 3: Update status documents.**

  Record the two migrated golden routes, the unchanged private capability boundary, the exact verification commands, and the fact that no new GC inventory row or public ownership syntax was added. Do not rewrite historical `complete_rows=15 pending_rows=15` snapshots.

- [ ] **Step 4: Review documentation consistency.**

  ```bash
  git diff --check
  rg -n "G6\.2|complete_rows=15 pending_rows=15|generic producer|public own" \
    doc/pending_blocked.md doc/master_plan.md doc/start_here.md CHANGELOG.md
  ```

  Expected: current sections agree; historical counts remain explicitly historical; no current section says that generic producer/resource lowering is complete.

- [ ] **Step 5: Commit the boundary and status update.**

  ```bash
  git add src/build/codegen_component_producer_state_ir_test.zig \
    src/build/codegen_component_producer_emitter_test.zig \
    doc/pending_blocked.md doc/master_plan.md doc/start_here.md CHANGELOG.md
  git commit -m "Record G6.2 lifecycle foundation boundary"
  ```

### Task 6: Run the complete verification gate

**Files:**

- Verify all files changed by Tasks 1-5.
- Do not modify tests or source to make a failing gate pass.

- [ ] **Step 1: Run the Zig unit test root with workspace caches.**

  ```bash
  mkdir -p .tmp/do-tmp/foundation-tmp .tmp/do-tmp/foundation-zig-cache .tmp/do-tmp/foundation-zig-gcache
  (
    export TMPDIR="$PWD/.tmp/do-tmp/foundation-tmp"
    export ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/foundation-zig-cache"
    export ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/foundation-zig-gcache"
    cd src && zig test main.zig
  )
  ```

  Expected: exit code `0`; record the fresh test count.

- [ ] **Step 2: Run the repository default regression.**

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp/foundation-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/foundation-zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/foundation-zig-gcache" \
  ./src/build/test/run_tests.sh
  ```

  Expected: zero failures and unchanged skip set.

- [ ] **Step 3: Run ReleaseSmall build and smoke.**

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp/foundation-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/foundation-zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/foundation-zig-gcache" \
  bash -lc 'cd src && zig build --prefix .. -Doptimize=ReleaseSmall'
  bash src/build/test/run_release_smoke.sh
  ```

  Expected: compiler installs successfully and release smoke passes.

- [ ] **Step 4: Run final repository checks.**

  ```bash
  git diff --check
  git status --short
  ```

  Expected: no whitespace errors; only intended source, test, and documentation changes are present.

- [ ] **Step 5: Create the final implementation commit.**

  If the task commits were used, verify the branch contains only those commits. Otherwise:

  ```bash
  git add src/build src/main.zig doc/pending_blocked.md doc/master_plan.md \
    doc/start_here.md CHANGELOG.md
  git commit -m "Complete G6.2 producer lifecycle foundation"
  ```

## Completion Criteria

- The two golden routes use the shared lifecycle validation path.
- Normal, pending, error, cancellation, early-drop, and repeat lifecycle paths are represented and validated by the same pure transition contract.
- Direct-route WAT/WIT byte parity and scalar/list ABI/runtime evidence remain green.
- Unsupported borrowed, variant, arbitrary, shared-lease, sixth-forwarding, and seventh-nesting cases remain rejected.
- No public ownership syntax, D2 generic async behavior, or ordinary GC semantics changed.
- Current status documents distinguish this internal foundation from generic G6.2 completion.

