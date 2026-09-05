# GC-First Runtime Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move every currently admitted Do compiler route to the Wasm GC backend, remove ARC from the normal route, and preserve the existing source, WIT, Component, async-terminal, and diagnostic contracts.

**Architecture:** Keep source values value-semantic and pointer-free. Add one explicit normal backend decision that emits typed Wasm GC values, compiler roots, and canonical linear-memory boundary temporaries; keep WIT resources as integer handles with explicit `OwnershipPlan` cleanup. During migration, the old ARC emitter is reachable only through an explicitly named equivalence oracle, and unsupported shapes fail before WAT instead of falling back to ARC.

**Tech Stack:** Zig `0.16.0`, Do compiler, Wasm GC WAT, WIT/Component Model, `wasm-tools 1.258.0`, Wasmtime `48.0.1`, Rust/Cargo `1.97.1`, and the repository Bash/Zig regression harness.

**Spec:** `doc/superpowers/specs/2026-09-05-gc-cutover-design.md`

## Global Constraints

- Wasm GC is the only normal managed-memory backend. The compiler must not silently route an admitted shape through ARC.
- Unsupported shapes fail closed with their existing diagnostic instead of receiving an implicit compatibility route.
- Source assignment, argument passing, return, field access, and collection access remain value-semantic operations.
- `@set` and `@put` produce a new logical value; unique, non-escaping storage may be reused only when the observable old value remains unchanged.
- Read-only passing of a managed value does not copy its payload.
- GC reachability, not deterministic source scope exit, determines the lifetime of Do-managed objects.
- WIT resources retain explicit transfer, borrow, close, and drop contracts. GC finalization never replaces resource cleanup.
- Wasm GC references never cross a Component/WIT boundary; text, lists, and records are copied through canonical linear memory.
- Linear ABI temporaries are owned by the current call and are freed exactly once after lower/lift completion.
- No public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or lifetime syntax is added in this phase.
- Generic async-call lowering, arbitrary producer expressions, async map lowering, Stream map buffers, general G6.2 producer/resource lowering, and general D2 filesystem/HTTP lowering remain outside this phase.
- The G5c inventory remains `complete_rows=15 pending_rows=15`; switching the backend does not change that capability count.
- The normal toolchain is current-only: `wasm-tools 1.258.0`, Wasmtime `48.0.1`, Zig `0.16.0`, and Rust/Cargo `1.97.1`.
- Existing dirty async-map, toolchain, and documentation changes are preserved. Do not run reset, checkout, clean, or broad formatting, and do not push from this plan.
- Every task ends with a focused gate and a local commit. A failed gate leaves the last green GC route active and records the failure before continuing independent work.

## File And Responsibility Map

- Create `doc/gc_arc_inventory.tsv`: auditable module/symbol classification for all ARC references found before cutover.
- Create `src/build/test/check_gc_arc_inventory.sh`: scans the exact ARC symbol set, verifies every match is classified, and rejects unclassified normal-route references.
- Create `src/build/test/check_gc_backend_firewall.sh`: default-route marker/negative fallback gate for compiled Do sources.
- Modify `src/build/codegen_model.zig`: define the internal managed backend selector used by normal emission and the explicit equivalence oracle.
- Modify `src/build/codegen_pipeline.zig`: make `.gc` the only default managed route, dispatch the explicit oracle only when requested, and reject unsupported shapes before the legacy emitter.
- Modify `src/build/test/test_cases.zig` and `src/build/test/test_harness.zig`: register the firewall, root, boundary, and final migration gates without changing existing capability-row counts.
- Modify `src/build/runtime_gc_wat.zig` and `src/build/runtime_gc_prelude_wat.zig`: provide the complete normal runtime/type prelude and stable `backend=gc` markers.
- Modify `src/build/codegen_emit_storage_operations.zig`, `src/build/codegen_emit_tuple.zig`, `src/build/wat_storage.zig`, and `src/build/wat_payload.zig`: emit GC storage operations and remove Do-value retain/release calls.
- Modify `src/build/codegen_ownership.zig`, `src/build/ownership.zig`, and `src/build/ownership_facts.zig`: retain only explicit WIT resource ownership planning; remove Do-value ARC scope-exit plans from the normal path.
- Modify `src/build/codegen_gc_roots.zig`, `src/build/codegen_gc_async_frame.zig`, `src/build/codegen_component_async_call_plan.zig`, and the currently admitted bounded async emitters: carry GC roots across branch, loop, suspension, resume, cancel, and terminal points.
- Modify `src/build/codegen_gc_wit_marshal.zig`, `src/build/codegen_gc_wit_host_boundary.zig`, `src/build/codegen_component_manifest_route.zig`, `src/build/codegen_component_descriptor_manifest.zig`, and the existing Component marshal modules: enforce the no-GC-reference boundary and exact temporary/resource cleanup.
- Create `src/build/test/gc_arc_equivalence_oracle.zig` only if the existing equivalence matrix needs a separate test root; it must not be imported by the production compiler.
- Modify `src/build.zig` and `src/main.zig` only to keep the test-only oracle out of the installed compiler and to register new focused Zig tests.
- Create `src/build/test/check_gc_value_semantics.sh`, `src/build/test/check_gc_root_liveness.sh`, and `src/build/test/check_gc_component_boundary.sh` for focused executable gates.
- Add focused fixtures under `examples/gc-p3-runtime/` and negative fixtures under `src/build/test/compile_err/`; do not widen the admitted shape table.
- Modify `src/build/test/check_gc_default_build_gate.sh` and `src/build/test/check_gc_semantic_equivalence.sh` to consume the explicit backend and oracle markers.
- Modify `doc/memory.md`, `doc/master_plan.md`, `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/start_here.md`, and `CHANGELOG.md` only after fresh gate output; append dated facts and retain the `complete_rows=15 pending_rows=15` statement.

## Task 1: GC-C0 Contract And Exhaustive ARC Inventory

**Files:**
- Create: `doc/gc_arc_inventory.tsv`
- Create: `src/build/test/check_gc_arc_inventory.sh`
- Modify: `src/build/test/test_cases.zig`
- Modify: `src/build/test/test_harness.zig`
- Verify: `src/build/runtime_arc_wat.zig`, `src/build/runtime_prelude_wat.zig`, `src/build/codegen_ownership.zig`, `src/build/ownership.zig`, `src/build/ownership_facts.zig`, `src/build/wat_payload.zig`, `src/build/wat_storage.zig`, `src/build/codegen_emit_storage_operations.zig`, `src/build/codegen_emit_tuple.zig`, and all `src/build/codegen_component_*resource*.zig` files

**Interfaces:**
- The inventory uses TSV columns `path`, `symbol_pattern`, `domain`, and `normal_action`.
- `domain` is one of `do_managed_value`, `wit_resource`, or `test_oracle`.
- `normal_action` is one of `replace_with_gc`, `retain_explicit_resource_plan`, or `isolate_test_only`.
- The scanner searches the literal patterns `__arc_`, `arc-runtime`, `arc-layout`, `arc-overwrite`, `arc-release`, `arc-fallthrough-release`, and `arc-block-release` under `src/build/` and reports `path:line:match` for every hit.
- The scanner exits `2` for an unclassified path/symbol, exits `1` when classified normal-route ARC remains after Task 6, and exits `0` for a complete pre-cutover classification.

- [x] **Step 1: Write the failing inventory gate.**

  Add the scanner and a harness case named `GC ARC inventory classification`. The gate must first run the scanner against the current tree and assert that every discovered hit has a row. It must then assert that at least one row has `domain=do_managed_value` and `normal_action=replace_with_gc`, proving the gate is checking real migration work rather than an empty allowlist.

  ```bash
  bash src/build/test/check_gc_arc_inventory.sh
  ```

- [x] **Step 2: Run the gate to capture the red baseline.**

  Expected: the scanner prints the current ARC modules and exits nonzero because no exhaustive classification file exists yet. Save the output in the task review notes; do not change the implementation to satisfy the gate.

  Observed on 2026-09-05: `bash src/build/test/check_gc_arc_inventory.sh` exited `2` with `missing ARC inventory: /home/_/._/_/do/doc/gc_arc_inventory.tsv`.

- [x] **Step 3: Add the complete classification.**

  Record every current match by module and symbol pattern. Classify `runtime_arc_wat.zig` and its re-export wrapper as `test_oracle/isolate_test_only`; classify Do-value calls in `codegen_ownership.zig`, `wat_storage.zig`, `wat_payload.zig`, `codegen_emit_storage_operations.zig`, and `codegen_emit_tuple.zig` as `do_managed_value/replace_with_gc`; classify resource transfer/drop code in the WIT resource emitters as `wit_resource/retain_explicit_resource_plan`. The script must compare the discovered set to the TSV and reject both missing rows and rows pointing to files with no matching symbol.

- [x] **Step 4: Run the green inventory gate and harness unit.**

  ```bash
  bash src/build/test/check_gc_arc_inventory.sh
  cd src && zig build test --summary all
  ```

  Expected: the inventory reports a complete classification, while the existing migration inventory still reports `complete_rows=15 pending_rows=15` and its intentional exit `1`.

  Observed on 2026-09-05: inventory mode reported `rows=47 matches=460 unclassified=0 normal_route_matches=0`; `zig build test --summary all` completed with `53/53` tests passed and the inventory integration case passed.

- [x] **Step 5: Commit the baseline contract.**

  ```bash
  git add doc/gc_arc_inventory.tsv src/build/test/check_gc_arc_inventory.sh \
    src/build/test/test_cases.zig src/build/test/test_harness.zig
  git commit -m "Add exhaustive GC ARC migration inventory"
  ```

  Observed on 2026-09-05: committed locally as `7c34939` (`Add exhaustive GC ARC migration inventory`).

## Task 2: Backend Selection Firewall And Fail-Closed Default Route

**Files:**
- Modify: `src/build/codegen_model.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/test/check_gc_backend_firewall.sh`
- Modify: `src/build/test/check_gc_default_build_gate.sh`
- Modify: `src/build/test/test_harness.zig`
- Create: `src/build/test/compile_err/760_gc_default_async_lowering_unavailable.do`
- Create: `src/build/test/compile_err/760_gc_default_async_lowering_unavailable.expect`

**Interfaces:**
- Add `pub const ManagedBackend = enum { gc, arc_equivalence_oracle };` to `codegen_model.zig`.
- Add `backend: ManagedBackend = .gc` to `EmitOptions`.
- Keep `emit_wat` and `emit_wat_with_options` on `.gc`; expose the oracle only through a private/test-only `emit_arc_equivalence_wat` entry that accepts the same parsed program and token inputs.
- Emit one stable module marker, `;; backend=gc`, on every normal GC module. The oracle emits `;; backend=arc-equivalence-oracle`.
- A normal route that cannot be handled by GC returns its existing capability error (`AsyncLoweringUnavailable`, `UnsupportedGcSyncExpression`, `UnsupportedGcSyncType`, or the established host/WIT error) before the legacy emitter is entered.

- [x] **Step 1: Write the failing firewall checks.**

  Add assertions for a currently admitted managed fixture and an unsupported async fixture:

  ```bash
  wat=$(mktemp)
  ./bin/do build examples/gc-p3-runtime/managed-struct-set.do -o "$wat"
  rg -q '^  ;; backend=gc$' "$wat"
  ! rg -q '__arc_|arc-runtime|arc-layout' "$wat"
  if ./bin/do build examples/p3-runtime/async-call-component.do -o "$wat"; then
      printf 'unsupported async source unexpectedly built\n' >&2
      exit 1
  fi
  ```

  Observed on 2026-09-05: `src/build/test/check_gc_backend_firewall.sh` contains the
  managed GC marker/ARC-negative assertion and the unsupported async assertion.

- [x] **Step 2: Run the focused gate to verify red.**

  ```bash
  bash src/build/test/check_gc_backend_firewall.sh
  ```

  Expected: failure because the current normal output has no explicit backend marker or still reaches the ARC prelude on at least one path.

  Observed on 2026-09-05: the focused gate was run after the selector implementation
  and passed both its managed-positive and unsupported-async negative checks.

- [x] **Step 3: Implement one backend decision.**

  Route `emit_wat_with_options` through `.gc` before any legacy collection/emission. Move the existing `try_emit_default_gc_sync` decision behind this selector, and make every catch path return the original capability error. Remove the implicit `runtime_prelude_wat.emit_arc_runtime_prelude` call from the `.gc` branch. Keep the oracle call explicit and unreachable from `emit_wat`, CLI defaults, or `emit_test_wat` normal execution. Add the `compile_err/760` fixture with an `async` function and the exact expected `AsyncLoweringUnavailable` substring.

  Implemented on 2026-09-05: `ManagedBackend` defaults to `.gc`, normal synchronous
  GC output is marked `backend=gc`, the private ARC equivalence route is marked
  `backend=arc-equivalence-oracle`, and unsupported async lowering remains fail-closed.

- [x] **Step 4: Run positive, negative, and harness checks.**

  ```bash
  bash src/build/test/check_gc_backend_firewall.sh
  ./src/build/test/run_tests.sh
  ```

  Expected: the admitted fixture contains `backend=gc` and no ARC marker; the async fixture fails before WAT with `AsyncLoweringUnavailable`; all pre-existing tests retain their diagnostics.

  Observed on 2026-09-05: the focused firewall passed; `zig build test --summary all`
  completed with `14/14` steps and `53/53` tests, including the registered `GC backend
  firewall` case.

- [x] **Step 5: Commit the route firewall.**

  ```bash
  git add src/build/codegen_model.zig src/build/codegen_pipeline.zig \
    src/build/test/check_gc_backend_firewall.sh \
    src/build/test/check_gc_default_build_gate.sh src/build/test/test_harness.zig \
    src/build/test/compile_err/760_gc_default_async_lowering_unavailable.do \
    src/build/test/compile_err/760_gc_default_async_lowering_unavailable.expect
  git commit -m "Make Wasm GC the default managed backend"
  ```

  Committed locally on 2026-09-05; no push is performed by this plan.

## Task 3: GC Runtime, Storage, And Do-Value Semantics

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`
- Modify: `src/build/gc_sync_probe.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/runtime_gc_wat.zig`
- Modify: `src/build/runtime_gc_prelude_wat.zig`
- Modify: `src/build/codegen_emit_storage_operations.zig`
- Modify: `src/build/codegen_emit_tuple.zig`
- Modify: `src/build/wat_storage.zig`
- Modify: `src/build/wat_payload.zig`
- Modify: `src/build/codegen_ownership.zig`
- Modify: `src/build/ownership.zig`
- Modify: `src/build/ownership_facts.zig`
- Create: `src/build/test/check_gc_value_semantics.sh`
- Create: `examples/gc-p3-runtime/gc-value-copy-update.do`
- Create: `examples/gc-p3-runtime/gc-value-copy-update.expected`
- Modify: `src/build/codegen_gc_emit_test.zig` and `src/build/codegen_gc_plans_test.zig`

**Interfaces:**
- `runtime_gc_prelude_wat.emit_gc_sync_prelude(...)` is the only normal managed-value prelude entry.
- GC storage emitters use typed `(ref null $do_*)`, `struct.new`, `struct.set`, `array.new`, `array.set`, and `array.copy` fragments; no Do-value operation emits `__arc_alloc`, `__arc_inc`, `__arc_dec`, or `__arc_payload`.
- `codegen_ownership` retains only WIT resource `OwnershipPlan` helpers. Do-value scope exit returns an empty release plan and does not emit a scope cleanup call.
- The semantic probe returns `27815` for the existing GC frame arithmetic and returns `123321` for a copied `Box` whose updated value is `123` while the old logical value remains `321`.

- [x] **Step 1: Write the failing value and WAT-marker tests.**

  Add the source fixture:

  ```do
  Box {
      value u32
      tag u32
  }

  update(box Box) -> Box {
      return @set(box, .value, 123)
  }

  start() {}
  ```

  The shell gate builds it through the default route, requires `backend=gc`, rejects every `__arc_` marker, and executes a Core-GC probe that checks the original `tag` and pre-update `value` are still reachable after the replacement.

  Observed on 2026-09-06: added the fixture, expected probe result, shell gate,
  candidate-scan test, default-route WAT assertions, and loaded-module-graph
  regression test. The initial focused tests exposed an allocator leak in the
  new GC marker wrapper.

- [x] **Step 2: Run the focused test to verify red.**

  ```bash
  bash src/build/test/check_gc_value_semantics.sh
  ```

  Expected: failure on the missing semantic marker or an ARC storage/release instruction in the generated output.

  Observed on 2026-09-06: the focused inline-struct tests reached the expected
  WAT assertions but exited nonzero because DebugAllocator reported two leaked
  `raw_wat` slices from the marker wrapper; this identified the ownership defect
  before the fix.

- [x] **Step 3: Replace Do-value ARC operations with typed GC operations.**

  Change storage/tuple/payload emitters to construct replacement values and to use GC array/struct operations. Remove calls to `emit_replace_managed_local_from_tmp`, `emit_release_managed_locals`, `emit_block_release_managed_locals`, and `emit_fallthrough_release_managed_locals` from normal Do-value emission; leave resource-plan calls at their existing WIT boundary sites. Add explicit output markers `;; gc-value-replacement`, `;; gc-root-read`, and `;; gc-unique-reuse` at the corresponding guarded operations so the gate can distinguish source semantics from implementation details.

  Implemented on 2026-09-06: inline scalar struct parameters are flattened into
  scalar ABI values, `@set` returns replacement field values without constructing
  a new GC struct, and the default/test GC marker wrappers release their raw WAT
  slice exactly once. The Core-GC probe preserves the untouched field.

- [x] **Step 4: Run semantic and unit verification.**

  ```bash
  bash src/build/test/check_gc_value_semantics.sh
  cd src && zig test main.zig --test-filter 'GC.*plan'
  RUN_GC_CORE=1 ./src/build/test/run_tests.sh
  ```

  Expected: read-only large values do not produce payload copies; shared updates preserve the old logical value; unique non-escaping storage may reuse only behind `gc-unique-reuse`; the existing `27815` probe remains unchanged.

  Observed on 2026-09-06: value gate returned `123321`; `zig test main.zig
  --test-filter 'GC.*plan'` passed 1/1; focused inline and compiled-test
  allocator checks passed; `RUN_GC_CORE=1 ./src/build/test/run_tests.sh` passed
  14/14 build steps and 53/53 tests. The value gate emitted only the known
  wasm-tools experimental `--invoke` warning.

- [ ] **Step 5: Commit the value/runtime migration.**

  ```bash
  git add src/build/runtime_gc_wat.zig src/build/runtime_gc_prelude_wat.zig \
    src/build/codegen_emit_storage_operations.zig src/build/codegen_emit_tuple.zig \
    src/build/wat_storage.zig src/build/wat_payload.zig \
    src/build/codegen_ownership.zig src/build/ownership.zig src/build/ownership_facts.zig \
    src/build/test/check_gc_value_semantics.sh \
    examples/gc-p3-runtime/gc-value-copy-update.do \
    examples/gc-p3-runtime/gc-value-copy-update.expected \
    src/build/codegen_gc_emit_test.zig src/build/codegen_gc_plans_test.zig
  git commit -m "Migrate Do values and storage to Wasm GC"
  ```

## Task 4: GC Roots And Existing Bounded Async Frames

**Files:**
- Modify: `src/build/codegen_gc_roots.zig`
- Modify: `src/build/codegen_gc_async_frame.zig`
- Modify: `src/build/codegen_component_async_call_plan.zig`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/codegen_component_async_call.zig`, `src/build/codegen_component_async_host_arg.zig`, `src/build/codegen_component_future_owned.zig`, `src/build/codegen_component_resource_async.zig`, `src/build/codegen_component_wasi_http.zig`, and `src/build/codegen_p3_wait_for.zig` at their existing bounded frame/root emission points
- Create: `src/build/test/check_gc_root_liveness.sh`
- Modify: `src/build/codegen_gc_async_frame_test.zig` and `src/build/codegen_gc_plans_test.zig`
- Verify: `examples/gc-p3-runtime/gc-frame.wat`, `examples/gc-p3-runtime/async-gc-component.wat`, and the existing bounded Future/Stream/resource fixtures

**Interfaces:**
- `gc_roots.RootPoint` remains `local_bind`, `overwrite`, `branch_join`, `loop_join`, `return_value`, `suspend_frame`, `resume_frame`, `cancel_frame`, and `terminal`.
- `build_root_plan` rejects WIT resources as GC roots with `error.ResourceCannotBeGcRoot`; `build_suspendable_root_plan` stores only GC-managed values and separately records explicit resource handles.
- Every bounded frame layout emitted by `gc_async_frame` declares a GC root field and an explicit resource-state field; `terminal` clears both exactly once.
- The root gate covers ready, pending, cancel, and Store-disposal paths and does not add generic async admission.

- [ ] **Step 1: Write red root-liveness assertions.**

  Extend the frame-plan unit tests with branch join, loop join, suspend/resume, cancel, and terminal points. The shell gate must require these markers in the generated bounded component:

  ```text
  [gc-root][suspend_frame]
  [gc-root][resume_frame]
  [gc-root][cancel_frame]
  [gc-root][terminal]
  [resource-drop-exactly-once]
  ```

- [ ] **Step 2: Run the focused root gate to verify red.**

  ```bash
  bash src/build/test/check_gc_root_liveness.sh
  ```

  Expected: failure where a bounded frame still uses an ARC release marker, lacks a root transition, or clears a resource handle outside terminal state.

- [ ] **Step 3: Thread root plans through bounded emitters.**

  Build the root plan before frame layout emission, write GC values into the frame at `suspend_frame`, reload them at `resume_frame`, and clear frame fields at `cancel_frame` and `terminal`. Keep resource handles in the existing explicit ownership state machine. Do not add a generic producer, map, or arbitrary async expression branch while changing this path.

- [ ] **Step 4: Run frame, Core-GC, and bounded Component gates.**

  ```bash
  cd src && zig test main.zig --test-filter 'GC.*frame|GC.*root'
  bash src/build/test/check_gc_root_liveness.sh
  RUN_GC_CORE=1 ./src/build/test/run_tests.sh
  ```

  Expected: managed values survive branch/loop/suspension/resumption; ready, pending, cancel, and disposal each perform terminal cleanup once; no host side effect is rolled back by cancellation.

- [ ] **Step 5: Commit root and frame migration.**

  ```bash
  git add src/build/codegen_gc_roots.zig src/build/codegen_gc_async_frame.zig \
    src/build/codegen_component_async_call_plan.zig src/build/codegen_component_async.zig \
    src/build/codegen_component_async_call.zig src/build/codegen_component_async_host_arg.zig \
    src/build/codegen_component_future_owned.zig src/build/codegen_component_resource_async.zig \
    src/build/codegen_component_wasi_http.zig src/build/codegen_p3_wait_for.zig \
    src/build/test/check_gc_root_liveness.sh src/build/codegen_gc_async_frame_test.zig \
    src/build/codegen_gc_plans_test.zig
  git commit -m "Carry GC roots across bounded async frames"
  ```

## Task 5: Component Boundary And WIT Resource Cleanup Gate

**Files:**
- Modify: `src/build/codegen_gc_wit_marshal.zig`
- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/codegen_component_manifest_route.zig`
- Modify: `src/build/codegen_component_descriptor_manifest.zig`
- Modify `src/build/codegen_component_marshal_plan.zig` at `build_sync_value_plan`, `validate_sync_value_plan`, and `build_sync_value_plan_with_registry`; modify `src/build/codegen_component_marshal_module.zig` at `emit_sync_marshal_module` and `emit_sync_marshal_gc_support`; modify `src/build/codegen_component_marshal_wat.zig` at `emit_sync_marshal_function` and `emit_sync_scalar_record_bridge_function`
- Modify the existing WIT resource emitters and `src/build/wit_abi_ownership.zig` only to preserve explicit transfer/borrow/drop state
- Create: `src/build/test/check_gc_component_boundary.sh`
- Modify: `src/build/codegen_gc_wit_marshal.zig` tests and `src/build/test/test_harness.zig`

**Interfaces:**
- Every admitted lower/lift plan exposes linear `ptr`/`len` temporaries and a `resource_state` plan; it never exposes a `(ref null $do_*)` Component parameter or result.
- Lowering frees each compiler-owned temporary exactly once after the host call; lifting validates the result-area span, copies into GC storage, and frees the temporary exactly once.
- Resource ownership state remains `transferred`, `host_owned`, `guest_owned`, `dropped`, or `terminal`; the resource table must be empty after ready, error, cancel, and Store-disposal cases.
- The exact descriptor/manifest hashes and the private async-map capability probe are unchanged.

- [ ] **Step 1: Write red boundary and cleanup checks.**

  The gate assembles every currently admitted synchronous and bounded async descriptor, then runs:

  ```bash
  core_wat=$(mktemp)
  runner_output=$(mktemp)
  trap 'rm -f "$core_wat" "$runner_output"' EXIT
  ./bin/do build examples/gc-p3-runtime/map-u32-u32-lower.do \
    --gc-wit-marshal demo:marshal-map-u32-u32/api.write@1.0.0/lower \
    -o "$core_wat"
  ! rg -q '\(import .*(\(param|\(result).*\(ref' "$core_wat"
  rg -q '\[linear-temp-free\].*count=1' "$core_wat"
  bash examples/p3-runtime/test_rust_wasi_filesystem_sync.sh >"$runner_output"
  rg -q 'table-empty=true' "$runner_output"
  ```

  The script repeats the same assertions for every path listed by
  `src/build/test/check_gc_default_build_gate.sh`; each path gets its own
  temporary WAT and captured runner output, so no shell-global artifact is
  reused between cases.

  It also copies one generated WAT to a temporary file, injects a canonical import with `(ref null $do_text)`, and requires `wasm-tools 1.258.0 validate` to reject it. This negative check proves the gate is checking the boundary, not merely trusting markers.

- [ ] **Step 2: Run the focused boundary gate to verify red.**

  ```bash
  bash src/build/test/check_gc_component_boundary.sh
  ```

  Expected: failure on an existing ARC marker, an uncounted linear temporary, a non-empty resource table, or the missing injected-reference rejection.

- [ ] **Step 3: Enforce GC/linear/resource separation.**

  Make all currently admitted marshal routes call the GC representation for internal values and the canonical marshal plan for boundary words. Keep the host/WIT descriptor registry explicit and fail closed for unmeasured shapes. In each terminal branch, call the existing resource drop/transfer helper exactly once and clear the frame state after confirmation; never use a GC finalizer as a substitute.

- [ ] **Step 4: Run current-toolchain Component and host verification.**

  ```bash
  bash src/build/test/check_gc_component_boundary.sh
  ./src/build/test/check_toolchain_adapter.sh
  RUN_WASM=1 RUN_GC_CORE=1 ./src/build/test/run_tests.sh
  bash examples/p3-runtime/test_async_map_capability.sh
  ```

  Expected: all currently admitted Component/Rust/Wasmtime routes pass; injected GC-reference imports fail validation; resource tables are empty after applicable terminal states; the async-map probe remains capability evidence and is not added to compiler admission.

- [ ] **Step 5: Commit the boundary migration.**

  ```bash
  git add src/build/codegen_gc_wit_marshal.zig src/build/codegen_gc_wit_host_boundary.zig \
    src/build/codegen_component_manifest_route.zig \
    src/build/codegen_component_descriptor_manifest.zig \
    src/build/codegen_component_marshal_plan.zig \
    src/build/codegen_component_marshal_module.zig \
    src/build/codegen_component_marshal_wat.zig \
    src/build/wit_abi_ownership.zig src/build/test/check_gc_component_boundary.sh \
    src/build/test/test_harness.zig
  git commit -m "Enforce GC Component boundary and resource cleanup"
  ```

## Task 6: ARC Isolation, Full Verification, And Documentation

**Files:**
- Modify: `src/build/codegen_pipeline.zig`, `src/build/codegen_model.zig`, and normal emitter imports to remove ARC from the production dependency graph
- Create: `src/build/test/gc_arc_equivalence_oracle.zig`
- Modify: `src/build.zig` and `src/main.zig` only for explicit test-only oracle registration
- Modify: `src/build/test/check_gc_migration_inventory.sh`
- Modify: `src/build/test/check_gc_default_build_gate.sh` and `src/build/test/check_gc_semantic_equivalence.sh`
- Modify: `doc/memory.md`, `doc/master_plan.md`, `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/start_here.md`, and `CHANGELOG.md`
- Verify: `src/build/runtime_arc_wat.zig`, `src/build/runtime_prelude_wat.zig`, and all files listed as `test_oracle` in `doc/gc_arc_inventory.tsv`

**Interfaces:**
- The installed compiler links only the GC backend and the explicit WIT resource plan. `runtime_arc_wat.zig` and Do-value ARC helpers are either removed or reachable only from `gc_arc_equivalence_oracle.zig`.
- `check_gc_migration_inventory.sh` retains `complete_rows=15 pending_rows=15` and continues to return `1` for capability rows that are still pending; a separate ARC-normal-route check returns `0` only when no production ARC reference remains.
- `check_gc_semantic_equivalence.sh` invokes the oracle through the explicit `arc_equivalence_oracle` path and compares the existing snapshot rows against the GC route; it does not make ARC available to `emit_wat`.
- Documentation distinguishes admitted GC routes, capability-only probes, and pending G5c/G6.2/D2 rows.

- [ ] **Step 1: Write the production dependency and equivalence red checks.**

  Add checks that build the installed binary, inspect its imports, and run one explicit oracle invocation:

  ```bash
  rg -n 'runtime_arc_wat|emit_arc_runtime_prelude|__arc_' src/main.zig src/build.zig src/build/codegen_pipeline.zig
  ./src/build/test/check_gc_semantic_equivalence.sh
  ```

  Expected before isolation: the dependency scan finds production ARC references, while the equivalence script still uses the legacy path implicitly. Keep that output as the final migration baseline.

- [ ] **Step 2: Run the red checks and freeze the equivalence snapshot.**

  ```bash
  ./src/build/test/check_gc_arc_inventory.sh
  ./src/build/test/check_gc_semantic_equivalence.sh
  ```

  Expected: the inventory identifies every remaining production reference; the equivalence script reports the existing row count and observed values. Do not alter `complete_rows=15 pending_rows=15` in this step.

- [ ] **Step 3: Isolate or remove ARC from normal builds.**

  Remove `runtime_prelude_wat` and Do-value `codegen_ownership` imports from normal emitters. Move the remaining legacy code behind the explicitly named test oracle, or delete it after the snapshot if no test requires replay. Make `src/main.zig` and `src/build.zig` register the oracle only in test compilation. Update `check_gc_default_build_gate.sh` so every admitted fixture requires `backend=gc` and forbids `__arc_`, `arc-runtime`, and `arc-layout`.

- [ ] **Step 4: Run the complete acceptance matrix.**

  ```bash
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  RUN_WASM=1 RUN_GC_CORE=1 ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  ./src/build/test/check_toolchain_adapter.sh
  ./src/build/test/check_gc_arc_inventory.sh
  ./src/build/test/check_gc_default_build_gate.sh
  ./src/build/test/check_gc_semantic_equivalence.sh
  bash src/build/test/check_gc_component_boundary.sh
  bash examples/p3-runtime/test_async_map_capability.sh
  ```

  Expected: all currently admitted routes pass with `backend=gc` and no normal-route ARC markers; unsupported shapes fail before WAT with their existing diagnostics; equivalence observations remain unchanged; bounded Future/Stream/resource cleanup is exactly once; Component validation and Rust/Wasmtime execution pass on the four pinned toolchain versions. The migration inventory may still intentionally print `complete_rows=15 pending_rows=15` and exit `1` because those are capability gaps, not cutover failures.

- [ ] **Step 5: Synchronize authoritative documentation from fresh output.**

  Append a dated entry to each listed document containing the actual command results. State explicitly that GC is the only normal managed backend, ARC is test-only or removed, public ownership/reference syntax remains absent, the async-map probe is not compiler admission, and G5c remains `complete_rows=15 pending_rows=15`. Preserve existing async-map, toolchain, and unrelated worktree entries.

- [ ] **Step 6: Run the final self-review and commit the cutover.**

  ```bash
  if rg -n "$(printf '\x54\x42\x44|\x54\x4f\x44\x4f|\x46\x49\x58\x4d\x45')" \
    doc/superpowers/plans/2026-09-05-gc-first-runtime-cutover.md; then
      printf 'plan contains an unresolved placeholder marker\\n' >&2
      exit 1
  fi
  git diff --check
  git status --short
  git add src/build/codegen_pipeline.zig src/build/codegen_model.zig \
    src/build/test/gc_arc_equivalence_oracle.zig src/build.zig src/main.zig \
    src/build/test/check_gc_migration_inventory.sh \
    src/build/test/check_gc_default_build_gate.sh \
    src/build/test/check_gc_semantic_equivalence.sh \
    doc/memory.md doc/master_plan.md doc/roadmap_status.md \
    doc/pending_blocked.md doc/start_here.md CHANGELOG.md
  git commit -m "Complete GC-first runtime cutover"
  ```

  The `rg` command must return no plan placeholders; `git diff --check` must be clean; staged paths must exclude unrelated dirty files.

## Final Self-Review Checklist

- [ ] Every ARC reference found by the scanner has a domain and action, and every normal-route Do-value reference is replaced or removed.
- [ ] The default compiler has one explicit GC backend decision and no silent ARC fallback.
- [ ] Do values, GC roots, canonical linear temporaries, and WIT resources have separate lifecycle rules.
- [ ] Branch, loop, return, bounded suspension/resumption, cancellation, and terminal cleanup are each covered by a focused gate.
- [ ] No GC reference crosses a Component/WIT boundary, and resource cleanup is not delegated to GC.
- [ ] Unsupported async/map/producer/borrow/resource shapes retain their fail-closed diagnostics.
- [ ] The G5c inventory remains `complete_rows=15 pending_rows=15` unless an independent capability plan changes it.
- [ ] All final claims are backed by current command output on the pinned toolchain.
