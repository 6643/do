# G5c Next Phase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan task-by-task with review checkpoints. Preserve unrelated dirty changes in the current `main` checkout.

**Goal:** Close the current G5c route-consolidation gates, then prepare exactly one independently evidenced bounded residual G5c slice without widening the admitted shape set or claiming full GC cutover.

**Architecture:** Finish the existing `LoadedRequest`/descriptor-registry consolidation first. All admitted C14–C20 routes continue to consume one manifest-backed request and the existing `SyncValuePlan`; no second layout table or descriptor-specific emitter branch is introduced. After the baseline is green, choose one residual shape only after a read-only inventory review, and give it its own design, pinned ABI/WIT probe, positive/negative fixtures, host/equivalence gate, and rollback boundary.

**Tech Stack:** Zig 0.16.0, `wasm-tools 1.255.0`, Wasmtime 47.0.2, the repository `run_tests.sh` harness, WAT/component validation, and the existing Rust host runner.

**Spec:** `doc/superpowers/specs/2026-08-25-g5c-route-consolidation-design.md`

## Global Constraints

- Keep the admitted C14–C20 descriptor registry unchanged until a separate residual-slice design is approved.
- Keep `LoadedRequest` as the single ownership/provenance boundary; production callers must not reload the same manifest/WIT request.
- Keep canonical Component/WIT imports free of Wasm GC reference types.
- Validate every pointer/length span before its first load or copy and preserve measured exactly-once cleanup order.
- Keep unknown descriptors, async/resource shapes, generic aggregates, borrowed payloads, `own<T>`, `borrow<T>`, `ref<T>`, `Option`, and `Result` fail-closed for this route family.
- Use only the pinned Zig, `wasm-tools`, and Wasmtime versions above.
- Do not change migration inventory status: the expected gate remains `complete_rows=15 pending_rows=15` and deliberate exit code `1`.
- Do not remove the ARC fallback or use this phase as evidence for full GC cutover.

---

### Task 1: Lock the shared span-guard and cleanup contract (complete 2026-08-25)

**Files:**

- Modify only if a focused assertion proves a missing invariant: `src/build/codegen_component_marshal_plan.zig`, `src/build/codegen_component_marshal_ops.zig`, `src/build/codegen_component_marshal_wat.zig`
- Test: the existing marshal-plan, marshal-ops, marshal-WAT tests and C14–C20 gate fixtures

**Interfaces:**

- Consume: `LoadedRequest.plan` and its measured operation metadata.
- Produce: one emitter-visible sequence for every admitted text/list operation: `canonical_call -> validate_linear_span -> copy_linear_payload -> construct_gc_value -> publish_gc_root -> cleanup_each_linear_allocation_once`.

- [x] **Step 1: Add failing WAT assertions for every admitted C14–C20 text/list route.**

  Assert that the overflow/bounds guard occurs before the first `i32.load` or `i32.load8_u`, every canonical import has no `(ref`, and the number and reverse order of frees match the measured plan. For C20, assert payload cleanup precedes label cleanup.

- [x] **Step 2: Run the focused assertions before changing emitters.**

  ```bash
  cd src
  zig test build/codegen_component_marshal_plan.zig --test-filter 'measured'
  zig test build/codegen_component_marshal_wat.zig --test-filter 'span'
  zig test build/codegen_component_marshal_wat.zig --test-filter 'cleanup'
  ```

  Expected: either all assertions pass with no source change, or the failing assertion identifies one missing plan/emitter invariant. A failure is not bypassed by weakening the assertion.

- [x] **Step 3: If and only if a failure is reproduced, add the smallest plan-boundary fix.**

  Extend the existing operation metadata or pure validator so the emitter receives the measured guard and cleanup facts. Do not add descriptor IDs, hard-coded offsets, or a second admission path to the WAT emitter.

- [x] **Step 4: Re-run the focused WAT tests and parser checks.**

  ```bash
  cd src
  zig test build/codegen_component_marshal_plan.zig
  zig test build/codegen_component_marshal_ops.zig
  zig test build/codegen_component_marshal_wat.zig
  ```

  Expected: all focused tests pass and generated canonical imports remain GC-reference-free.

### Task 2: Re-run the consolidated C14–C20 route matrix (complete 2026-08-25)

**Files:**

- Test only: existing scripts under `examples/gc-p3-runtime/` and compiler fixtures under `src/build/test/`

**Interfaces:**

- Consume: the single loaded request, shared descriptor registry, and route lease from the current implementation.
- Produce: host, ARC/GC equivalence, negative, and WAT evidence for every currently admitted C14–C20 descriptor.

- [x] **Step 1: Execute each existing focused route script selected by its filename.**

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

  Expected: every selected script exits `0`; host counters and equivalence values remain the fixture-defined values; negative fixtures reject before WAT.

- [x] **Step 2: Verify the shared request is not resolved twice by the production routes.**

  Inspect the default and explicit route output/log assertions for one manifest load, one source-hash validation, one WIT binding, and one host-boundary validation per route. A compatibility wrapper may still load once for isolated tests, but production routes must consume the already-loaded request.

- [x] **Step 3: Run the default compiler and unit suites.**

  ```bash
  ./src/build/test/run_tests.sh
  (cd src && zig test main.zig)
  ```

  Expected: the full regression suite and Zig unit suite pass with no leak/error diagnostics.

### Task 3: Run release and inventory gates (complete 2026-08-25)

**Files:**

- Test only: `src/build/test/run_release_smoke.sh`, `src/build/test/check_gc_default_build_gate.sh`, `src/build/test/check_gc_g5c_residual_gate.sh`, `src/build/test/check_gc_migration_inventory.sh`

**Interfaces:**

- Consume: the consolidated route implementation and the pinned toolchain.
- Produce: release-smoke, default build/parse, G5c residual, and migration-inventory evidence.

- [x] **Step 1: Run the ReleaseSmall build and smoke gate.**

  ```bash
  (cd src && zig build -Doptimize=ReleaseSmall)
  ./src/build/test/run_release_smoke.sh
  ```

  Expected: both commands exit `0` and the generated compiler is the freshly built binary.

- [x] **Step 2: Run the default and residual GC gates.**

  ```bash
  ./src/build/test/check_gc_default_build_gate.sh
  ./src/build/test/check_gc_g5c_residual_gate.sh
  ```

  Expected: both commands exit `0`, use `wasm-tools 1.255.0`, and preserve the current fixture count and no-ARC assertions.

- [x] **Step 3: Run the migration inventory and preserve its deliberate non-zero result.**

  ```bash
  set +e
  ./src/build/test/check_gc_migration_inventory.sh
  inventory_status=$?
  set -e
  test "$inventory_status" -eq 1
  ```

  Expected output includes `summary complete_rows=15 pending_rows=15`; exit `1` means the migration ledger is still intentionally open, not that the route consolidation failed.

### Task 4: Update current-stage evidence and handoff boundaries (complete 2026-08-25)

**Files:**

- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/pending_blocked.md`

**Interfaces:**

- Consume: the exact command outputs and observed host/equivalence counters from Tasks 1–3.
- Produce: status text that distinguishes route consolidation from full GC migration and records any residual failure as a bounded blocker.

- [x] **Step 1: Record only verified facts.**

  Add the shared-request behavior, registry coverage, span/cleanup result, focused route result, release result, and inventory result. Do not report a pending row as complete and do not copy prior results without re-running the command in this phase.

- [x] **Step 2: Run a documentation consistency check.**

  ```bash
  git diff --check
  rg -n 'complete_rows=15 pending_rows=15|full G5c|route consolidation|C14|C20' doc/roadmap_status.md doc/start_here.md doc/pending_blocked.md
  ```

  Expected: no whitespace errors, no statement that this phase closed full G5c, and no contradictory toolchain or inventory claims.

### Task 5: Close the selected bounded slice and reopen the residual design gate (complete 2026-08-25)

**Files:**

- Read-only inputs: `src/build/test/check_gc_migration_inventory.sh`, `doc/pending_blocked.md`, `doc/host_abi_blockers.md`, current C14–C20 manifests and gates
- Completed candidate artifacts: `doc/superpowers/specs/2026-08-25-g5c-mixed-text-two-u32-lists-lower-design.md`, `doc/superpowers/plans/2026-08-25-g5c-mixed-text-two-u32-lists-lower.md`, `doc/superpowers/specs/2026-08-25-g5c-mixed-text-two-u32-lists-lift-design.md`, and `doc/superpowers/plans/2026-08-25-g5c-mixed-text-two-u32-lists-lift.md`
- Next-stage input: the refreshed matrix and the selected candidate's independent spec/plan; no further candidate is selected by this plan

**Interfaces:**

- Consume: the verified baseline from Tasks 1–4 and the 15-row pending inventory.
- Produce: a closed evidence record for the selected descriptor and an explicit gate for the next residual review.

- [x] **Step 1: Produce a read-only capability matrix for the remaining rows.**

  For each candidate, record current evidence, missing evidence, canonical ABI risk, cleanup risk, and whether it can reuse `LoadedRequest`/`SyncValuePlan` without a new ownership model. Keep all rows `pending` during this review.

- [x] **Step 2: Select exactly one bounded candidate for this phase.**

  The candidate must be synchronous, manifest-backed, measurable, free of canonical GC references, and independently executable through Component validation plus Rust/Wasmtime. General aggregates, arbitrary producers, async/resource lowering, borrowed payloads, and ownership syntax are not candidates for this phase.

  The selected candidates were the paired fixed shapes `Writing { code: u32, label: text, first: [u32], second: [u32] }` lower and `Reading { code: u32, label: text, first: [u32], second: [u32] }` lift. Their exact descriptors, measured layouts, and three-span operation/emitter variants are recorded in the completed specs and plans below.

- [x] **Step 3: Apply the design gate before implementation.**

  If the capability matrix shows that every remaining candidate requires a new ownership/async/resource contract, record the blocker and continue only with release-candidate maintenance. Do not widen codegen to make a candidate appear admissible.

  A bounded candidate met the conditions, was approved, and was implemented only through its dedicated spec/plan and gates. The next candidate is not inferred from this result.

- [x] **Step 4: Create the approved candidate spec before implementation and close its evidence loop.**

  The paired `2026-08-25-g5c-mixed-text-two-u32-lists-lower-design.md` and `2026-08-25-g5c-mixed-text-two-u32-lists-lift-design.md` files fix the exact source/WIT pairs, measured layouts, canonical imports, accepted field shapes, span guards, cleanup order, positive/negative fixture names, host counters, equivalence oracles, and fail-closed cases. Both matching implementation plans are complete and the full verification loop is recorded in the current-stage handoff documents.

## Exit Criteria

This phase is complete: Tasks 1–5 have fresh green evidence, including the
mixed-text/two-`list<u32>` lift and lower routes. The current baseline is
`85 fixtures`, `run_tests.sh` `pass=1380 fail=0 skip=3`, Zig `678/678`, and
inventory `complete_rows=15 pending_rows=15` with exit `1`. The next residual
design gate is reopened without preselecting a candidate; any new candidate
must satisfy the synchronous manifest-backed, measurable, canonical-ABI-free
and `LoadedRequest`/`SyncValuePlan` reuse constraints. This is not a full GC
cutover and does not close any inventory row by itself.
