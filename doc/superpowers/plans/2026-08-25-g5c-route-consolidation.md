# G5c Route Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with review checkpoints. Preserve unrelated dirty changes in the current `main` checkout.

**Goal:** Make the existing C14–C20 bounded synchronous GC/WIT routes consume one manifest-backed validated request while preserving every current fail-closed boundary and leaving the global GC migration ledger open.

**Architecture:** Reuse `codegen_component_descriptor_manifest.LoadedRequest` as the ownership boundary. The loader resolves the manifest, source hash, WIT member, measured layout, canonical ABI and host-boundary field tree once; default host admission and explicit marshal probes consume that request. Descriptor IDs remain lookup keys, not shape tables; the existing `SyncValuePlan` and WAT emitters remain the single lowering model.

**Tech Stack:** Zig 0.16.0 compiler/tests, WIT parser and manifest loader, `.do` compile fixtures, pinned `wasm-tools 1.255.0`, Wasmtime 47.0.2 host/equivalence gates, Bash regression scripts.

**Spec:** `doc/superpowers/specs/2026-08-25-g5c-route-consolidation-design.md`

## Global Constraints

- Keep the current `main` checkout and preserve unrelated dirty/untracked files; stage only files belonging to this plan if an explicit commit is requested.
- Keep the admitted C14–C20 synchronous descriptor set unchanged.
- Keep unknown descriptors, async/resource shapes, generic aggregates, borrowed payloads, `own<T>`, `borrow<T>`, `ref<T>`, `Option` and `Result` fail-closed.
- Keep canonical Component/WIT imports free of Wasm GC reference types.
- Validate every linear pointer/length span before reading or copying it.
- Emit and test exactly-once cleanup in the existing measured order.
- Retain ARC only as fallback/equivalence oracle; do not close or edit the migration inventory rows.
- Use only `wasm-tools 1.255.0`, Wasmtime 47.0.2 and Zig 0.16.0 for gates.

---

### Task 1: Make the loaded request own the derived host-boundary facts

**Files:**

- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/codegen_component_descriptor_manifest.zig`
- Test: `src/build/codegen_component_descriptor_manifest.zig`
- Test: `src/build/codegen_gc_wit_host_boundary.zig`

**Interfaces:**

- Add an owned recursive field tree with a deterministic `deinit` path. The
  tree must expose the existing `HostBoundarySpec` view without borrowing the
  temporary WIT binding.
- Add a request-based validator with this signature:

```zig
pub fn validate_loaded_host_boundary(
    loaded: *const LoadedRequest,
    tokens: []const lexer.Token,
) !void
```

- `load_request_internal` must construct the field tree while the resolved WIT
  binding is live, deep-copy any WIT-owned names, and store it in
  `LoadedRequest`.
- `validate_host_boundary_from_manifest` must become a compatibility wrapper
  that calls `load_request_from_manifest`, then `validate_loaded_host_boundary`,
  then `deinit`; it may not repeat manifest/source/hash/WIT resolution.

- [ ] **Step 1: Add a failing ownership test.**

  Add a test that loads
  `demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift`, calls
  `validate_loaded_host_boundary` with fixture 648, then calls `loaded.deinit()`.
  Use `std.testing.allocator` so a missing nested-field or copied-string free
  fails the test.

- [ ] **Step 2: Add the owned boundary type and deinitializer.**

  Store owned locator/member/record-name strings and recursively owned
  `HostBoundaryField` names/types. `deinit` must release children first, then
  strings, then the request's existing plan/measurement/manifest/source.

- [ ] **Step 3: Factor request loading around one binding resolution.**

  Keep the existing order: read manifest -> find descriptor -> read source and
  world source -> concatenate -> verify `source_sha256` -> resolve WIT -> check
  binding claims -> derive host fields -> build measured `SyncValuePlan`.
  Return the complete request only after both host fields and plan succeed.

- [ ] **Step 4: Run the focused loader tests.**

  ```bash
  cd src
  zig test build/codegen_component_descriptor_manifest.zig --test-filter 'owned host boundary'
  zig test build/codegen_gc_wit_host_boundary.zig --test-filter 'loaded host boundary'
  ```

  Expected result: all existing tests plus the ownership test pass, with no
  allocator leak and no change to current diagnostics.

### Task 2: Replace hard-coded production admission dispatch with a single registry lookup

**Files:**

- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/run.zig`
- Modify: `src/build/codegen_gc_wit_marshal.zig`
- Test: `src/build/run.zig`
- Test: `src/build/codegen_gc_wit_host_boundary.zig`

**Interfaces:**

- Add one table-backed lookup in `codegen_gc_wit_host_boundary.zig`:

```zig
pub fn descriptor_id_for_host(locator: []const u8, member: []const u8) ?[]const u8
```

  The table contains only the currently admitted descriptor IDs and their
  canonical locator/member pairs. It contains no field layout or emitter data.
- Add a descriptor allowlist predicate used by explicit marshal dispatch:

```zig
pub fn is_admitted_descriptor(descriptor_id: []const u8) bool
```

- Keep the existing `validate(tokens, descriptor_id)` and fixed literals only
  for standalone compatibility tests until all callers use loaded requests;
  production default/explicit routes must not use those literals as shape
  truth.

- [ ] **Step 1: Write registry tests before changing callers.**

  Verify every current C14–C20 locator/member maps to its manifest descriptor,
  an unknown locator returns `null`, and an async/member mismatch does not map.

- [ ] **Step 2: Implement the table-backed lookup.**

  Use one `[]const AdmissionEntry` and a linear guard-style search. Do not add
  a second shape registry or infer a descriptor from a similar record.

- [ ] **Step 3: Rewire `run.zig`.**

  Replace the `if` chain in `admitted_gc_host_descriptor` with the shared
  lookup. The selected descriptor is still loaded from the manifest, and the
  request-based validator from Task 1 is called on the already-loaded request.

- [ ] **Step 4: Rewire explicit marshal admission.**

  Replace the boolean descriptor list at the start of
  `codegen_gc_wit_marshal.emit_module` with `is_admitted_descriptor`. Unknown
  IDs must still return `error.UnsupportedGcWitMarshalDescriptor` before WAT.

- [ ] **Step 5: Run focused dispatch tests.**

  ```bash
  cd src
  zig test build/run.zig --test-filter 'GC host admission'
  zig test build/codegen_gc_wit_host_boundary.zig --test-filter 'descriptor registry'
  zig test build/codegen_gc_wit_marshal.zig --test-filter 'unknown descriptor'
  ```

### Task 3: Make default and explicit routes consume the same loaded request

**Files:**

- Modify: `src/build/run.zig`
- Modify: `src/build/codegen_component_manifest_route.zig`
- Modify: `src/build/codegen_gc_wit_marshal.zig`
- Test: `src/build/codegen_component_manifest_route_test.zig`
- Test: `src/build/codegen_gc_plans_test.zig`

**Interfaces:**

- Add a manifest-route entry point that accepts an already-loaded request:

```zig
pub fn emit_sync_marshal_module_from_loaded_request(
    allocator: std.mem.Allocator,
    loaded: *const descriptor_loader.LoadedRequest,
    canonical_u64_arg: ?u64,
    emit_realloc_counters: bool,
) ![]u8
```

- Keep existing public wrappers as compatibility adapters that load once and
  delegate to the new entry point.
- `run.zig` must retain one request lease through host validation and ordinary
  code generation.
- `codegen_gc_wit_marshal.emit_module` must load and validate once before any
  specialized probe wrapper is selected. A probe wrapper may add `$run`/stats
  presentation, but it must consume the loaded plan and must not reload the
  manifest or perform a second shape admission.

- [ ] **Step 1: Add the loaded-request route test.**

  Build the C20 source fixture through the new entry point and assert that the
  output contains `(type $canonical_lift (func (param i32)))`, the canonical
  import, `$do_record`, `$do_bytes`, and no `(ref` in the import declaration.

- [ ] **Step 2: Implement the loaded-request emitter entry point.**

  Move the existing `marshal_route.emit_sync_marshal_module_from_plan` call
  behind the new function. The compatibility wrappers must only load/deinit
  and delegate.

- [ ] **Step 3: Rewire the default route lease.**

  In `load_default_gc_host_route`, load the request once, validate its owned
  host-boundary spec, and retain that request in `GcHostRouteLease` until all
  generated host imports and route WAT are complete.

- [ ] **Step 4: Rewire explicit probe selection.**

  Preserve the existing C14–C20 `$run` result/stat wrappers, but pass the loaded
  plan into the generic base emitter. Unknown and structurally drifted sources
  must fail before wrapper text is appended.

- [ ] **Step 5: Run route focused tests.**

  ```bash
  cd src
  zig test build/codegen_component_manifest_route_test.zig --test-filter 'loaded request'
  zig test build/codegen_gc_plans_test.zig
  zig test build/codegen_gc_wit_marshal.zig --test-filter 'managed'
  zig test build/codegen_gc_wit_marshal.zig --test-filter 'list'
  zig test build/codegen_gc_wit_marshal.zig --test-filter 'mixed'
  ```

### Task 4: Lock shared span guards and exactly-once cleanup at the plan/emitter boundary

**Files:**

- Modify only if focused tests expose a missing invariant: `src/build/codegen_component_marshal_plan.zig`, `src/build/codegen_component_marshal_ops.zig`, `src/build/codegen_component_marshal_wat.zig`
- Test: the same three marshal modules plus C14–C20 WAT fixtures

**Interfaces:**

- Keep `marshal.SyncValuePlan` as the only emitter input.
- Every managed text/list operation must expose measured pointer offset,
  length offset, stride, capacity and free action to the emitter.
- The emitted operation order is:

```text
canonical_call -> validate_linear_span -> copy_linear_payload
-> construct_gc_value -> publish_gc_root -> cleanup_each_linear_allocation_once
```

- [ ] **Step 1: Add failing WAT assertions for all admitted list/text routes.**

  Assert the guard precedes the first `i32.load`/`i32.load8_u`, canonical imports
  contain no GC reference type, and the number/order of `cabi_realloc` frees
  matches the manifest measurement.

- [ ] **Step 2: Reuse existing operation metadata.**

  If the assertions fail, add the smallest pure validation helper at the plan
  boundary and make the WAT emitter consume it. Do not add descriptor-specific
  offsets or cleanup branches to the emitter.

- [ ] **Step 3: Run focused WAT and parser gates.**

  ```bash
  cd src
  zig test build/codegen_component_marshal_plan.zig --test-filter 'GC reference'
  zig test build/codegen_component_marshal_plan.zig --test-filter 'measured'
  zig test build/codegen_component_marshal_wat.zig --test-filter 'cleanup'
  zig test build/codegen_component_marshal_wat.zig --test-filter 'span'
  zig test build/codegen_component_marshal_wat.zig --test-filter 'mixed text'
  ```

  The existing C14–C20 host/equivalence gates run `wasm-tools parse` on each
  generated module; a missing temporary module is a test failure, not a skip.

### Task 5: Run the complete gates and update stage evidence

**Files:**

- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/pending_blocked.md`
- Modify only when a test is genuinely added: focused C14–C20 gate scripts

**Interfaces:**

- No migration inventory row is edited or marked complete.
- All current positive, equivalence and negative scripts continue to use the
  pinned toolchain and report their observed host counters.

- [ ] **Step 1: Run focused C14–C20 host/equivalence/negative gates.**

  Run the existing focused scripts selected by this command and record the
  exit code and observed counters. A script failure stops this task.

  ```bash
  find examples/gc-p3-runtime -maxdepth 1 -type f -name 'test_gc_*.sh' -print0 |
  while IFS= read -r -d '' script; do
    case "$script" in
      *marshal_record*|*default_host_route*|*mixed_text*|*u32_list*|*byte_list*|*nested*|*managed*)
        bash "$script" || exit 1
        ;;
    esac
  done
  ```

- [ ] **Step 2: Run the default and compiler suites.**

  ```bash
  ./src/build/test/run_tests.sh
  cd src && zig test main.zig
  cd ..
  set +e
  ./src/build/test/check_gc_migration_inventory.sh
  inventory_status=$?
  set -e
  test "$inventory_status" -eq 1
  ```

  Expected: the full regression and Zig unit suite pass; the inventory retains
  `complete_rows=15 pending_rows=15` and its deliberate exit `1`.

- [ ] **Step 3: Run release and formatting checks.**

  ```bash
  cd src && zig build -Doptimize=ReleaseSmall
  cd .. && git diff --check
  ```

- [ ] **Step 4: Update evidence documents.**

  Record the shared-request behavior, unchanged admitted descriptor list,
  focused gate results, and any residual issue in the three status documents.
  Do not describe route consolidation as full GC cutover.

- [ ] **Step 5: Review the final diff.**

  ```bash
  git status --short
  git diff --stat -- \
    src/build/codegen_gc_wit_host_boundary.zig \
    src/build/codegen_component_descriptor_manifest.zig \
    src/build/codegen_component_manifest_route.zig \
    src/build/codegen_gc_wit_marshal.zig \
    src/build/run.zig \
    doc/roadmap_status.md doc/start_here.md doc/pending_blocked.md
  ```

  Confirm no unrelated dirty file is staged or modified by this plan.
