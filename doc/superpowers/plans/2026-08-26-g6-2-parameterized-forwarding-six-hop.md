# G6.2 Parameterized Forwarding Six-Hop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan task-by-task with review checkpoints. Preserve unrelated dirty changes in the current `main` checkout.

**Goal:** Admit exactly six parameterized `StreamWriter<u8>` forwarding helper edges while preserving the existing descriptor, ABI, ownership, and fail-closed boundaries.

**Architecture:** Reuse the existing `StreamWriterPlan` parser and private async producer emitter. The only compiler admission widening is the measured hop bound `5 → 6`; all parameter matching, helper non-export, lease transfer, and terminal cleanup checks remain unchanged. The positive fixture gets an independent Component/Rust/Wasmtime gate, while a seventh-hop fixture keeps the explicit rejection boundary.

**Tech Stack:** Zig `0.16.0`, `wasm-tools 1.255.0`, Wasmtime `47.0.2`, repository shell gates, and the existing Rust host runner.

**Spec:** `doc/superpowers/specs/2026-08-26-g6-2-parameterized-forwarding-six-hop-design.md`

## Verification status (2026-08-26)

The six-hop implementation is present in the current checkout and has fresh
evidence: the analyzer filter passes `5/5`; the Do/Component positive gate,
seventh-hop/general-boundary negative gate, and Rust/Wasmtime matrix all pass
with Zig `0.16.0`, `wasm-tools 1.255.0`, and Wasmtime `47.0.2`. The runtime
matrix covers `count=0/1/3`, `value=90`, pending/ready/`Err(pipe)`, early drop,
and cancel-after-transfer with one callback, one stream drop, an empty
`ResourceTable`, and exactly-once cleanup. The repository bundle also passes
`run_tests.sh` (`1388/0/3`), `zig test main.zig` (`682/682`), default GC
(`86 fixtures`), residual/equivalence, ReleaseSmall, and release smoke; the
inventory remains deliberately `complete_rows=15 pending_rows=15` with exit
`1`.

The unchecked steps below preserve the historical red/green execution order;
the historical pre-change failure run is not reconstructed. This status does
not widen the six-hop boundary or authorize a seventh hop, arbitrary producer,
ownership syntax, or full GC cutover.

## Global Constraints

- Keep the descriptor and WIT world identical to `stream-probe-guest-producer-parameterized-five-hop`.
- Keep canonical imports free of Wasm GC reference types.
- Re-measure frame offsets; do not assume `52/60` without WAT evidence.
- Keep helpers private and export only `produce`.
- Keep `count=0/1/3`, `value=90`, exactly-once stream cleanup, and empty `ResourceTable` invariants.
- Keep seventh-hop, arbitrary producer, borrowed, variant, generic list, public ownership syntax, and full GC cutover out of scope.
- Preserve all unrelated dirty changes; do not reset, clean, or push as part of this plan.

---

### Task 1: Reconfirm the release-candidate baseline

**Files:**

- Read-only: current compiler, gates, and dirty worktree

**Interfaces:**

- Consumes: current `main` checkout and pinned toolchain.
- Produces: fresh baseline evidence before any six-hop change.

- [ ] **Step 1: Record checkout and tool versions.**

```bash
git status --short --branch
zig version
command -v wasm-tools
wasm-tools --version
wasmtime --version
```

Expected: branch remains `main`, existing dirty changes remain visible, and versions
are `0.16.0`, `1.255.0`, and `47.0.2`.

- [ ] **Step 2: Run focused async boundary tests.**

```bash
(cd src && zig test build/codegen_component_async_plan.zig)
bash examples/p3-runtime/test_do_g6_general_boundary_rejection.sh
```

Expected: existing tests pass and both sixth-forwarding and arbitrary-producer fixtures
are rejected before WAT.

- [ ] **Step 3: Stop on a baseline regression.**

Do not edit the six-hop path if either command fails; capture the failure and repair or
reconcile the unrelated regression first.

### Task 2: Add analyzer red tests for six-hop admission

**Files:**

- Modify: `src/build/codegen_component_async_plan.zig` near the existing fifth/sixth-hop tests

**Interfaces:**

- Consumes: `StreamWriterPlan.analyze(tokens, registry)`.
- Produces: a test that requires six helper forwarding edges to be accepted while the
  existing seventh-edge boundary remains rejected.

- [ ] **Step 1: Add the six-hop source test before changing production code.**

Use the exact chain `produce -> outer_stream -> extra_stream -> entry_stream ->
forward_stream -> middle_stream -> inner_stream -> finish_stream`, with every call
passing `(writer, count, value)` and `finish_stream` containing the existing bounded
write/close/sink sequence. Assert `ProducerMode.countdown`, helper name
`outer_stream`, and names `count`/`value`.

- [ ] **Step 2: Run only the new test and observe the expected failure.**

```bash
(cd src && zig test build/codegen_component_async_plan.zig --test-filter 'accepts a sixth parameterized producer forwarding hop')
```

Expected: FAIL with `UnsupportedP3StreamWriterComponent`; this confirms the test reaches
the current hop boundary rather than failing because of malformed syntax.

- [ ] **Step 3: Convert the unit boundary test to seven hops before changing production code.**

Change the existing `rejects a sixth parameterized producer forwarding hop` source to
add one static helper edge and rename the test to
`rejects a seventh parameterized producer forwarding hop`. Run it while the bound is
still `5`; it must continue to fail with `UnsupportedP3StreamWriterComponent`.

### Task 3: Widen only the bounded analyzer constant

**Files:**

- Modify: `src/build/codegen_component_async_plan.zig:1559-1560`

**Interfaces:**

- Consumes: the failing six-hop analyzer test from Task 2.
- Produces: admission for six, rejection for seven, with no new parser route.

- [ ] **Step 1: Change the single hop bound.**

Change:

```zig
const max_parameterized_forwarding_hops: usize = 5;
```

to:

```zig
const max_parameterized_forwarding_hops: usize = 6;
```

Do not alter `parse_parameterized_forwarding_helper` or introduce unbounded recursion.

- [ ] **Step 2: Run the focused analyzer tests.**

```bash
(cd src && zig test build/codegen_component_async_plan.zig --test-filter 'parameterized producer forwarding hop')
```

Expected: two-, three-, four-, five-, and six-hop acceptance tests pass; the seventh-hop
unit test fails with `UnsupportedP3StreamWriterComponent`.

### Task 4: Establish the positive Do/Component gate and seventh-hop negative

**Files:**

- Create: `examples/p3-runtime/stream-probe-guest-producer-parameterized-six-hop.do`
- Create: `examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_six_hop.sh`
- Create: `examples/p3-runtime/wit/stream-probe-guest-producer-parameterized-six-hop.wit`
- Modify: `examples/p3-runtime/stream-probe-guest-producer-sixth-forwarding.do` to add one edge and make it seventh-hop negative
- Modify: `examples/p3-runtime/test_do_g6_general_boundary_rejection.sh`

**Interfaces:**

- Consumes: the six-hop analyzer admission and existing five-hop WIT surface.
- Produces: a positive Component artifact and a seventh-hop fail-closed gate.

- [ ] **Step 1: Write the positive six-hop Do fixture.**

Use the exact source surface from the design, including `finish_stream`'s countdown,
`defer close(writer)`, and one `sink_write(writer)` call. Keep `produce(count u64,
value u8) -> Result<nil, ProbeError>` unchanged.

- [ ] **Step 2: Add the matching WIT mirror.**

Keep package, interface, world, async member, and result error cases byte-for-byte
equivalent to the five-hop WIT; the gate must compare generated output with `cmp`.

- [ ] **Step 3: Add the Component assertions.**

The shell gate must assert `[writer-lease-transfer] async-helper`, measured offsets after
the probe, the async `(i64, i32) -> i32` type, one `[async-lift]produce` export, and no
helper exports. It must then run:

```bash
wasm-tools parse "$core_path" -o "$core_wasm"
wasm-tools component embed "$wit_path" "$core_wasm" --world stream-writer-probe -o "$embedded_path"
wasm-tools component new "$embedded_path" -o "$component_path"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component_path"
```

- [ ] **Step 4: Convert the old negative into a seventh-hop fixture.**

Add one static helper edge, retain the same descriptor and typed arguments, and keep the
expected diagnostic `UnsupportedP3AsyncComponent` in
`test_do_g6_general_boundary_rejection.sh`.

### Task 5: Extend the Rust/Wasmtime runtime matrix

**Files:**

- Modify: `examples/p3-runtime/rust-host-runner/src/bin/stream_probe_guest_producer_dynamic.rs`
- Create: `examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_six_hop.sh`

**Interfaces:**

- Consumes: the positive six-hop Component from Task 4.
- Produces: runtime evidence for producer values, pending behavior, errors, cancellation,
  early drop, lease cleanup, and table disposal.

- [ ] **Step 1: Add `ParameterizedSixHop` to `ProducerShape`.**

Update parsing, `is_parameterized`, labels, and the error text without changing the
existing shape names or default countdown behavior.

- [ ] **Step 2: Reuse the existing host callback and consumer accounting.**

Run `count=0/1/3` with `value=90` for pending, ready, and error. Add the cancellation
and early-drop assertions using the existing stream-drop signaling; require one host
callback, one stream drop, expected bytes, and an empty `ResourceTable`.

- [ ] **Step 3: Verify exactly-once cleanup.**

The runner must fail if list/stream cleanup occurs zero times or more than once, or if a
cancelled operation reports a successful external effect. Cancellation may clear internal
state but must not claim rollback.

### Task 6: Run the complete gate matrix and update evidence

**Files:**

- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `CHANGELOG.md`

**Interfaces:**

- Consumes: focused, Component, Rust/Wasmtime, and cleanup outputs from Tasks 1–5.
- Produces: synchronized evidence that distinguishes six-hop promotion from general
  async lowering and full GC migration.

- [ ] **Step 1: Run the positive and negative gates.**

```bash
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_six_hop.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_six_hop.sh
bash examples/p3-runtime/test_do_g6_general_boundary_rejection.sh
```

- [ ] **Step 2: Run compiler and release gates.**

```bash
(cd src && zig test main.zig)
./src/build/test/run_tests.sh
(cd src && zig build -Doptimize=ReleaseSmall)
./src/build/test/run_release_smoke.sh
```

- [ ] **Step 3: Preserve the deliberate inventory result.**

```bash
set +e
bash src/build/test/check_gc_migration_inventory.sh
inventory_status=$?
set -e
test "$inventory_status" -eq 1
```

Expected output still contains `summary complete_rows=15 pending_rows=15`.

- [ ] **Step 4: Update only verified documentation facts.**

Record that sixth-hop forwarding is a private bounded capability, that seventh-hop and
general producer lowering remain blocked, and that no migration row or full GC cutover
was closed.

- [ ] **Step 5: Run final consistency checks.**

```bash
git diff --check
rg -n 'sixth|seventh|parameterized.*forwarding|complete_rows=15 pending_rows=15|full GC' \
  doc/host_abi_blockers.md doc/pending_blocked.md doc/roadmap_status.md doc/start_here.md
```

### Task 7: Handoff without widening scope

**Files:**

- No additional files.

**Interfaces:**

- Consumes: all verified artifacts and documentation from Task 6.
- Produces: a clean handoff state with no unrecorded blocker.

- [ ] **Step 1: Inspect the final diff.**

Confirm that only six-hop fixtures, its runner/gates, the one analyzer bound, and their
design/evidence documents are attributable to this stage; preserve unrelated dirty files.

- [ ] **Step 2: Report residual boundaries.**

Explicitly retain seventh-hop, arbitrary producer, general list/resource, borrowed
payload, D2 general async, and full GC cutover as pending. Do not push unless separately
requested.
