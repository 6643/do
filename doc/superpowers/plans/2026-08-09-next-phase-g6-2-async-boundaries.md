# G6.2 And Async Boundary Next Phase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the next independently verifiable G6.2 and colorless-async capability boundaries without widening public ownership syntax or silently generalizing the existing bounded lowerings.

**Architecture:** Work in a gate-first sequence. Refresh the pinned WIT capability matrix, then probe one new bounded pure-scalar list producer (`stream<list<u32>>`) as an isolated G6.2 shape. In parallel, freeze the promotion contract for general async-call lowering and the D2 filesystem boundary, but do not implement either until their canonical ABI, ownership, cancellation, Component, and Rust/Wasmtime gates are independently green. A failed pinned probe is a recorded no-go result, not a reason to weaken a registry predicate or add a compatibility fallback.

**Tech Stack:** Zig 0.16.0, Do compiler, WIT/Core WAT, `wasm-tools` 1.255.0 for current capability probes, pinned legacy `wasm-tools` 1.254.0 where async assembly requires it, Rust 1.97.1, Wasmtime 47.0.2, Bash regression gates, and the existing `src/build/test/run_tests.sh` harness.

## Global Constraints

- Preserve the clean `main`/`origin/main` baseline before each task; unrelated worktree changes are not part of this phase.
- Keep ordinary public result APIs as `T | E` or `nil | E`; private WIT/Component `Result` rows remain ABI metadata only.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, lifetime, `externref`, `anyref`, or `funcref` syntax.
- Do not change `@host_func`, `@host_async_func`, `@async`, `@await`, or `@cancel` semantics while running probes.
- Keep `--p3-async-component`, `--p3-async-component-v2`, and `--p3-async-call-component` opt-in; unsupported shapes must fail before WAT emission.
- Every admitted positive shape requires a pinned WIT hash, measured canonical layout, explicit ownership matrix, positive and negative fixtures, Component validation, and Rust/Wasmtime ready/pending/error/cancel cleanup evidence.
- Cancellation remains Component/WASI-aligned: drop live async state exactly once and never roll back an external effect already issued before cancellation.
- The existing `future<borrow<T>>` and `stream<record { ticket: borrow<T> }>` rejection is a toolchain boundary until a newly pinned toolchain proves otherwise.
- This phase may create probes and design documents; compiler registry/emitter promotion is a separate follow-up plan after the relevant gate is green.

## Order And Gates

| Order | Task | Deliverable | Stop condition |
| --- | --- | --- | --- |
| 1 | Baseline | Reproducible current counts and tool versions | Any baseline regression blocks feature work |
| 2 | Borrow refresh | Current capability matrix and exact rejection evidence | Rejection remains recorded; no ownership promotion |
| 3 | G6.2 scalar-list probe | Independent ABI/runtime evidence for `stream<list<u32>>` | Green probe authorizes a later promotion plan; red probe is a no-go |
| 4 | General async design | Explicit frame, payload, multi-await, and cancellation promotion contract | No compiler widening in this phase |
| 5 | D2 boundary design | Per-method ABI/host gate matrix for general filesystem async | No generic filesystem or external HTTP lowering |
| 6 | Closeout | Truthful roadmap/status and full regression evidence | Only green artifacts are marked complete |

### Task 1: Freeze the baseline and remaining boundaries

**Files:**
- Verify: `doc/start_here.md`
- Verify: `doc/roadmap_status.md`
- Verify: `doc/pending_blocked.md`
- Verify: `doc/host_abi_blockers.md`
- Verify: `doc/master_plan.md`

**Interfaces:**
- Consumes: the current local `main` baseline at `6274960`, current pinned tools,
  and the existing bounded async/G6.2 gates. The three local commits after
  `cb2aa40` are already recorded baseline/status updates, not feature work for
  this phase.
- Produces: a command-backed starting point with no stale claim that private D2, owned-future, or inline scalar slices are generic capabilities.

- [x] **Step 1: Verify checkout identity.**

Run:

```bash
git status --short --branch
git rev-parse main origin/main
git log -1 --oneline --decorate
```

Observed: `main` is at `6274960 docs: record restored Zig baseline` and is
three commits ahead of `origin/main` (`cb2aa40`). The worktree contains only the
untracked plan and Task 2 evidence document being carried by this phase; no
compiler or fixture edits are present.

- [x] **Step 2: Verify tool versions.**

Run:

```bash
zig version
wasm-tools --version
rustc --version
wasmtime --version
```

Observed: Zig `0.16.0`, `wasm-tools 1.255.0 (76e20611d 2026-07-30)`, Rust
`1.97.1`, and Wasmtime `47.0.2`.

- [x] **Step 3: Run the baseline suites.**

Run:

```bash
cd src && zig test main.zig
cd ..
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

Observed: `zig test main.zig` passes `312/312`; the default harness reports
`pass=1158 fail=0 skip=3`; the Wasm harness reports `pass=1160 fail=0 skip=3`
with Wasm smoke `6/6`; ReleaseSmall smoke passes all eight checks and
`git diff --check` passes. The `308/308` and `1151` values in the original
draft were stale; the current status documents already record the verified
counts.

- [x] **Step 4: Commit only a baseline note when evidence changed.**

If the counts or pinned versions differ, update the dated baseline paragraph
in `doc/roadmap_status.md` and `doc/start_here.md`, then run the same commands
again and commit:

```bash
git add doc/roadmap_status.md doc/start_here.md
git commit -m "docs: refresh next-phase baseline"
```

The status documents already contain the observed `312/312`, `1158`, and
`1160` values from the preceding baseline commit, so no additional status
commit is required for Task 1.

### Task 2: Refresh the pinned borrow and ownership capability matrix

**Files:**
- Create: `doc/superpowers/specs/2026-08-09-borrow-capability-refresh-design.md`
- Verify: `examples/p3-runtime/test_borrow_capability_matrix.sh`
- Verify: `examples/p3-runtime/test_list_borrow_canonical_abi.sh`
- Verify: `examples/p3-runtime/test_future_owned_canonical_abi.sh`
- Modify: `doc/pending_blocked.md` only when fresh output differs

**Interfaces:**
- Consumes: `WASM_TOOLS_EXPECT_VERSION=1.255.0`, the existing borrowed-list
  canonical probe, and the owned-future canonical probe.
- Produces: a dated matrix with exact accepted/rejected WIT rows, tool hashes,
  stderr for rejected nested borrows, and an explicit no-promotion decision.

- [x] **Step 1: Run the matrix and canonical probes.**

Run:

```bash
WASM_TOOLS_EXPECT_VERSION=1.255.0 \
  bash examples/p3-runtime/test_borrow_capability_matrix.sh
bash examples/p3-runtime/test_list_borrow_canonical_abi.sh
bash examples/p3-runtime/test_future_owned_canonical_abi.sh
```

Observed: all six accepted rows and both rejected rows matched this matrix;
the two rejections occurred during `component embed` with the expected
`contains a \`borrow<T>\` which is not supported` diagnostic.

- [x] **Step 2: Write the evidence and stop conditions.**

`doc/superpowers/specs/2026-08-09-borrow-capability-refresh-design.md` must
record the `wasm-tools` version/hash, WIT hashes used by each script, the full
matrix, and these conclusions:

```text
list<borrow<T>> is proven only for the synchronous canonical list probe.
future<borrow<T>> and stream<record { ticket: borrow<T> }> remain blocked.
future<own<T>> is proven only by the existing private canonical/runtime slice.
No compiler registry entry or public ownership syntax is added by this task.
```

- [x] **Step 3: Re-run compiler drift guards.**

Run:

```bash
cd src && zig test build/p3_async_manifest.zig
cd ..
bash examples/p3-runtime/test_do_borrowed_resource_rejection.sh
```

Observed: `p3_async_manifest` passed `87/87`, the existing Do borrowed
resource rejection passed, and `git diff` contains no compiler, registry,
sema, or generated-WAT changes.

- [x] **Step 4: Commit the evidence-only refresh.**

```bash
git add doc/superpowers/specs/2026-08-09-borrow-capability-refresh-design.md \
  doc/pending_blocked.md
git commit -m "docs: refresh borrow capability boundary"
```

Commit only the evidence document; no `src/build` files or public ownership
syntax are part of this task.

### Task 3: Probe a bounded pure-scalar list producer

**Files:**
- Create: `doc/superpowers/specs/2026-08-09-g6-2-scalar-list-producer-design.md`
- Create: `examples/p3-runtime/wit/g6-2-scalar-list-producer.wit`
- Create: `examples/p3-runtime/g6-2-scalar-list-producer-canonical.wat`
- Create: `examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_scalar_list_producer_abi.rs`

**Interfaces:**
- Consumes: the current capacity-one stream producer protocol and the fresh
  toolchain matrix from Task 2.
- Produces: an independent ABI/runtime probe for one bounded
  `stream<list<u32>>` producer; it does not modify `p3_async_registry.json`,
  sema admission, or codegen.

The WIT source must contain this exact shape:

```wit
package do:g6-2-scalar-list-producer@0.1.0;

interface types {
  enum error-code { io, pipe, invalid-mode }
}

interface sink {
  use types.{error-code};
  consume-via-stream: async func(data: stream<list<u32>>) -> result<_, error-code>;
}

world scalar-list-producer {
  use types.{error-code};
  import sink;
  export produce: async func(count: u32) -> result<_, error-code>;
}
```

- [x] **Step 1: Define the probe contract and red gate.**

The design must freeze capacity `3`, count parameter `u32`, and the four
positive rows `0 -> []`, `1 -> [10]`, `2 -> [10, 20]`, `3 -> [10, 20, 30]`.
Count `4` must return `Err(invalid-mode)` without invoking the sink. The shell
gate must require the WIT, canonical WAT, and Rust runner and fail loudly when
one is absent; it may not silently skip a missing artifact.

Run before adding the probe artifacts:

```bash
bash examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh
```

Observed: the red gate failed before assembly with
`missing probe artifact: .../g6-2-scalar-list-producer-canonical.wat`.

- [x] **Step 2: Implement the hand-authored canonical WAT and host oracle.**

The WAT must expose the measured list pointer/length path and preserve explicit
marker comments for pointer word offsets, list element stride, capacity, and
the single stream item slot. It must exercise ready, pending, sink error, early
drop, cancellation before transfer, and cancellation after transfer.

The Rust runner must print machine-checkable rows for all five count/error
cases, assert ordered list contents, count one sink callback per admitted
positive row, and assert exactly one list allocation release on every terminal
path. Because the list contains only `u32`, the probe must report an empty
`ResourceTable`; it must not invent resource drops or treat a list pointer as a
Do pointer/reference type.

- [x] **Step 3: Validate the independent ABI/runtime gate.**

Run:

```bash
wasm-tools component wit examples/p3-runtime/wit/g6-2-scalar-list-producer.wit
sha256sum examples/p3-runtime/wit/g6-2-scalar-list-producer.wit
bash examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh
```

Observed: `wasm-tools component wit` and `sha256sum` matched the design;
Component assembly/validation succeeded with `wasm-tools 1.255.0`, the Rust
runner passed all count, pending, sink-error, early-drop, and both cancellation
rows under Wasmtime `47.0.2`, and the measured layout/release invariant is
recorded in the design. No compiler descriptor was added.

- [x] **Step 4: Commit only the probe evidence.**

```bash
git add doc/superpowers/specs/2026-08-09-g6-2-scalar-list-producer-design.md \
  examples/p3-runtime/wit/g6-2-scalar-list-producer.wit \
  examples/p3-runtime/g6-2-scalar-list-producer-canonical.wat \
  examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh \
  examples/p3-runtime/rust-host-runner/src/bin/g6_2_scalar_list_producer_abi.rs
git commit -m "Probe bounded scalar list producer ABI"
```

A green probe authorizes a separate implementation plan for registry/sema and
compiler lowering. It does not itself promote `stream<list<u32>>` into Do.

### Task 4: Close the general async-call promotion design

**Files:**
- Create: `doc/superpowers/specs/2026-08-09-general-async-call-promotion-design.md`
- Verify: `doc/superpowers/specs/2026-08-07-general-async-call-lowering-design.md`
- Verify: `src/build/codegen_component_async_call_plan.zig`
- Verify: `src/build/codegen_component_async_call.zig`
- Verify: `examples/p3-runtime/test_async_call_component_probe.sh`
- Verify: `examples/p3-runtime/test_rust_async_call_component.sh`

**Interfaces:**
- Consumes: the current unit, scalar-argument, inline-scalar, and owned-future
  bounded contracts.
- Produces: a promotion contract for arbitrary producer expressions, multiple
  awaits, payload/resource/list/stream values, and host-call arguments without
  changing the current implementation.

- [x] **Step 1: Capture the current bounded frame facts.**

The design must state the currently verified root-owned frames and cleanup
events: the inline scalar frame is 20 bytes with its `u32` slot at offset `12`;
event `6` drops the active future/subtask, waitable set, context, and frame
exactly once; the existing owned-future probe uses its independently measured
payload/presence layout. These facts are evidence for future design, not a
generic layout formula.

- [x] **Step 2: Define the promotion contract.**

The document must specify, without implementation placeholders:

```text
Inputs: arbitrary producer expression, zero or more host arguments, multiple
await/cancel sites, and a declared payload shape.
State: one root continuation plus an explicit waitable set, active operation,
payload ownership state, and terminal state.
Cancellation: cancel the active Component subtask, release live guest state in
reverse ownership order, and never compensate an already-issued host effect.
Admission: every payload/argument/producer shape has its own pinned WIT/WAT
probe and positive/negative Component/Rust/Wasmtime matrix.
```

The design must explicitly reject public ownership syntax, implicit async
contagion, independent guest child tasks where the pinned ABI cannot support
them, and generic lowering inferred from one private descriptor.

- [x] **Step 3: Re-run the existing boundary gates.**

Run:

```bash
bash examples/p3-runtime/test_async_call_component_probe.sh
bash examples/p3-runtime/test_rust_async_call_component.sh \
  /tmp/async-call-component.component.wasm
cd src && zig test build/codegen_component_async_call_plan_test.zig
zig test build/codegen_component_async_call_test.zig
```

Expected: the bounded unit/child-only rows remain green and unsupported
payload, multiple-child, arbitrary-producer, and nested shapes remain rejected
before WAT. Any new acceptance is a design regression, not a feature win.

- [x] **Step 4: Commit the design-only closure.**

```bash
git add doc/superpowers/specs/2026-08-09-general-async-call-promotion-design.md
git commit -m "docs: freeze general async-call promotion boundary"
```

Do not modify `codegen_component_async_call*` in this task.

### Task 5: Define the D2 general filesystem/HTTP gate

**Files:**
- Create: `doc/superpowers/specs/2026-08-09-d2-general-filesystem-async-boundary-design.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Verify: `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit`
- Verify: `examples/p3-runtime/test_d2_wasi_filesystem_get_type_abi.sh`
- Verify: `examples/p3-runtime/test_d2_wasi_filesystem_sync_abi.sh`
- Verify: `examples/p3-runtime/test_d2_wasi_filesystem_get_flags_abi.sh`

**Interfaces:**
- Consumes: the three closed private filesystem method probes and the pinned
  upstream filesystem WIT hash.
- Produces: a method-by-method recovery matrix for `read`, `write`, `stat`,
  `open-at`, directory mutation, and external HTTP, with no generic compiler
  admission.

- [x] **Step 1: Revalidate the closed D2 anchors.**

Run:

```bash
bash examples/p3-runtime/test_d2_wasi_filesystem_get_type_abi.sh
bash examples/p3-runtime/test_d2_wasi_filesystem_sync_abi.sh
bash examples/p3-runtime/test_d2_wasi_filesystem_get_flags_abi.sh
```

Expected: all three private ABI probes remain green and continue to report the
same pinned upstream WIT identity. A changed method signature requires a new
probe record; do not infer it from an older method.

- [x] **Step 2: Classify each unadmitted method.**

For each method, record its exact WIT signature, canonical result/payload
shape, resource drops, stream/list/borrow requirements, pending and cancel
protocol, and the host-side observable cleanup counters required for a green
gate. The design must state that `read`/`write` and stream-producing methods
need separate list/stream/resource probes, while external HTTP needs a
separate service-world and payload-error gate.

- [x] **Step 3: Preserve the no-go boundary.**

Run:

```bash
cd src && zig test build/p3_filesystem_wit_manifest.zig
cd ..
bash examples/p3-runtime/test_do_borrowed_resource_rejection.sh
```

Expected: current manifest and borrowed-payload rejection remain green. The
compiler must still reject unregistered filesystem methods, borrowed payloads,
arbitrary producer expressions, and public ownership syntax before WAT.

- [x] **Step 4: Commit the D2 boundary record.**

```bash
git add doc/superpowers/specs/2026-08-09-d2-general-filesystem-async-boundary-design.md \
  doc/host_abi_blockers.md doc/pending_blocked.md
git commit -m "docs: define D2 general async recovery gates"
```

### Task 6: Close out the phase and hand off promotion work

**Files:**
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/master_plan.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: the baseline, capability refresh, scalar-list probe result, async
  promotion design, and D2 boundary design.
- Produces: truthful status with each green evidence slice named separately and
  each no-go retaining its exact recovery condition.

- [x] **Step 1: Update only verified status.**

If Task 3 is green, record the scalar-list ABI/runtime probe as evidence-only
and link its design; do not call it a compiler capability. If Task 3 is red,
record the exact tool/runtime failure under G6.2 and leave the previous
bounded descriptors unchanged. Keep `future<borrow<T>>`, borrowed stream
records, generic async-call lowering, generic filesystem async, external HTTP,
and public ownership syntax pending or deferred.

- [x] **Step 2: Run the complete closeout matrix.**

Run:

```bash
cd src && zig test main.zig
cd ..
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

Expected: the same baseline counts from Task 1, plus every green probe named
in the status documents. No new skip, registry entry, public type, or changed
diagnostic is allowed without its own plan and fixture.

- [x] **Step 3: Commit the phase handoff.**

```bash
git add doc/superpowers/plans/2026-08-09-next-phase-g6-2-async-boundaries.md \
  doc/start_here.md doc/roadmap_status.md doc/pending_blocked.md \
  doc/host_abi_blockers.md doc/master_plan.md CHANGELOG.md
git commit -m "docs: plan next G6.2 and async boundary phase"
```

Pushing is a separate delivery action and is not part of this implementation
plan.

## Self-Review

- **Coverage:** baseline, pinned borrow evidence, one new bounded G6.2 probe,
  general async promotion criteria, D2 recovery criteria, and final status are
  each represented by a task with commands and stop conditions.
- **No placeholders:** every future artifact has an exact path or an explicit
  no-go result, and every verification step names its command and outcome.
- **Type consistency:** the scalar-list WIT uses `stream<list<u32>>`, count is
  `u32`, the accepted list lengths are `0..3`, and the invalid row is `4`.
  Borrowed rows and owned rows remain separate capability classes.
- **Scope:** no task modifies generic lowering or public ownership syntax;
  compiler promotion begins only in a separately approved plan after a green
  canonical probe.
