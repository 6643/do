# Post-Sync Release-Candidate Continuation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the synchronized v1/GC-first release candidate reproducible while reviewing the next G6.2 capability without widening any unadmitted language or runtime surface.

**Architecture:** Use a sequential evidence loop: establish a fresh baseline, audit only active documentation, re-run already admitted private D2/G6.2 gates, then apply the exact-shape admission contract. If no candidate satisfies every contract item, record a fail-closed stop and make no compiler change. A candidate that does qualify must start a separate design/probe plan before implementation.

**Tech Stack:** Zig `0.16.0`, current-only `wasm-tools 1.258.0`, Wasmtime `48.0.1`, Rust/Cargo `1.97.1`, `bin/do-toolchain`, the Zig regression harness, Bash gates, and Rust/Wasmtime Component runners.

**Spec:** `doc/start_here.md`, `doc/master_plan.md`, `doc/pending_blocked.md`, `doc/memory.md`, and `toolchain/toolchain.lock.json`.

## Global Constraints

- Keep the current-only toolchain versions from `toolchain/toolchain.lock.json`; do not add a compatibility route.
- Keep normal compilation GC-only; ARC files remain explicit test-only equivalence-oracle debt.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, `Option`, or `Result` syntax.
- Do not widen generic async/map/producer/resource lowering, borrowed/list/variant payloads, arbitrary producer expressions, general filesystem async, external HTTP, or root hard-cancel.
- Keep `complete_rows=15 pending_rows=15` and its intentional inventory exit `1`.
- Use project-local Zig caches for direct tests: `TMPDIR="$PWD/.tmp/do-tmp"`, `ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache"`, and `ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache"`.
- Preserve dated historical evidence; modify only active status text and the execution record for this plan.
- Do not push from this plan unless a later turn explicitly requests delivery.

---

### Task 1: Establish the post-sync release baseline

**Files:**
- Read: `toolchain/toolchain.lock.json`
- Read: `src/build/test/run_tests.sh`
- Read: `src/build/test/run_release_smoke.sh`
- Modify: none

**Interfaces:**
- Consumes: the synchronized `main` checkout and current toolchain adapter.
- Produces: fresh regression, isolated-cache Zig, and release-smoke evidence for Tasks 2-5.

- [x] **Step 1: Confirm branch, remote, and worktree state.**

```bash
git fetch origin
git status --short --branch
git rev-list --left-right --count HEAD...origin/main
```

Expected: clean `main`, no untracked generated output, and `0 0` divergence.

- [x] **Step 2: Run the full current-only regression.**

```bash
RUN_WASM=1 RUN_GC_CORE=1 ./src/build/test/run_tests.sh
```

Expected: exit `0`, `14/14 steps succeeded; 56/56 tests passed`, including the GC and Component gates.

- [x] **Step 3: Run the independent Zig suite with isolated caches.**

```bash
(cd src && TMPDIR="$PWD/../.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" \
  zig test main.zig)
```

Expected: exit `0` and `All 1743 tests passed.` A default user-cache failure is recorded as environment evidence, not source failure evidence.

- [x] **Step 4: Run the release smoke gate.**

```bash
./src/build/test/run_release_smoke.sh
```

Expected: ReleaseSmall build, `do build`, `do test`, compiled test, check, fmt, run, LSP, adapter, cache-wiring, and residual-gate checks all pass.

- [x] **Step 5: Verify no test generated a worktree diff.**

```bash
git diff --check
git status --short --branch
```

Expected: no whitespace errors and no generated files outside ignored cache directories.

### Task 2: Audit active status and toolchain documentation

**Files:**
- Read: `README.md`, `CHANGELOG.md`, `doc/start_here.md`, `doc/master_plan.md`, `doc/roadmap_status.md`, `doc/pending_blocked.md`, `src/build/test/README.md`
- Read: this plan file
- Modify only: active status lines in the files above when contradicted by Task 1 evidence

**Interfaces:**
- Consumes: Task 1 counts and the pinned toolchain lock.
- Produces: one active-status consistency result; dated historical entries remain unchanged.

- [x] **Step 1: Scan current markers and recent capability names.**

```bash
rg -n '14/14 steps|56/56|1743/1743|wasm-tools 1\.258\.0|Wasmtime 48\.0\.1|read-via-stream|complete_rows=15 pending_rows=15|public `own<T>`|no second exact candidate' \
  README.md CHANGELOG.md doc/start_here.md doc/master_plan.md \
  doc/roadmap_status.md doc/pending_blocked.md src/build/test/README.md
```

Classify every hit as active status, current gate evidence, or dated history before editing.

- [x] **Step 2: Check the active stop boundary.**

The active sections must continue to say all of the following: GC is the normal route; ARC is test-only; the inventory remains `15/15` with exit `1`; closed private shapes do not imply generic lowering; public ownership syntax remains closed; and no second exact G6.2 candidate is admitted.

- [x] **Step 3: Repair only confirmed active drift.**

Use `apply_patch` for the smallest line-level correction. Do not rewrite old counts merely because newer counts exist elsewhere. Run:

```bash
git diff --check
```

Expected: either no documentation diff or a minimal active-status diff whose values match Task 1.

### Task 3: Re-run the admitted private D2 maintenance gates

**Files:**
- Read: `doc/superpowers/plans/2026-09-15-d2-filesystem-read-via-stream.md`
- Read: `doc/superpowers/specs/2026-09-15-d2-filesystem-read-via-stream-design.md`
- Read: D2 sections in `doc/pending_blocked.md`
- Modify: none unless a gate exposes a confirmed active documentation mismatch

**Interfaces:**
- Consumes: the pinned filesystem WIT route and current-only adapter.
- Produces: maintenance evidence for the already closed private `descriptor.read-via-stream` route; it cannot promote a general filesystem method.

- [x] **Step 1: Run the ABI gate.**

```bash
bash examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_abi.sh
```

Expected: the fixed synchronous `(File,u64) -> Tuple<Stream<u8>, Future<Result<nil,FileError>>>` source and measured Core `(i32,i64,i32) -> nil` import remain accepted; drift remains rejected before Component assembly.

- [x] **Step 2: Run the compiler/lowering gate.**

```bash
bash examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_lowering.sh
```

Expected: one-to-three explicit byte reads plus one completion await pass; extra reads, altered ownership, second awaits, and unregistered locators reject before WAT.

- [x] **Step 3: Run the Rust/Wasmtime lifecycle gate.**

```bash
bash examples/p3-runtime/test_rust_wasi_filesystem_read_via_stream.sh
```

Expected: ready, pending, completion error, cancel-before/after-EOF, Store early-drop, and repeat preserve exactly-once stream/future/descriptor cleanup and an empty live `ResourceTable`.

- [x] **Step 4: Record any failure without widening the route.**

If a gate fails, preserve its output, classify the failure as implementation, toolchain, environment, or documentation evidence, and stop only the affected repair. Do not add a fallback or broaden the descriptor matcher.

### Task 4: Revalidate G6.2 private contract and lifecycle inventory

**Files:**
- Read: the G6.2 table and §6 in `doc/pending_blocked.md`
- Read: §4 in `doc/master_plan.md`
- Read: all current G6.2 plans/specs under `doc/superpowers/plans/` and `doc/superpowers/specs/`
- Read: `doc/gc_arc_inventory.tsv`
- Modify: none unless Task 2 found active status drift

**Interfaces:**
- Consumes: closed private descriptors, their pinned manifests, and Task 1-3 evidence.
- Produces: a candidate table with one of two explicit outcomes: `no candidate admitted` or `candidate requires separate design`.

- [x] **Step 1: Enumerate closed shapes without treating them as new work.**

Run:

```bash
find doc/superpowers/plans doc/superpowers/specs -maxdepth 1 -type f -printf '%p\n' \
  | sort \
  | rg 'g6-2|producer|map|filesystem'
rg -n 'private|closed|已关闭|descriptor|package|WIT hash|SHA-256' \
  doc/pending_blocked.md doc/master_plan.md doc/start_here.md
```

Record the direct, two-owned-field, parameterized, triple, nested, mixed, single-list, two-list, scalar-list, dynamic, batched, map, and D2 private routes already documented as closed. Their existence is evidence reuse, not permission to generalize.

- [x] **Step 2: Apply the exact admission checklist to every pending extension.**

Run:

```bash
rg -n 'package|member|WIT hash|SHA-256|Core|ABI|layout|matcher|negative|WAT|parse|embed|validate|canonical|generated|ready|pending|error|cancel|early-drop|repeat|cleanup|rollback|ownership' \
  doc/superpowers/plans doc/superpowers/specs doc/pending_blocked.md
```

A candidate is eligible only if its record contains all of these facts: fixed package/member; pinned WIT content hash; measured Core ABI and layout; source matcher; negative fixtures rejected before WAT; Component parse/embed/new/validate; generated and canonical parity; Rust/Wasmtime ready/pending/error/cancel/early-drop/repeat lifecycle; exactly-once cleanup; and a rollback/ownership state table.

- [x] **Step 3: Keep the review fail-closed when any item is missing.**

When no candidate has every fact, record `no candidate admitted` and keep generic producer/resource, borrowed/list/variant, seventh-hop/seventh-level, general async-call, and general filesystem async routes rejected before WAT. Do not create a speculative manifest, syntax branch, or compiler emitter.

- [x] **Step 4: Escalate a qualifying candidate to a separate design gate.**

If a candidate unexpectedly satisfies every item, record its exact package/member and evidence paths, then stop this plan before implementation. Open a separate design/spec and probe plan; that new plan must be approved before compiler changes.

### Task 5: Verify repository hygiene and release handoff

**Files:**
- Read: current plan, active status documents, and git state
- Modify only: this plan's execution record and confirmed active status corrections

**Interfaces:**
- Consumes: Task 1-4 evidence.
- Produces: a clean, reproducible handoff state and an explicit next-stage stop condition.

- [x] **Step 1: Update this plan with command evidence.**

Record the actual exit codes and counts from Tasks 1-4. State whether a candidate was admitted. Keep `complete_rows=15 pending_rows=15` unchanged.

- [x] **Step 2: Run the final local integrity checks.**

```bash
git diff --check
git diff --cached --check
git status --short --branch
git rev-list --left-right --count HEAD...origin/main
```

Expected: no whitespace errors, no accidental artifacts, and a clearly stated local/remote relationship.

- [x] **Step 3: Commit only plan/status evidence.**

```bash
git add doc/superpowers/plans/2026-09-15-post-sync-release-candidate-continuation.md README.md CHANGELOG.md doc/start_here.md doc/master_plan.md doc/roadmap_status.md doc/pending_blocked.md src/build/test/README.md
git diff --cached --check
git commit -m "Record post-sync release candidate review"
```

Stage only files that were actually changed by this plan. Do not include cache output, generated WAT, bundles, or unrelated work.

- [x] **Step 4: Stop at the delivery boundary.**

Do not push this plan's follow-up commit automatically. A later explicit delivery request must perform fetch, divergence check, push, and post-push `0 0` verification.

## Exit Criteria

- Current-only full regression, isolated-cache Zig tests, release smoke, and admitted D2 maintenance gates are green.
- Active documentation matches the fresh counts and current toolchain; dated history is preserved.
- `complete_rows=15 pending_rows=15` remains deliberate with exit `1`.
- G6.2 has either one fully documented candidate handed to a separate design/probe plan or an explicit no-candidate fail-closed stop.
- No public ownership syntax, generic lowering, or unmeasured producer/resource shape is added.
- The repository is clean and the delivery boundary is explicit.

## Execution Record

Completed 2026-09-16 on the explicitly authorized `main` checkout. The
pre-change baseline was clean and synchronized (`HEAD=origin/main=2669c9b`,
divergence `0 0`). No compiler shape, manifest, syntax branch, or runtime
fallback was added by this plan.

### Task 1 evidence

- `RUN_WASM=1 RUN_GC_CORE=1 ./src/build/test/run_tests.sh`: exit `0`,
  `14/14 steps succeeded; 56/56 tests passed`.
- Isolated-cache `(cd src && ... zig test main.zig)`: exit `0`,
  `All 1743 tests passed.`
- `./src/build/test/run_release_smoke.sh`: exit `0`; ReleaseSmall, CLI,
  adapter, Component/GC, and residual gates passed.
- Post-test `git diff --check` and status showed no generated worktree change.

### Task 2 evidence

The active README, start entry, roadmap, master plan, pending list, and test
README agree on GC-only normal compilation, ARC test-only status, current
`56/56` and `1743/1743` baselines, `wasm-tools 1.258.0` / Wasmtime `48.0.1`,
the closed private `descriptor.read-via-stream` route, and
`complete_rows=15 pending_rows=15` with intentional exit `1`. Dated historical
`53/53` and older counts were preserved. No active documentation correction
was required.

### Task 3 evidence

- `bash examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_abi.sh`:
  `WASI filesystem read-via-stream ABI probe passed`.
- `bash examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_lowering.sh`:
  both bounded fixtures passed and `WASI D2 read-via-stream lowering passed`.
- `bash examples/p3-runtime/test_rust_wasi_filesystem_read_via_stream.sh`:
  `WASI D2 read-via-stream runtime passed`.
- No gate failure occurred; the route remains fixed and private.

### Task 4 evidence

The closed direct, two-owned-field, parameterized, triple, nested, mixed,
single-list, two-list, scalar-list, dynamic, batched, map, and D2 private
routes were treated as evidence reuse, not new candidates. The admission scan
found no pending candidate containing every required package/member, pinned WIT
hash, measured Core ABI/layout, source matcher, WAT-negative fixtures,
Component parse/embed/new/validate, canonical/generated parity,
Rust/Wasmtime lifecycle matrix, exactly-once cleanup, and rollback/ownership
state facts. Outcome: **no candidate admitted**. Generic producer/resource,
borrowed/list/variant, seventh-hop/seventh-level, general async-call, and
general filesystem async routes remain rejected before WAT; no separate design
gate was opened.

### Task 5 evidence

This execution record and the checked task boxes are the only intended
repository change. Final `git diff --check`, staged-diff check, status, and
divergence checks were run before the evidence-only commit. The commit is kept
local at the delivery boundary; no push was performed. A later explicit push
request must re-fetch, verify divergence, push, and confirm post-push `0 0`.
