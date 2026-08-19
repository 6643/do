# GC-First Documentation Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the active Do documentation describe Wasm GC as the selected managed-memory backend and retire ARC as an active design target without changing compiler implementation or historical evidence.

**Architecture:** The source contract remains immutable value semantics with internal managed references and copy-on-write updates. The active runtime contract changes from ARC object accounting to GC-managed objects; Component/WIT resources remain ABI-owned handles with explicit transfer and drop rules. Historical plans and changelog entries retain their original facts but gain a narrow supersession note where they would otherwise be mistaken for the current target.

**Tech Stack:** Markdown documentation, repository residual scans, `git diff --check`.

## Global Constraints

- Do not modify `src/`, `bin/`, fixtures, generated artifacts, or runtime behavior in this documentation-only task.
- Preserve the existing user changes in `doc/start_here.md` and `union.md`.
- Do not remove historical verification facts from `CHANGELOG.md` or dated plans.
- Preserve source-level value semantics, internal payload sharing for read-only passes, and copy-on-write update semantics.
- State that GC never releases Component/WIT host resources; their ownership and drop remain compiler/ABI contracts.
- Treat `own<T>`, `borrow<T>`, `ref<T>`, pointers, and general source references as out of scope for the public v1 language surface.

---

### Task 1: Record the GC-First Decision

**Files:**
- Create: `doc/design/2026-08-11-gc-first-memory-decision.md`
- Test: `rg -n "GC-first|ARC" doc/design/2026-08-11-gc-first-memory-decision.md`

**Consumes:** Existing `doc/memory.md` value semantics and the generic WIT ownership boundary.

**Produces:** A dated decision record that defines the active memory target, non-goals, resource boundary, migration rule, and superseded ARC contract.

- [x] **Step 1: Write the decision record.**

Document that Wasm GC is the only selected managed-memory target, managed source values use internal GC references, reads share payloads, updates preserve value semantics, and WIT resources are not GC-managed.

- [x] **Step 2: Verify the decision record contains every required boundary.**

Run: `rg -n "Wasm GC|value semantics|copy-on-write|resource|own<T>|borrow<T>|ref<T>|ARC" doc/design/2026-08-11-gc-first-memory-decision.md`

Expected: Every listed contract term appears in the decision record.

### Task 2: Promote the GC Memory Model

**Files:**
- Modify: `doc/memory.md:1-42`
- Modify: `doc/memory.md` ARC-specific implementation sections and status text
- Test: `rg -n "active ARC|planned replacement backend|Runtime/ARC switch" doc/memory.md`

**Consumes:** Task 1 decision record.

**Produces:** The authoritative memory document describes GC as active target and labels ARC representation material as superseded implementation history.

- [x] **Step 1: Replace the title, status, and selected-backend section.**

Set Wasm GC as the active target. Retain the no-pointer/reference source contract, internal reference passing, immutable published values, COW update semantics, and explicit host-resource ownership boundary.

- [x] **Step 2: Replace ARC-specific ownership wording with GC reachability wording.**

Remove normative requirements for source-value retain/release and reference-count object headers. Preserve concrete historical ARC layout facts only under a clearly labeled historical section.

- [x] **Step 3: Verify active-status residuals are gone.**

Run: `! rg -n "active ARC|planned replacement backend|Runtime/ARC switch" doc/memory.md`

Expected: Exit status 0 with no output.

### Task 3: Synchronize Active Entry and Architecture Documents

**Files:**
- Modify: `AGENTS.md`
- Modify: `doc/spec.md`
- Modify: `doc/spec_rules.md`
- Modify: `doc/host-binding-design.md`
- Modify: `doc/roadmap_status.md`
- Test: `rg -n -i "active ARC|ARC memory model|ARC backend" AGENTS.md doc/spec.md doc/spec_rules.md doc/host-binding-design.md doc/roadmap_status.md`

**Consumes:** Task 1 decision record and Task 2 authoritative memory model.

**Produces:** Active project navigation and language/host documentation direct readers to the GC-first contract instead of presenting ARC as the v1 runtime.

- [x] **Step 1: Update navigation and specification links.**

Replace references that call ARC the authoritative runtime with the GC-first model and the dated decision record. Keep existing source ABI and host ownership descriptions intact.

- [x] **Step 2: Update active runtime and roadmap wording.**

Mark ARC implementation work as superseded by the GC-first migration. Do not claim that the current compiler has already completed the migration.

- [x] **Step 3: Verify no active document presents ARC as current.**

Run: `! rg -n -i "active ARC|ARC memory model|ARC backend" AGENTS.md doc/spec.md doc/spec_rules.md doc/host-binding-design.md doc/roadmap_status.md`

Expected: Exit status 0 with no output.

### Task 4: Mark Active Blockers and Dated Plans Correctly

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: relevant `doc/superpowers/specs/*.md` that describe ARC migration as a future active gate
- Modify: relevant `doc/superpowers/plans/*.md` that describe ARC migration as a future active gate
- Test: `rg -n -i "ARC.*active|active.*ARC|ARC.*migration" doc/host_abi_blockers.md doc/pending_blocked.md doc/superpowers/specs doc/superpowers/plans`

**Consumes:** Task 1 decision record.

**Produces:** Open blockers retain their evidence but point to GC completion gates; dated records remain historical rather than becoming false current guidance.

- [x] **Step 1: Add a concise supersession banner to each active blocker or plan that names ARC as an open target.**

The banner must state that ARC claims are historical, source semantics remain unchanged, and future implementation work targets GC.

- [x] **Step 2: Preserve historical commands, hashes, and pass counts unchanged.**

Do not alter completion evidence or logs from earlier work.

- [x] **Step 3: Verify each modified historical record clearly identifies its status.**

Run: `rg -n "Superseded by GC-first|GC-first" doc/host_abi_blockers.md doc/pending_blocked.md doc/superpowers/specs doc/superpowers/plans`

Expected: Every modified historical record has an explicit status marker.

### Task 5: Validate the Documentation Migration

**Files:**
- Test: all modified Markdown files

**Consumes:** Tasks 1-4.

**Produces:** A checked documentation-only diff with a categorized residual inventory for ARC terms that remain as historical code/module names or verification evidence.

- [x] **Step 1: Run the active-document residual scan.**

Run: `rg -n -i "active ARC|planned replacement backend|Runtime/ARC switch|ARC memory model|ARC backend" AGENTS.md doc README.md doc/superpowers/specs doc/superpowers/plans`

Expected: No active-contract hit; any retained historical hit must contain an explicit GC-first supersession marker.

- [x] **Step 2: Run formatting and scope checks.**

Run: `git diff --check && git diff --name-only`

Expected: No whitespace errors; changed files are documentation only and exclude `doc/start_here.md` and `union.md`.

- [x] **Step 3: Record residual implementation debt.**

Document that `runtime_arc_wat.zig`, `codegen_ownership.zig`, ARC tests, and generated WAT remain implementation work for a later GC backend migration; this documentation task does not claim them complete.
