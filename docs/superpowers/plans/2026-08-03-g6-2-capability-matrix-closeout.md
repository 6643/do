# G6.2 Capability Matrix Closeout And Authorization Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or superpowers:subagent-driven-development) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the verified branch-terminal/reordered-helper slice, publish an accurate G6.2 baseline, and finish the capability-matrix gate before authorizing any new private resource-lowering shape.

**Architecture:** Treat the current private descriptor registry and path-sensitive `StreamWriter<T>` lease analysis as the only implementation boundary. First reconcile source/runtime evidence with the status documents, then run the pinned-tool capability probes and negative fixtures, and finally make a documented go/no-go decision for one bounded positive slice. No public ownership syntax or general async lowering is introduced by this plan.

**Tech Stack:** Zig 0.16, Do compiler fixtures, WAT/WIT Component assembly, pinned `wasm-tools 1.254.0`, Rust 2024, Wasmtime `47.0.2`, Bash regression harness.

## Global Constraints

- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Do not enable general async-call lowering, arbitrary producer expressions, borrowed/list/variant resource fields, sixth forwarding, seventh nesting, or arbitrary filesystem async methods.
- Keep cancellation aligned with WASI/Component lifecycle semantics: release live guest/Component resources, never roll back an already-issued external side effect.
- Keep `wasm-tools 1.254.0` and Wasmtime `47.0.2` pinned; record tool rejection as a boundary.
- Do not claim `table-empty=true` for the stream-only runner that has no `ResourceTable`.
- Preserve unrelated dirty worktree changes; do not reset, clean, checkout, commit, or push.

---

## Current Handoff

The current slice already has evidence for:

- branch-selected writer terminal behavior (`close` / `abort`) with pending and ready paths;
- reordered helper lease binding, including the existing bounded forwarding depth;
- the existing consumer/resource and StreamMirror gates.

The handoff must correct two documentation risks before new work starts: branch-terminal and reordered-helper evidence must be listed as verified, and stream-only runtime output must not be described as a `ResourceTable` emptiness proof.

The authoritative implementation context remains:

- `docs/superpowers/plans/2026-08-03-g6-2-general-resource-ownership.md`
- `doc/design/2026-08-03-g6-2-general-resource-ownership.md`
- `doc/pending_blocked.md`

---

### Task 1: Freeze the compiler and formatting baseline

**Files:**

- Verify: `src/build/codegen_component_stream_writer.zig`
- Verify: `src/build/sema_stream_lease.zig`
- Verify: `src/build/test/run_tests.sh`
- Verify: `src/build/test/run_release_smoke.sh`

**Interfaces:**

- Consumes: the current branch-terminal and reordered-helper implementation.
- Produces: reproducible baseline output for the remaining documentation and gate tasks.

- [x] **Step 1: Check Zig formatting for the modified implementation files.**

Run:

```bash
cd src
zig fmt --check build/codegen_component_stream_writer.zig build/sema_stream_lease.zig
```

Expected: exit 0 and no formatting diff.

- [x] **Step 2: Run the focused semantic and emitter suites.**

Run:

```bash
cd src
zig test build/sema_stream_lease.zig
zig test build/codegen_component_async_plan.zig
zig test build/codegen_component_stream_writer.zig
```

Expected: all tests pass, including the reordered-helper lease test and the waitable-set handle regression.

- [x] **Step 3: Run the complete default, WASM, and ReleaseSmall checks with workspace caches.**

Run:

```bash
cd /home/_/._/do
mkdir -p .tmp/do-tmp/next-default .tmp/do-tmp/next-wasm .tmp/do-tmp/next-zig-cache .tmp/do-tmp/next-zig-gcache
TMPDIR="$PWD/.tmp/do-tmp/next-default" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/next-zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/next-zig-gcache" \
  ./src/build/test/run_tests.sh
TMPDIR="$PWD/.tmp/do-tmp/next-wasm" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/next-zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/next-zig-gcache" \
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
TMPDIR="$PWD/.tmp/do-tmp/next-default" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/next-zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/next-zig-gcache" \
  ./src/build/test/run_release_smoke.sh
```

Expected: zero failures, the known skip set unchanged, and the WASM run summary remains green. Record the exact counts in the status documents; do not copy older counts from prior plans.

---

### Task 2: Publish an evidence-accurate status handoff

**Files:**

- Modify: `doc/roadmap_status.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/start_here.md`
- Modify: `docs/superpowers/plans/2026-08-03-g6-2-first-positive-resource-slice.md`

**Interfaces:**

- Consumes: Task 1 command output and the existing focused runtime evidence.
- Produces: consistent `已验` / `待验证` / `blocked` wording across the five handoff documents.

- [x] **Step 1: Add the two verified checkpoints.**

Record that branch-selected `close/abort` terminal lowering and reordered helper lease binding are verified, naming their focused tests and runtime scripts. Keep the private descriptor scope explicit.

- [x] **Step 2: Correct cleanup claims by runner capability.**

For stream-only producer runs, describe stream/future/frame cleanup and omit `table-empty=true`; reserve `table-empty=true` for Rust/Wasmtime runners that actually instantiate and inspect a `ResourceTable`.

- [x] **Step 3: Preserve the blocked boundary.**

Keep general producer leases, arbitrary producer expressions, borrowed/list/variant resource fields, sixth forwarding, seventh nesting, public `own<T>`/`borrow<T>`/`ref<T>`, and general async calls blocked. State that cancellation does not roll back external effects.

- [x] **Step 4: Check documentation consistency.**

Run:

```bash
git diff --check
rg -n "branch-terminal|reordered|table-empty|general producer|borrowed|sixth|seventh|own<T>|borrow<T>|ref<T>" \
  doc/roadmap_status.md doc/pending_blocked.md doc/host_abi_blockers.md doc/start_here.md \
  docs/superpowers/plans/2026-08-03-g6-2-first-positive-resource-slice.md
```

Expected: no whitespace errors, and no status file claims that the general resource gate is complete.

---

### Task 3: Complete the pinned capability matrix

**Files:**

- Modify: `doc/design/2026-08-03-g6-2-general-resource-ownership.md`
- Verify: `src/build/p3_async_registry.json`
- Verify: `src/build/resource_abi_registry.json`
- Verify: `examples/p3-runtime/test_do_g6_general_boundary_rejection.sh`
- Verify: `examples/p3-runtime/test_do_borrowed_resource_rejection.sh`

**Interfaces:**

- Consumes: pinned WIT snapshots, registry descriptors, current compiler diagnostics, and Wasmtime runner behavior.
- Produces: one row per shape with result category, exact command, exact diagnostic, and the layer that rejected it.

- [x] **Step 1: Record the verified positive rows.**

Include scalar/string consumers, direct and multiple `own` fields, one through six nested owned-resource levels, multiple nested paths, bounded producers, parameterized producers, helper forwarding through five hops, reordered helper arguments, branch-terminal producer behavior, and the six StreamMirror runtime modes.

- [x] **Step 2: Re-run each negative probe at its owning layer.**

Run:

```bash
bash examples/p3-runtime/test_do_g6_general_boundary_rejection.sh
bash examples/p3-runtime/test_do_borrowed_resource_rejection.sh
./bin/do check src/build/test/check/412_stream_writer_shared_lease.do
(cd src && zig test build/p3_async_manifest.zig)
```

Expected: sixth forwarding and arbitrary producer fail with `UnsupportedP3AsyncComponent`, shared lease fails with `StreamWriterAlreadyFinalized`, borrowed WIT fails with the pinned `borrow<T>` diagnostic, and the manifest test retains the seventh-level rejection.

- [x] **Step 3: Record toolchain provenance.**

Keep the pinned versions and classify each result as `verified`, `rejected by compiler`, `rejected by wasm-tools`, `rejected by manifest validation`, `runtime-unknown`, or `deferred`. Do not convert a tool acceptance into Do lowering support.

---

### Task 4: Review and lock the ownership invariants

**Files:**

- Modify: `doc/design/2026-08-03-g6-2-general-resource-ownership.md`
- Verify: `src/build/sema_stream_lease.zig`
- Verify: `src/build/codegen_async_cleanup.zig`
- Verify: `src/build/codegen_component_stream_writer.zig`

**Interfaces:**

- Consumes: Task 3 matrix and the existing lease/resource cleanup implementation.
- Produces: a language-independent contract for any later private lowering change.

- [x] **Step 1: Verify the state set.**

Retain `owned`, `owned-deferred`, `borrowed-use`, `transferred`, `in-flight`, `finalized`, `cancelled`, and `maybe`; map each current compiler state to the documented internal concept.

- [x] **Step 2: Verify terminal and join rules.**

Require no use after transfer/finalization, no second transfer, equal branch/loop terminal state, and no scope exit with an unresolved or deferred owner. Keep `StreamWriterLeasePathConflict`, `StreamWriterDeferredTransfer`, and `StreamWriterAlreadyFinalized` as the stable boundary diagnostics.

- [x] **Step 3: Verify child-before-parent cleanup.**

Document and test the order `child endpoint/subtask -> stream/future -> waitable set -> frame`; keep the fixed waitable-set handle regression as the concrete proof that a dropped child handle is never reused as the waitable-set handle.

- [x] **Step 4: Verify cancellation semantics.**

State that cancellation marks the private frame terminal, releases live Component tasks/endpoints exactly once, and leaves already-issued external effects untouched. No rollback callback, operation-id, or compensation protocol is introduced.

---

### Task 5: Authorization gate for the next positive slice

**Files:**

- Modify: `doc/design/2026-08-03-g6-2-general-resource-ownership.md`
- Modify: `doc/pending_blocked.md`
- Create or update: `docs/superpowers/plans/2026-08-03-g6-2-first-positive-resource-slice.md`

**Interfaces:**

- Consumes: Tasks 1-4 and their command output.
- Produces: a separately reviewable positive implementation plan, or a documented no-go decision.

- [x] **Step 1: Apply the stopping gate.**

Authorize a positive slice only if the full regression, capability matrix, ownership invariants, and negative fixtures are green under the pinned toolchain.

- [x] **Step 2: Select the smallest new invariant.**

The selected bounded candidate is the private descriptor-bounded producer operation sequence already closed by the branch-selected `close`/`abort` terminal plan: one explicit lease transfer and one terminal completion, reusing the existing `StreamWriter<T>` lease states. It adds a real state transition; raising only the forwarding-depth or nesting constant is not sufficient.

- [x] **Step 3: Reject scope-expanding candidates.**

Do not authorize public ownership syntax, general async-call composition, arbitrary producer expressions, borrowed/list/variant stream fields, sixth forwarding, seventh nesting, or D2 host I/O in this phase.

- [x] **Step 4: Record the decision and hand off implementation.**

The branch-selected terminal plan is fully verified and handed off in
`docs/superpowers/plans/2026-08-03-g6-2-first-positive-resource-slice.md`.
This phase authorizes no second positive codegen expansion: any next shape
requires its own design, pinned-tool probe, negative fixtures, and explicit
review. Continue only with independent documentation, boundary maintenance,
or a separately authorized positive plan.

---

## Completion Criteria

This phase is complete when:

- the focused Zig, default, WASM, ReleaseSmall, and runtime checks have fresh output;
- all five status/design documents agree on the verified and blocked boundaries;
- the capability matrix has exact diagnostics and pinned tool versions;
- the ownership state machine and cancellation contract are explicit;
- the negative fixtures remain green and reject unsupported expansion at the correct layer;
- a separate positive implementation plan is authorized, or a no-go decision is documented.

The phase stops before public `own<T>`/`borrow<T>`/`ref<T>` syntax, general async lowering, and real D2 host runtime work.
