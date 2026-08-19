# GC G5a Aggregate Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the next bounded G5a Wasm GC aggregate slices and produce executable evidence for pure payload unions, nested aggregate layout, Tuple/storage boundaries, and resolved generic managed calls without changing the default ARC route.

**Architecture:** Continue the parsed complete-program GC entry in `codegen_gc_sync.zig`. Keep source-level value semantics and classify managed values through typed `ValueRep`/layout facts; no source-visible pointer, reference, ownership, `Result<T,E>`, or `Option<T>` feature is added. A union carrier is admitted only when every payload slot is a GC-safe Do value; WIT resources and Component ABI values remain separate and fail closed in this plan.

**Tech Stack:** Zig 0.16, Wasm GC Core WAT, `wasm-tools 1.255.0`, Wasmtime `-W gc=y`, current root `./src/build/test/run_tests.sh` harness.

**Spec:** `doc/superpowers/specs/2026-08-11-gc-backend-architecture-design.md`, `doc/design/2026-08-11-gc-first-memory-decision.md`, `doc/superpowers/plans/2026-08-13-gc-first-one-pass-migration.md`.

## Global Constraints

- Default `do build` remains ARC until G5b equivalence and G5c cutover gates pass.
- `--gc-core` remains a migration oracle and is not expanded into a public backend choice.
- Do not mix ARC handles with GC references in one emitted Core module or source-value data flow.
- Do not add public `ref<T>`, `own<T>`, `borrow<T>`, `Result<T,E>`, or `Option<T>` types.
- Do not admit WIT resource-containing aggregates, imports, async/future/stream, Component marshalling, or unresolved generic bindings in this aggregate slice.
- Unsupported shapes must return a named error before WAT emission; no ARC fallback is allowed.
- Preserve unrelated user changes in the dirty worktree; stage only files belonging to the current task.

### Task 0: Restore The Current G5a Green Baseline

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`
- Test: `src/build/codegen_gc_sync.zig`
- Verify: `src/build/gc_sync_probe.zig`, `examples/gc-p3-runtime/test_do_gc_*.sh`

**Interfaces:**
- Consumes: the already admitted parsed list, text, nested-struct, and tuple slices.
- Produces: a green focused GC sync suite with the exact rejection class for non-`u8` list updates.

- [ ] **Step 1: Fix the stale negative assertion.**

  Change the non-`u8` list test to assert the current pre-WAT contract emitted by `emit_gc_wat_for_supported_program`: `error.UnsupportedGcSyncType`. Do not broaden admission to `[u32]`.

- [ ] **Step 2: Run the focused unit gate.**

  ```bash
  cd src && zig test build/codegen_gc_sync.zig
  cd src && zig test build/gc_sync_probe.zig
  cd src && zig test build/codegen_gc_emit_test.zig
  ```

  Expected: `codegen_gc_sync.zig` reports `90/90`, probe `28/28`, and emitter tests `18/18`.

- [ ] **Step 3: Run executable slice probes.**

  ```bash
  for probe in \
    examples/gc-p3-runtime/test_do_gc_list_set.sh \
    examples/gc-p3-runtime/test_do_gc_parameterized_list_set.sh \
    examples/gc-p3-runtime/test_do_gc_list_literal.sh \
    examples/gc-p3-runtime/test_do_gc_list_put.sh \
    examples/gc-p3-runtime/test_do_gc_managed_struct_payload.sh \
    examples/gc-p3-runtime/test_do_gc_managed_struct_payload_renamed.sh \
    examples/gc-p3-runtime/test_do_gc_nested_managed_struct.sh \
    examples/gc-p3-runtime/test_do_gc_managed_tuple_text_bytes.sh; do
    bash "$probe"
  done
  git diff --check
  ```

  Expected: every probe validates with current `wasm-tools` and Wasmtime GC and returns `27815`.

- [ ] **Step 4: Record a scoped review checkpoint.**

  Write `.superpowers/sdd/2026-08-13-gc-g5a-aggregate-closure/task-0-report.md` with the exact test counts, probe output, remaining boundaries, and any review finding. Do not mark the inventory row complete from unit tests alone.

- [ ] **Step 5: Commit only the baseline fix.**

  ```bash
  git add src/build/codegen_gc_sync.zig .superpowers/sdd/2026-08-13-gc-g5a-aggregate-closure/task-0-report.md
  git commit -m "Restore green parsed GC aggregate baseline"
  ```

### Task 1: Make Probe And Ledger Evidence Fail Closed

**Files:**
- Modify: `src/build/gc_sync_probe.zig`
- Modify: `src/build/test/check_gc_migration_inventory.sh`
- Test: `src/build/gc_sync_probe.zig`
- Test: `src/build/test/check_gc_migration_inventory.sh`
- Modify: `doc/host_abi_blockers.md`, `doc/roadmap_status.md`, `examples/gc-p3-runtime/README.md`

**Interfaces:**
- Consumes: parsed declaration/layout facts and the current 13-row migration manifest.
- Produces: probe classification that cannot fabricate `$box`/field names, plus ledger evidence validation that distinguishes linked artifacts from prose.

- [ ] **Step 1: Add regression tests for probe mismatch.**

  Add a fixture with a differently shaped managed struct and a scalar-field update. Assert `UnsupportedGcSyncProbeSignature` before wrapper WAT generation; assert that a parsed payload probe carries the actual struct and field names.

- [ ] **Step 2: Replace heuristic probe admission.**

  In `find_managed_struct_payload_probe`, require the exact parsed update expression, resolve the actual struct declaration and field order, and reject any shape whose generated wrapper cannot be built from those facts. Do not use parameter count or capitalization as a managed-shape proxy.

- [ ] **Step 3: Validate evidence kinds in the inventory.**

  Keep G5a fixture/probe links as repository paths. For future G5b/G5c complete rows, require a repository file with an explicit evidence marker and reject arbitrary prose. Pending rows must continue to use `-`. Preserve the intentional non-zero result while rows remain pending.

- [ ] **Step 4: Run the evidence gate.**

  ```bash
  cd src && zig test build/gc_sync_probe.zig
  bash -n src/build/test/check_gc_migration_inventory.sh
  bash src/build/test/check_gc_migration_inventory.sh
  git diff --check
  ```

  Expected: probe tests pass; inventory exits `1` only because G5a/G5b/G5c rows remain incomplete, and it reports no malformed evidence.

- [ ] **Step 5: Commit probe/ledger hardening.**

  ```bash
  git add src/build/gc_sync_probe.zig src/build/test/check_gc_migration_inventory.sh doc/host_abi_blockers.md doc/roadmap_status.md examples/gc-p3-runtime/README.md
  git commit -m "Harden GC migration evidence boundaries"
  ```

### Task 2: Admit One Pure GC Payload-Union Carrier

**Files:**
- Modify: `src/build/codegen_gc_representation.zig`
- Modify: `src/build/codegen_gc_layout.zig`
- Modify: `src/build/codegen_gc_emit.zig`
- Modify: `src/build/codegen_gc_sync.zig`
- Test: `src/build/codegen_gc_sync.zig`, `src/build/codegen_gc_emit_test.zig`
- Create: `examples/gc-p3-runtime/gc-payload-union.do`
- Create: `examples/gc-p3-runtime/test_do_gc_payload_union.sh`

**Interfaces:**
- Consumes: existing parsed payload-enum declarations and `UnionLayout`/`UnionBranch` facts from `codegen_collect_declarations.zig` and `codegen_union_layout.zig`.
- Produces: one complete-program GC slice for a payload enum with exactly one managed `[u8]` arm and one inline unit/scalar arm; all other union shapes remain rejected.

- [ ] **Step 1: Add failing positive and negative tests.**

  Cover a declaration such as:

  ```do
  Message = Empty | Bytes([u8])
  rewrite(value Message, bytes [u8]) -> Message {
      return Bytes(bytes)
  }
  ```

  Assert old `Empty`/`Bytes` values remain observable, the new arm has the replacement GC reference, and no `__arc_` symbol is emitted. Add negative tests for two managed arms, a resource payload, scalar-plus-managed multi-slot payloads, and unresolved payload type; each must fail before WAT with a specific `UnsupportedGcSyncUnion*` error.

- [ ] **Step 2: Add representation/layout guards.**

  Classify payload enum arms through `ValueRep`. Admit only unit plus one `[u8]` arm in this first carrier. Reject `ResourceHandle`, nested unions, Tuple/storage payloads, and any arm requiring an untyped or mixed slot. Keep tag and payload layout facts separate from WIT resource plans.

- [ ] **Step 3: Lower tag/payload construction and direct replacement.**

  Emit a typed GC union struct containing the tag and nullable `$do_bytes` payload. Construct `Empty` with a null payload and `Bytes(bytes)` with the direct GC reference. `rewrite` must allocate a new union object and leave the input union unchanged.

- [ ] **Step 4: Add and run the Wasmtime probe.**

  The probe must check distinct union object identity, old/new tags, old payload preservation, and new payload contents. Validate with `wasm-tools parse`, compile with Wasmtime `-W gc=y`, invoke the exported probe, and expect `27815`.

- [ ] **Step 5: Commit the bounded union slice.**

  ```bash
  git add src/build/codegen_gc_*.zig examples/gc-p3-runtime/gc-payload-union.do examples/gc-p3-runtime/test_do_gc_payload_union.sh
  git commit -m "Admit bounded payload unions through Wasm GC"
  ```

### Task 3: Close Typed Aggregate Layout And Tuple/Storage Boundaries

**Files:**
- Modify: `src/build/codegen_gc_layout.zig`
- Modify: `src/build/codegen_gc_roots.zig`
- Modify: `src/build/codegen_gc_emit.zig`
- Modify: `src/build/codegen_gc_sync.zig`
- Modify: `src/build/codegen_gc_sync_adapter.zig`
- Modify: `src/build/codegen_gc_model_adapter.zig`
- Modify: `src/build/codegen_emit_tuple.zig`
- Modify: `src/build/codegen_emit_union.zig`
- Test: `src/build/codegen_gc_layout.zig`, `src/build/codegen_gc_sync.zig`, `src/build/codegen_gc_emit_test.zig`

**Interfaces:**
- Consumes: the bounded payload union and existing nested managed struct facts.
- Produces: topologically collected GC layouts and an explicit admission matrix for nested structs, Tuple construction/indexing, and storage updates.

- [ ] **Step 1: Add failing layout tests.**

  Add cases for missing child type, forward-invalid child, direct cycle, resource field, Tuple with an unsupported leaf, and a local Tuple binding. Assert each named error before WAT.

- [ ] **Step 2: Collect nested GC layouts topologically.**

  Build a dependency graph from managed struct fields, detect cycles with a three-state DFS, and emit child types before parent types. A resource field must return `ResourceInManagedAggregate`, never become a GC field.

- [ ] **Step 3: Add a minimal Tuple constructor/index path.**

  Admit only `Tuple<text, [u8]>` construction from direct locals/literals and `@get` indices `0`/`1`; reject arbitrary indices, nested tuples, resource leaves, and general Tuple storage until their own evidence exists.

- [ ] **Step 4: Keep storage ABI separate.**

  Do not reuse ordinary ARC tuple packing for GC references. Either lower a typed GC tuple object or return `UnsupportedGcSyncTupleStorage` for storage writes; the decision must be explicit in tests and docs.

- [ ] **Step 5: Run the aggregate layout gate.**

  ```bash
  cd src && zig test build/codegen_gc_layout.zig
  cd src && zig test build/codegen_gc_sync.zig
  cd src && zig test build/codegen_gc_emit_test.zig
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  ```

  Expected: all admitted aggregate slices pass, and every unsupported/resource shape fails before WAT.

- [ ] **Step 6: Commit typed aggregate closure.**

  ```bash
  git add src/build/codegen_gc_*.zig src/build/codegen_emit_tuple.zig src/build/codegen_emit_union.zig src/build/test doc/roadmap_status.md doc/host_abi_blockers.md examples/gc-p3-runtime
  git commit -m "Close typed GC aggregate boundaries"
  ```

### Task 4: Route Resolved Generic Managed Calls

**Files:**
- Modify: `src/build/codegen_generics.zig`
- Modify: `src/build/codegen_gc_sync.zig`
- Modify: `src/build/codegen_gc_sync_adapter.zig`
- Modify: `src/build/codegen_gc_model_adapter.zig`
- Test: `src/build/codegen_gc_sync.zig`, `src/build/codegen_generics.zig`, `src/build/test/compile_ok/`
- Create: `examples/gc-p3-runtime/generic-managed-identity.do`
- Create: `examples/gc-p3-runtime/test_do_gc_generic_managed_identity.sh`

**Interfaces:**
- Consumes: resolved generic type bindings and typed `GcStructLayout`/`ValueRep` facts.
- Produces: one generic identity/return and one generic managed field update slice with unresolved/resource/generic-union bindings rejected pre-WAT.

- [x] **Step 1: Add red fixtures.**

  Add generic identity and managed field update cases, plus unresolved type, resource type, and generic union negative cases. Assert named errors rather than generic `UnsupportedGcSyncType` where a more precise guard is possible.

- [x] **Step 2: Thread resolved bindings into GC facts.**

  Make generic instantiation return the concrete `ValueRep` and layout identity used by GC lowering. Reject missing substitutions, recursive unresolved layouts, and resource-containing substitutions before emitter invocation.

- [x] **Step 3: Lower the admitted generic calls.**

  Pass managed values as typed GC refs, preserve identity for read-only return, and rebuild only the updated logical path for field update. No generic call may enter an ARC emitter.

- [x] **Step 4: Run generic and full aggregate gates.**

  ```bash
  cd src && zig test build/codegen_generics.zig
  cd src && zig test build/codegen_gc_sync.zig
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  bash examples/gc-p3-runtime/test_do_gc_generic_managed_identity.sh
  ```

  Expected: positive generic probes return `27815`; unresolved/resource forms fail before WAT.

- [x] **Step 5: Record resolved generic lowering without commit/push.**

  ```bash
  git add src/build/codegen_generics.zig src/build/codegen_gc_*.zig src/build/test examples/gc-p3-runtime doc/roadmap_status.md doc/host_abi_blockers.md
  git commit -m "Lower resolved generic managed calls through GC"
  ```

### Task 5: Aggregate Gate And Migration Handoff

**Files:**
- Modify: `src/build/test/check_gc_migration_inventory.sh`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/host_abi_blockers.md`
- Create: `.superpowers/sdd/2026-08-13-gc-g5a-aggregate-closure/task-5-report.md`

**Interfaces:**
- Consumes: all focused tests/probes from Tasks 0-4.
- Produces: a reviewed G5a aggregate checkpoint; G5b remains explicitly pending and default routing remains unchanged.

- [x] **Step 1: Run the focused aggregate commands.**

  ```bash
  cd src && zig fmt --check build/codegen_gc_*.zig build/gc_sync_probe.zig
  cd src && zig test build/codegen_gc_layout.zig
  cd src && zig test build/codegen_gc_sync.zig
  cd src && zig test build/codegen_gc_emit_test.zig
  cd src && zig test build/codegen_generics.zig
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  bash src/build/test/check_gc_migration_inventory.sh
  git diff --check
  ```

- [x] **Step 2: Confirm expected red/green states.**

  Focused implementation tests and all admitted probes must be green. The inventory must remain non-zero while any G5a/G5b/G5c row is pending. No command may silently route unsupported shapes to ARC.

- [x] **Step 3: Update the ledger with exact evidence.**

  Record fixture paths, probe commands, test counts, tool versions, and remaining boundaries. Do not mark `unions`, `tuple_storage`, or `generic_calls` complete unless their positive and negative evidence is executable and linked.

- [x] **Step 4: Write the checkpoint report.**

  Include changed files, verification commands and outputs, known review findings, rollback commits, and the next independent phase: synchronous root conversion. State explicitly that G5b equivalence and G5c default cutover remain pending.

- [x] **Step 5: Record the aggregate checkpoint without commit/push.**

  ```bash
  git add src/build/test/check_gc_migration_inventory.sh doc/roadmap_status.md doc/host_abi_blockers.md .superpowers/sdd/2026-08-13-gc-g5a-aggregate-closure/task-5-report.md
  git commit -m "Record G5a aggregate closure checkpoint"
  ```

## Completion Criteria

This stage is complete only when:

1. The focused GC sync suite and all admitted aggregate probes pass with current tools.
2. Pure payload-union admission is bounded, typed, and fail-closed for resources and unsupported arms.
3. Nested layouts are deterministic and resource fields never become GC children.
4. Resolved generic managed calls use GC facts; unresolved/resource bindings are rejected before WAT.
5. The migration ledger links executable evidence and remains red for pending G5b/G5c.
6. Normal `do build` still uses ARC; no default routing or ARC deletion occurs in this stage.

## Estimated Duration

With the current codebase and existing probe infrastructure: **5-8 effective workdays** for this aggregate stage, assuming no new Wasm GC validator limitation. The high-risk items are typed union carrier lowering and generic binding propagation. If either needs a new ABI design, stop that dependent task and record the blocker while continuing documentation and negative-gate work.
