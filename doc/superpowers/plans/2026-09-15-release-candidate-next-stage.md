# Release-Candidate Maintenance and G6.2 Next-Stage Admission Plan

> **For agentic workers:** This plan is executed inline in the explicitly authorized `main` checkout. Steps use checkbox syntax for tracking.

**Goal:** Keep the v1/GC-first release candidate reproducible and close the next G6.2 admission review without widening generic lowering or public ownership syntax.

**Architecture:** The current GC-only default route, bounded private Component routes, and fail-closed capability boundaries remain unchanged. The first two tasks are maintenance and evidence audits; a new producer/resource implementation is allowed only after a separate exact-shape admission record satisfies every lifecycle and ABI gate.

**Tech Stack:** Zig `0.16.0`, current-only `wasm-tools 1.258.0`, Wasmtime `48.0.1`, Rust/Cargo `1.97.1`, the Zig regression harness, Bash gates, and Rust/Wasmtime Component runners.

**Spec:** `doc/pending_blocked.md`, `doc/master_plan.md`, `doc/start_here.md`, and `doc/roadmap_status.md`.

## Global Constraints

- Keep `complete_rows=15 pending_rows=15` and the intentional inventory exit `1`.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, `Option`, or `Result` syntax.
- Do not widen generic async/map/producer/resource lowering, borrowed/list/variant payloads, or general filesystem async.
- Use the current-only `bin/do-toolchain` route and the pinned toolchain versions above.
- Run independent Zig tests with project-local caches: `TMPDIR="$PWD/.tmp/do-tmp"`, `ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache"`, and `ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache"`.
- Preserve historical evidence; update only active status sections when a real drift is found.
- Stage only files belonging to this plan; do not push a new implementation shape without a separate explicit delivery request.

### Task 1: Revalidate the release-candidate baseline

**Files:**
- Read: `src/build/test/run_tests.sh`, `src/build/test/run_release_smoke.sh`
- Test: repository regression and release gates

**Interfaces:** Consumes the current compiler, toolchain adapter, and registered private gates. Produces fresh counts and exit codes for Tasks 2–4.

- [x] **Step 1: Confirm checkout and remote state.**

  ```bash
  git status --short --branch
  git fetch origin
  git rev-list --left-right --count HEAD...origin/main
  ```

  Expected: clean `main`, no unreviewed code changes, and no remote divergence.

- [x] **Step 2: Run the full current-only regression.**

  ```bash
  RUN_WASM=1 RUN_GC_CORE=1 ./src/build/test/run_tests.sh
  ```

  Expected: `14/14 steps succeeded; 56/56 tests passed` and exit `0`.

- [x] **Step 3: Run the independent Zig suite with isolated caches.**

  ```bash
  (cd src && TMPDIR="$PWD/../.tmp/do-tmp" \
    ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" \
    ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" \
    zig test main.zig)
  ```

  Expected: `All 1743 tests passed.` A failure in the default user cache is classified as environment evidence and is not used as source failure evidence.

- [x] **Step 4: Run the release smoke.**

  ```bash
  ./src/build/test/run_release_smoke.sh
  ```

  Expected: ReleaseSmall build, `do build`, `do test`, compiled test, check, fmt, run, lsp, adapter, cache-wiring, and residual-gate checks all pass.

- [x] **Step 5: Verify the pending diff.**

  ```bash
  git diff --check
  git status --short --branch
  ```

  Expected: no whitespace errors and no generated artifacts in the worktree.

### Task 2: Audit active documentation and residual status

**Files:**
- Read: `README.md`, `CHANGELOG.md`, `doc/start_here.md`, `doc/master_plan.md`, `doc/roadmap_status.md`, `doc/pending_blocked.md`, `src/build/test/README.md`
- Modify only if active text contradicts fresh Task 1 evidence.

**Interfaces:** Consumes Task 1 counts and the current toolchain lock. Produces an active-status consistency result; historical sections remain unchanged.

- [x] **Step 1: Scan active baseline markers.**

  ```bash
  rg -n '14/14 steps; 56/56 tests|1743/1743|wasm-tools 1\.258\.0|read-via-stream|complete_rows=15 pending_rows=15' \
    README.md CHANGELOG.md doc/start_here.md doc/master_plan.md \
    doc/roadmap_status.md doc/pending_blocked.md src/build/test/README.md
  ```

  Classify each hit as active status, current gate evidence, or historical record before editing.

- [x] **Step 2: Check the current stop boundary.**

  Confirm that active sections still state: bounded private gates are closed, generic routes fail closed, public ownership syntax is pending, and no second exact candidate is admitted.

- [x] **Step 3: Repair only confirmed active drift.**

  Use `apply_patch` on the smallest affected documentation lines, then rerun `git diff --check` and Task 1. Do not rewrite historical counts or broaden claims from a private gate.

### Task 3: Run the next G6.2 admission review

**Files:**
- Read: `doc/pending_blocked.md:563`, `doc/pending_blocked.md:1194`, `doc/roadmap_status.md:623-633`, and all candidate-specific plans/specs under `doc/superpowers/`.
- Create: no implementation or public syntax files.

**Interfaces:** Consumes the active capability inventory and existing private route evidence. Produces either one exact candidate admission record or an explicit no-candidate stop.

- [x] **Step 1: Enumerate already closed shapes.**

  Record the existing bounded descriptor, producer, resource, map, and GC routes without treating them as new candidates.

- [x] **Step 2: Apply the admission checklist to every proposed extension.**

  A candidate must specify a fixed package/member, pinned WIT hash, measured Core ABI/layout, source matcher, WAT-before negative fixtures, Component parse/embed/new/validate, Rust/Wasmtime ready/pending/error/cancel/early-drop/repeat lifecycle, exactly-once cleanup, and canonical/generated parity.

- [x] **Step 3: Close the review fail-closed when no candidate qualifies.**

  Current evidence has no second exact candidate. Keep generic producer/resource, borrowed/list/variant, seventh-hop/seventh-level, general async-call, and general filesystem async routes rejected before WAT; do not add a speculative descriptor or compiler branch.

### Task 4: Handoff and delivery checkpoint

**Files:**
- Modify only the plan/status document if Task 2 found confirmed drift.

**Interfaces:** Consumes Task 1–3 evidence. Produces a clean, reproducible release-candidate checkout and a documented stop condition for the next implementation stage.

- [x] **Step 1: Mark each completed plan task with command evidence.**
- [x] **Step 2: Re-run `git diff --cached --check` before any commit.**
- [x] **Step 3: Commit only this plan and confirmed status corrections; push only after an explicit delivery request.**

## Exit Criteria

- Fresh full regression, isolated-cache Zig suite, and release smoke are green.
- Active documentation matches the fresh toolchain and test baseline.
- `complete_rows=15 pending_rows=15` remains deliberate and unchanged.
- No new implementation shape is opened without a separate exact admission record.
- The next implementation task is either a newly admitted exact G6.2 shape or continued release-candidate maintenance; generic widening is not an exit condition.

## Execution Record (2026-09-16)

- Task 1 evidence: `git fetch origin` and `git rev-list --left-right --count HEAD...origin/main` reported `1 0` (the intentional local plan commit is one commit ahead; origin did not advance); `RUN_WASM=1 RUN_GC_CORE=1 ./src/build/test/run_tests.sh` reported `14/14 steps succeeded; 56/56 tests passed`; isolated-cache `zig test main.zig` reported `All 1743 tests passed.`; `./src/build/test/run_release_smoke.sh` passed every listed check.
- Task 2 evidence: active baseline and stop-boundary scans match the current lock and keep historical dated counts unchanged.
- Task 3 evidence: closed private shapes are documented in the current plans/specs; no second exact candidate has a complete pinned ABI, source matcher, negative matrix, Component gate, Rust/Wasmtime lifecycle gate, and canonical/generated parity package. The review therefore remains fail-closed.
- Task 4 state: the plan was initially committed as `15c34a8` and its evidence correction as `4541cbd`; push remains intentionally deferred because this turn did not include a delivery request. No code, public syntax, manifest, or capability inventory changes were made.
