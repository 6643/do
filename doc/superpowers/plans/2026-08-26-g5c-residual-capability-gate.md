# G5c Residual Capability Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan task-by-task with review checkpoints. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the current mixed-text/two-`list<u32>` batch and produce an evidence-backed decision for exactly one next G5c residual shape without widening the GC admission boundary.

**Architecture:** This gate is deliberately separated from candidate implementation. It first verifies the current batch, then builds a machine-readable capability matrix from the 15-row migration inventory and the host ABI blocker ledger. Only a synchronous, manifest-backed, measurable shape that reuses `LoadedRequest` and `SyncValuePlan` may proceed to a separate candidate-specific design and implementation plan; if no row satisfies those conditions, the phase ends with a recorded blocker and release-candidate maintenance only.

**Tech Stack:** Zig 0.16.0, pinned `wasm-tools 1.255.0`, Wasmtime 47.0.2, the repository `run_tests.sh` harness, Component/WAT validation, and the existing Rust host runner.

**Spec:** `doc/superpowers/plans/2026-08-25-g5c-next-phase.md`, `doc/pending_blocked.md`, `doc/host_abi_blockers.md`, and `doc/memory.md`.

## Global Constraints

- Preserve the current dirty `main` checkout; do not reset, clean, or overwrite unrelated changes.
- Keep canonical Component imports free of Wasm GC reference types.
- Keep `LoadedRequest` as the sole manifest/source-provenance boundary and reuse `SyncValuePlan`; do not add a second registry or descriptor-specific ownership model.
- Keep unknown descriptors, drifted source/WIT, async/resource shapes, general aggregates, borrowed payloads, `own<T>`, `borrow<T>`, `ref<T>`, `Option`, and `Result` fail-closed for this route family.
- Keep the migration inventory at `complete_rows=15 pending_rows=15` with deliberate exit code `1` until a separately approved full-row migration decision changes it.
- Do not remove the ARC fallback or claim full GC cutover from bounded evidence.
- Do not push or publish; delivery integration is a separate explicit action.

---

### Task 1: Verify and close the current bounded batch

**Files:**

- Read/verify: `src/build/codegen_component_marshal_module.zig`, `src/build/codegen_component_marshal_ops.zig`, `src/build/codegen_component_marshal_wat.zig`
- Modify only with evidence: `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/start_here.md`, `examples/gc-p3-runtime/README.md`, `CHANGELOG.md`

**Interfaces:**

- Consumes: the mixed-text/two-`list<u32>` lower and lift descriptors, their host/equivalence/negative gates, and the current route-consolidation evidence.
- Produces: a verified baseline record that states the exact observed counters, tool versions, fixture count, and inventory result without claiming full G5c.

- [x] **Step 1: Capture the current worktree boundary.**

  Run:

  ```bash
  git status --short --branch
  git diff --stat
  git diff --check
  ```

  Record the existing dirty paths; do not revert or restage unrelated changes.

- [x] **Step 2: Run the focused marshal suites.**

  Run:

  ```bash
  (cd src && zig test build/codegen_component_marshal_module.zig)
  (cd src && zig test build/codegen_component_marshal_ops.zig)
  (cd src && zig test build/codegen_component_marshal_wat.zig)
  ```

  Expected: all focused tests pass, every admitted span is guarded before its first load/copy, and canonical imports contain no `(ref`.

- [x] **Step 3: Run the current host, equivalence, and negative gates.**

  Run:

  ```bash
  bash examples/gc-p3-runtime/test_gc_marshal_record_mixed_lower_host.sh
  bash examples/gc-p3-runtime/test_gc_marshal_record_mixed_lower_equivalence.sh
  bash examples/gc-p3-runtime/test_gc_marshal_record_mixed_lift_manifest_host.sh
  bash examples/gc-p3-runtime/test_gc_marshal_record_mixed_lift_manifest_equivalence.sh
  bash examples/gc-p3-runtime/test_gc_default_host_route_mixed_lower_negative.sh
  bash examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_two_u32_lists_lower_host.sh
  bash examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_two_u32_lists_lower_equivalence.sh
  bash examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_two_u32_lists_lower_negative.sh
  bash examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_two_u32_lists_lift_manifest_host.sh
  bash examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_two_u32_lists_lift_manifest_equivalence.sh
  bash examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_two_u32_lists_lift_negative.sh
  ```

  Expected: host payloads, callback counts, allocation/free counts, cleanup order, ARC/GC values, and all drift rejections match the checked-in gate contracts. If a filename is absent, stop and resolve the actual checked-in script name before proceeding; do not substitute a neighboring gate.

- [x] **Step 4: Run the repository and release gates.**

  Run:

  ```bash
  ./src/build/test/run_tests.sh
  (cd src && zig test main.zig)
  (cd src && zig build -Doptimize=ReleaseSmall)
  ./src/build/test/run_release_smoke.sh
  ./src/build/test/check_gc_default_build_gate.sh
  ./src/build/test/check_gc_g5c_residual_gate.sh
  ./src/build/test/check_gc_semantic_equivalence.sh
  ```

  Expected: exit `0` for every command, with fresh counts recorded in the handoff documents.

- [x] **Step 5: Verify the intentionally open migration ledger.**

  Run:

  ```bash
  set +e
  bash src/build/test/check_gc_migration_inventory.sh
  inventory_status=$?
  set -e
  test "$inventory_status" -eq 1
  ```

  Expected output: `summary complete_rows=15 pending_rows=15`; exit `1` is the intentional open-ledger result, not a route failure.

- [x] **Step 6: Update only verified stage evidence.**

  Copy the fresh outputs into `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/start_here.md`, and `examples/gc-p3-runtime/README.md`. Preserve the statements that general aggregates, async/resource lowering, ownership syntax, and full G5c cutover remain pending. Run `git diff --check` after the edits.

### Task 2: Build the residual capability matrix

**Files:**

- Read: `src/build/test/check_gc_migration_inventory.sh`, `doc/host_abi_blockers.md`, `doc/pending_blocked.md`, `doc/roadmap_status.md`
- Create: `doc/superpowers/specs/2026-08-26-g5c-residual-capability-matrix.md`

**Interfaces:**

- Consumes: Task 1's fresh verification outputs and the 15 inventory rows (`text`, `[u8]`, `other_lists`, `managed_struct_list_append`, `managed_structs`, `nested_structs`, `tuple_storage`, `unions`, `generic_calls`, `imports`, `host_wit_marshalling`, `host_wit_marshalling_managed_record_lower`, `sync_control_flow`, `future_stream_frames`, `resource_terminal_cleanup`).
- Produces: one matrix with one final decision per row: `candidate`, `blocked`, or `deferred`, plus the evidence and missing gate for that decision.

- [x] **Step 1: Extract each row's current boundary.**

  Use the TSV in `src/build/test/check_gc_migration_inventory.sh` and the corresponding sections in `doc/pending_blocked.md`. For every row record the current accepted shape, current rejection boundary, existing WIT/Component evidence, and the first missing proof.

- [x] **Step 2: Score each row against the admission contract.**

  A row may be marked `candidate` only if it is synchronous, manifest-backed, layout-measurable, canonical-ABI-free of GC references, independently executable through Component plus Rust/Wasmtime, and implementable by reusing `LoadedRequest`/`SyncValuePlan`. Any row requiring general producer expressions, async/resource lowering, borrowed/variant ownership, a new cleanup model, or a new public syntax is `blocked`.

- [x] **Step 3: Select exactly one candidate or record no candidate.**

  The matrix must end with either one exact descriptor/source shape selected for a later candidate-specific design, or an explicit `no admissible candidate` result with the blocking evidence. It must not silently select a neighboring shape or infer general support from a bounded route.

- [x] **Step 4: Self-review the matrix.**

  Check that every inventory row appears once, every decision has evidence, no row is marked complete merely because a private probe exists, and no `TBD`, `TODO`, or unbounded wording remains. Run:

  ```bash
  rg -n 'TBD|TODO|candidate|blocked|deferred|complete_rows=15 pending_rows=15' doc/superpowers/specs/2026-08-26-g5c-residual-capability-matrix.md
  git diff --check -- doc/superpowers/specs/2026-08-26-g5c-residual-capability-matrix.md
  ```

### Task 3: Apply the residual design gate

**Files:**

- Read: `doc/superpowers/specs/2026-08-26-g5c-residual-capability-matrix.md`
- Create only when Task 2 selects a candidate: one candidate-specific spec and one candidate-specific implementation plan under `doc/superpowers/specs/` and `doc/superpowers/plans/`
- Modify: `doc/pending_blocked.md`, `doc/roadmap_status.md`, `doc/start_here.md` only to record the gate result

**Interfaces:**

- Consumes: the matrix's single selected descriptor, or its explicit no-candidate result.
- Produces: either a complete candidate specification that fixes source/WIT hash, measured layout, canonical ABI, span guards, cleanup order, positive/negative fixtures, host counters, and equivalence oracle, or a recorded blocker with no implementation authorization.

- [x] **Step 1: No-candidate branch is not applicable; the matrix selected one exact candidate and records all other rows as blocked.**

  State the exact missing contract and leave the implementation route unchanged. Do not add a compatibility shim, broaden a validator, or change the inventory status.

- [x] **Step 2: The complete candidate spec and implementation plan already exist before this gate's closeout.**

  Include the exact descriptor, source/WIT files and hash, root/result layout, every canonical parameter, guard-before-load rule, allocation/free order, host observations, ARC/GC oracle, and every negative fixture. The spec must explicitly list rejected neighboring shapes.

- [x] **Step 3: Review the candidate spec against the matrix.**

  Confirm that the spec introduces no new ownership, async, resource, or canonical GC-reference contract and that all later implementation file paths and test commands are concrete.

### Task 4: Handoff to candidate implementation or release maintenance

**Files:**

- Modify: the candidate-specific plan/spec from Task 3, or the three handoff documents when no candidate exists

**Interfaces:**

- Consumes: the design-gate result.
- Produces: a clean boundary for the next implementation plan; no code is changed by this gate when no candidate is admissible.

- [x] **Step 1: Record the next executable action.**

  The selected candidate points to
  `doc/superpowers/plans/2026-08-25-g5c-mixed-text-byte-u32-lists-lower.md`;
  its first negative fixture is
  `src/build/test/compile_err/683_gc_wit_mixed_text_byte_u32_lists_lower_async.do`.
  The candidate gates are now green, so the next executable action is
  release-candidate maintenance followed by a fresh single-candidate review.

- [x] **Step 2: Re-run documentation checks.**

  ```bash
  git diff --check
  rg -n 'full G5c|complete_rows=15 pending_rows=15|own<T>|borrow<T>|ref<T>|AsyncLoweringUnavailable' \
    doc/roadmap_status.md doc/start_here.md doc/pending_blocked.md \
    doc/superpowers/specs/2026-08-26-g5c-residual-capability-matrix.md
  ```

  Expected: no document claims full cutover, public ownership syntax, or general async lowering from this bounded gate.

## Exit Criteria

- Task 1 has fresh green evidence for the current batch and preserves the deliberate inventory exit `1`.
- Task 2 contains all 15 rows exactly once and has an evidence-backed decision for each.
- Task 3 has either one complete candidate spec or one explicit blocker; it never leaves an implicit candidate.
- Task 4 identifies the next executable action without modifying unrelated compiler/runtime behavior.
- No code implementation begins until a candidate-specific spec and implementation plan exist.
