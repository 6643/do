# SDD ledger — plan: doc/superpowers/plans/2026-09-13-g6-2-shared-emitter-state-ir-pilot.md

## Setup

- Base checkout: `/home/_/._/_/do`
- Branch: `main`
- Plan workspace: `.superpowers/sdd/2026-09-13-g6-2-shared-emitter-state-ir-pilot`
- Starting HEAD: `822a13f`
- Starting worktree: plan/spec documents are untracked; implementation files are unchanged.
- Ruling: work remains on the current `main` checkout because the user explicitly authorized in-place main execution earlier. Cost if wrong: implementation commits are immediately visible on the shared branch; mitigation is strictly serial subagent dispatch, per-task review, no force reset/checkout, and no push without a separate explicit user instruction.

## Plan conflict scan

### Shared file/interface rows

| Pair | Shared surface | Finding | Ruling |
| --- | --- | --- | --- |
| Task 1 -> Task 2 | `RouteFrameFacts`, fact types, validator | Task 2 consumes the production facts extracted by Task 1; aliases must preserve mapping-probe field names. | No conflict. Task 1 lands first; Task 2 uses the production types and never imports the test-only probe. |
| Task 1 -> Task 5 | fact records used by the pilot input | Task 5 needs the same borrowed fact records and route identity. | No conflict. Task 5 consumes Task 1's records through the route adapter. |
| Task 2 -> Task 3 | `CanonicalFrameMap`, `state_ir.zig` | Task 3 extends the state-IR module created by Task 2 and must preserve the map API. | No conflict. Task 3 adds IR types/functions without changing map field meanings. |
| Task 2 -> Task 4 | map marker/lifecycle spans used for fragment validation | Fragment validation uses declared map markers but must not mutate map facts. | No conflict. Task 4 only borrows map/state data and owns no facts. |
| Task 2 -> Task 5 | `FrameMapInput` and `CanonicalFrameMap` | Task 5's `PilotFacts` must explicitly convert to `FrameMapInput`; no emitter/state-IR cycle is allowed. | No conflict. The plan's explicit conversion is binding. |
| Task 3 -> Task 5 | `LifecycleStateIR`, `build_lifecycle_ir` | Emitter consumes the static IR and must preserve post-transfer cancel semantics. | No conflict. Task 5 does not reinterpret or regenerate lifecycle transitions. |
| Task 4 -> Task 5 | `Fragment`, `assemble`, fragment table | Emitter supplies the route table and calls the bounded assembler. | No conflict. Task 4 owns coverage/order validation; Task 5 only handles admission and parity. |
| Task 5 -> Task 6 | private pilot API, test root, direct route adapter | Task 6 gates the artifact produced by Task 5 and verifies default-route rollback. | No conflict. Task 6 may change code only for a confirmed gate defect and may not promote the route. |
| Task 2/4/5 -> `src/main.zig` | test-root imports | Three tasks add distinct test-module imports to the same test block. | No conflict. Add one import per module, preserve production dispatch and existing import order. |

### Per-task self-consistency rows

| Task | Self-consistency check | Result |
| --- | --- | --- |
| Task 1 | Fact declarations, validator, mapping aliases and zero-offset regression all target the listed files. | Clean. |
| Task 2 | `FrameMapInput` is defined before `build_frame_map`; tests cover every named map error and fixed bound. | Clean. |
| Task 3 | Fixed arrays/counts match the allocation-free requirement; builder and validator expose the same IR shape. | Clean. |
| Task 4 | Fragment span descriptors, validation errors and allocator-owned assembly are covered by the listed tests. | Clean. |
| Task 5 | `PilotFacts` conversion, emitter ordering, adapter entry and parity/admission tests align; old emitter remains unchanged. | Clean. |
| Task 6 | Repository, Component, runtime, default-route, rollback and evidence updates are ordered after Tasks 1-5. | Clean. |

### Global constraints checked

- Single direct owned-record route only; no public ownership/lifetime syntax or generic/arbitrary producer admission.
- No default dispatch change, silent fallback, template deletion, or capability promotion.
- Facts/map/IR/fragment validation is borrowed and allocation-free; final WAT is caller-owned.
- Offset/handle zero remains valid; invalid identity, overlap, bounds, cleanup and parity fail closed.
- Current toolchain and Rust/Wasmtime evidence are required; environment failures remain explicit and unmasked.

## Task status

- Task 1: complete at `fdde887` after fix round 1; both Important findings addressed by scoped re-review. Minor/deferred: full repository suite was not run by the implementer; focus evidence is 20/20 and mapping table remains test-only by design.
- Task 2: complete at `2c63453`; scoped re-review accepted. Minor/deferred: duplicate required/ordered anchor cases lack separate fixtures, but validator rejects them and no P0/P1/P2 remains. Marker byte mismatch is explicitly owned by Task 4/5.
- Task 3: in_progress (BASE `2c63453`; brief `.superpowers/sdd/2026-09-13-g6-2-shared-emitter-state-ir-pilot/task-3-brief.md`)

### Task 3 review finding and ruling

- Important: `build_lifecycle_ir` and `validate_lifecycle_ir` trusted a caller-provided `CanonicalFrameMap` after checking only identity/frame size/ownership count; malformed frame, binding, marker, or lifecycle facts could therefore cross the lifecycle boundary.
- Ruling: close the gap in Task 3 before Task 4 by validating the map with the existing allocation-free `validate_frame_map` path and adding a malformed-map regression. Map validation failures must become an explicit lifecycle error, preserving fail-closed behavior without changing default dispatch. Cost if wrong: a malformed measured route could produce a seemingly valid static lifecycle plan.

- Task 3 fix round 1: `57985ba` adds allocation-free frame-map validation at both lifecycle entry points, explicit `MapError` to `LifecycleError` mapping, and an out-of-frame ownership regression. Focused lifecycle tests: 15/15; broader lifecycle tests: 64/64; scoped re-review: all findings addressed, no new Critical/Important breakage.
- Task 3: complete at `57985ba` (base `d79f50e`; implementation plus fix round). Remaining boundary: static IR is not yet wired into production WAT emission or default dispatch; that belongs to Tasks 4-6.

### Task 4 review findings and ruling

- P2: fragment assembly mapped allocator `OutOfMemory` to `InvalidSpan`, conflating a valid table with a resource failure.
- P2: missing-marker regression used a marker absent from the whole template, so it did not prove marker ownership is scoped to the declared fragment span.
- Ruling: fix both before Task 5. Extend the fragment error surface with explicit `OutOfMemory` and add a failing-allocator regression; change the marker fixture so the required marker exists in a different fragment and must still return `MissingMarker`. Cost if wrong: resource exhaustion could be misdiagnosed as malformed input, or a whole-template marker scan could pass unnoticed.

- Task 4 fix round 1: `a45c612` adds explicit `FragmentError.OutOfMemory`, propagates allocator failure without an output artifact, and changes the marker regression to a cross-fragment ownership case. Focused tests: 16/16; scoped re-review confirmed both code findings addressed.
- Task 4 fix round 2 ruling: scoped re-review found an obsolete residual paragraph in the evidence report still claiming OOM was mapped to `InvalidSpan`. Update the report only, preserving the new `OutOfMemory` behavior; cost if wrong: review evidence would contradict the implementation and weaken the audit trail.
- Task 4 fix round 2: `7143a5e` updates the stale report paragraph; final scoped re-review passed with no new breakage. Task 4: complete at `7143a5e` (implementation `7be594d`, code fix `a45c612`, report fix `7143a5e`).

- Task 5: complete at `2499f02` (implementation `1d2e4af`, fixes `291e635`, `2499f02`).

### Task 5 review findings and ruling

- P1: `PilotFacts` added an unapproved optional `template_wat` and allowed `golden_wat` to substitute for the assembly source, so a mutated golden could pass parity against itself.
- P1: the direct adapter validated only `plan.contract` plus static facts and ignored measured `plan.descriptor`, `plan.layout`, `plan.producer`, terminal/record/storage/absence details, and extra producer shape; a mutated plan could therefore produce the same WAT.
- P1: canonical GC boundary detection searched only a partial token set and missed legal `ref.null`/related GC opcodes.
- Ruling: fix all three before Task 6. Restore the exact `PilotFacts` API, use an adapter-owned immutable canonical template source independent of `golden_wat`, compare the complete measured direct-route plan shape before shared emission, and reject the complete canonical-boundary GC opcode/token set with direct regressions. Cost if wrong: parity/admission gates would be fail-open and could certify an unmeasured route or GC reference crossing.

### Task 5 fix round 1 review result and ruling

- `PilotFacts` exact shape and independent canonical source were accepted.
- P1 remained: direct admission did not explicitly reject non-null `canonical.record_list_layout` or `canonical.parameterized_owned_record_pair_producer`, and it did not pin measured record alignment; coordinated descriptor/layout/contract mutation could still pass.
- P1 remained: GC token coverage omitted standard array initialization/fill and `call_ref`/`return_call_ref`, and `;` was not a token delimiter for adjacent line comments.
- Ruling: fix round 2 must add explicit null checks for unsupported canonical variants, pin direct record alignment to the measured value independently of mutable shape, expand the GC opcode set, and treat comment delimiters as token boundaries with regressions for coordinated plan mutation and `ref.null;;`/missing opcodes. Cost if wrong: future or adversarial route facts could remain admission/GC fail-open despite current focused parity.
- Task 5 fix round 2: `2499f02` closes non-direct canonical optional-shape admission, pins direct alignment, adds coordinated mutation regressions, expands GC/reference tokens and semicolon tokenization. Scoped re-review passed all findings with no new P1 or regression. Task 5: complete at `2499f02` (implementation `1d2e4af`, fix rounds `291e635`, `2499f02`).

- Task 6: complete-with-residuals at `44216d0` (`Record G6.2 artifact guard status`); full regression ARC inventory remains BLOCKED and list/frame runtime counters remain unverified.

### Whole-branch hardening and verification

- Commit `59c8624` (`Harden G6.2 shared emitter pilot admission`) removes the production adapter's test-only `mapping_probe` dependency, wires `LifecycleStateIR` into fragment assembly, pins direct route facts/markers/bindings/lifecycle/hash fail-closed, and preserves allocator errors.
- Scoped re-review accepted all four prior Important findings; no new Critical/Important breakage was found. `mapping_probe` remains test-only.
- Fresh verification: pilot focused `20/20`, producer filter `195/195`, full `zig test main.zig` `1724/1724`, ReleaseSmall build and release smoke exit `0`. `run_tests.sh` still reports `53/53` harness cases but exits `1` on ARC inventory `exit 2`, `unclassified=3`; host runtime list/frame counters remain unverified.

### Task 6 review findings and ruling

- P1: Component artifact evidence invoked the ordinary `--p3-async-component` path, which is the old emitter; it did not prove that the private pilot entry generated the artifact passed to `wasm-tools`.
- P1: rollback evidence only observed that default dispatch did not use the pilot; it did not perform the required remove-private-dispatch rollback check.
- P1: lifecycle evidence omitted the required list/frame exactly-once assertions and did not preserve the concrete runner command/row output.
- P2: Component evidence omitted descriptor identity, artifact path, and actual GC-boundary guard output; default-route evidence omitted independent diagnostics/descriptor/runtime-counter/capability diff commands.
- P2: plan Step 6 remained unchecked despite the Task 6 commit.
- Ruling: fix Task 6 before closure. Generate or directly exercise a private-pilot artifact (or mark that gate explicitly unverifiable if the current private API cannot be invoked without an approved source change), perform and record the rollback operation, preserve concrete lifecycle/list/frame evidence, add exact artifact/default-route command outputs and identity checks, and synchronize plan/spec checkboxes. Keep the full regression exit 1 and ARC inventory mismatch as an explicit unresolved gate; do not weaken or classify it green. Cost if wrong: the pilot could be certified using only the unchanged legacy artifact and incomplete runtime observations.

### Task 6 fix round 1 review result and ruling

- Private-pilot artifact invocation and controlled rollback are now evidenced.
- P1 remains: the direct runtime log records resource/stream/future cleanup but no list/frame fields; the existing runner does not assert list/frame counters. For this route, list backing must be shown as structurally absent (zero list allocations/assets), while frame lifecycle must be shown by the static frame/state-IR gate and explicitly distinguished from host cleanup counters; otherwise mark the runtime sub-gate unverified.
- P2 remains: GC/ARC guard checks lack exact command/output; default counters/capability evidence lacks raw output paths/commands; progress/spec/report task status and commit identity are not fully synchronized.
- Ruling: fix round 2 must add concrete structural zero-list/static-frame evidence and exact commands/output paths, preserve the unresolved full-regression inventory mismatch, and synchronize progress, plan, spec, and report status/commit fields. Do not claim list/frame runtime counters that the runner does not produce. Cost if wrong: the pilot would overstate runtime lifecycle coverage.

### Task 6 fix round 2 review result and ruling

- Lifecycle list/frame evidence is now honestly split: direct route has zero list assets and static frame/state-IR evidence; host runtime list/frame counters remain unverified. GC/ARC and default command/output paths are recorded, and the full regression inventory exit 2 remains unresolved.
- P2 remains: the artifact guard shell command treats `rg` I/O errors (including a missing artifact) as clean, and the ignored ledger still says Task 6 is pending without the full evidence commit identity.
- Ruling: fix round 3 must make the artifact scan fail closed on missing/read errors and synchronize the ledger/report/spec with the actual Task 6 commit SHA/subject. Preserve all unresolved/unverified statuses. Cost if wrong: missing artifacts or stale recovery state could be mistaken for a verified gate.

### Task 6 fix round 3 result and ruling

- The artifact guard now checks existence/readability before scanning and handles `rg` status explicitly: `0` is a marker match and fails the gate, `1` is a clean no-match result, and `>=2` is an I/O/error result and fails the gate. The verified private artifact remains `.tmp/task-6-evidence/private-pilot/pilot.wat`; strict round-3 output is `.tmp/task-6-evidence/round3/artifact-guard-strict.log` with `artifact-boundary-scan=clean`, `existing-artifact-scan exit=0`, the missing-artifact diagnostic, and `missing-artifact-scan exit=2`.
- The ledger, report and spec identify evidence commits `a9ad501` (`Record G6.2 pilot gate evidence`), `4fab935` (`Close G6.2 pilot evidence package`), `4df221b` (`Record G6.2 lifecycle gate status`) and latest revision `44216d0` (`Record G6.2 artifact guard status`).
- Task 6 is complete-with-residuals: private artifact/rollback evidence is closed, while full regression remains blocked by ARC inventory (`exit 2`, `unclassified=3`) and list/frame runtime counters remain unverified.
- Ruling: round 3 is addressed without modifying runner, inventory, production source or route dispatch. Residual gates remain visible and prevent a full-green claim.

### Task 6 fix round 3 review result and ruling

- P2 remains: the report still presents the old fail-open artifact scan command as the direct scan command, while the strict round-3 command exists only in prose/summary; the report and progress also disagree on latest evidence commit, raw log path, and partial/complete-with-residuals wording.
- Ruling: fix round 4 is documentation-only. Replace the old command with the strict existence plus `rg` status handling, synchronize report/spec/progress to `44216d0` (`Record G6.2 artifact guard status`) and the round3 log paths, and use one explicit residual-status term. Preserve ARC inventory exit 2 and list/frame runtime unverified. Cost if wrong: recovery evidence could still direct auditors to a fail-open command or stale commit.

### Task 6 fix round 4 review result and ruling

- Round 4 scoped re-review accepted all findings: the report now presents the strict existence/readability and explicit `rg` status guard; report/spec/progress agree on `complete-with-residuals`, evidence revision `44216d0`, and `.tmp/task-6-evidence/round3/artifact-guard-strict.log`; ARC inventory remains exit 2 with `unclassified=3`, and list/frame runtime counters remain explicitly unverified.
- No new breakage was found in the documentation-only fix. Task 6 remains complete-with-residuals, not full-green; the deferred 12-route migration, generic/arbitrary producer, public ownership syntax, semantic-parity rewrite and D2 general async remain outside this plan.
- Ruling: close the Task 6 review loop and proceed to whole-branch review. Cost if wrong: a hidden cross-task regression or stale residual claim would survive into the next phase.

### Ruling: Task 2 marker validation boundary

The map builder receives borrowed route facts but no WAT/template observation. It therefore must reject empty/duplicate marker facts, while actual expected-vs-observed marker byte comparison is a fragment/pilot responsibility and must be tested there. This follows the approved spec's separation between measured route facts and template assembly; cost if wrong: the map filter alone would not catch a changed template marker, so Task 4/5's parity tests are load-bearing and must include that negative case.
- Task 4: complete at `7143a5e` (implementation `7be594d`, fix `a45c612`, report `7143a5e`).
- Task 5: complete at `2499f02` (implementation `1d2e4af`, fixes `291e635`, `2499f02`).
- Task 6: complete-with-residuals at `44216d0` (`Record G6.2 artifact guard status`); full regression ARC inventory remains BLOCKED and list/frame runtime counters remain unverified.
