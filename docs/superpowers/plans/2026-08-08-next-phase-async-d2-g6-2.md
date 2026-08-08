# Next Phase: Async Call, D2 Filesystem, and G6.2 Boundary Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Advance the next independently verifiable async/runtime capabilities without widening public ownership syntax or weakening the existing G6.2 and D2 boundaries.

**Architecture:** The recommended first slice extends the existing root-owned local-frame async-call adapter with one scalar guest argument; it does not create an independent guest task and does not require `own<T>`, `borrow<T>`, `ref<T>`, pointers, references, or lifetimes. A separate D2 track probes and, only if the pinned Component/runtime gate is green, promotes `descriptor.get-flags`, a no-resource-payload filesystem method. G6.2 generic producer, borrowed payload, and arbitrary producer work remains a capability review and explicit no-go until a new canonical probe and ownership matrix exist.

**Tech Stack:** Zig 0.16.0, Do lexer/sema/codegen, WIT/Core-WAT, `wasm-tools` 1.255.0 for current Component tooling, pinned legacy `wasm-tools` 1.254.0 for async assembly, Rust/Cargo 1.97.1, Wasmtime 47.0.2, and the existing Bash regression harness.

## Global Constraints

- Keep ordinary public result APIs as `T | E` or `nil | E`; private WIT/Component `Result` rows remain compatibility metadata only.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, lifetime, or rollback syntax.
- Preserve the existing C-min, dynamic-count, batched list producer, `descriptor.get-type`, and `descriptor.sync` behavior and negative diagnostics.
- Keep `--p3-async-component`, `--p3-async-component-v2`, and `--p3-async-call-component` opt-in; unsupported shapes must fail before WAT.
- A pinned-toolchain rejection is a recorded no-go. It must not be bypassed with a compatibility fallback or a widened registry predicate.
- Cancellation releases live Component resources exactly once and never compensates an external effect already issued before cancellation.
- Every positive shape requires: design, pinned WIT/WAT probe, manifest/sema admission, positive and negative source fixtures, Component validation, and Rust/Wasmtime cleanup evidence.
- Do not touch unrelated worktree changes, remove rebuildable artifacts, or push from an implementation subtask. Push is a separate final delivery step.

## Plan Map

| Order | Track | Deliverable | Gate |
| --- | --- | --- | --- |
| 1 | Baseline | Reproducible green starting point and synchronized stop conditions | Full Zig/Do/Wasm/release checks |
| 2 | A: async-call | One `u32` guest argument carried by a root-owned helper frame | Pinned Component plus ready/pending/cancel runtime matrix |
| 3 | B: D2 filesystem | Private `descriptor.get-flags` method slice, if canonical ABI is accepted | ABI, compiler, and local Wasmtime cleanup gates |
| 4 | C: G6.2 boundary | Re-run borrow/producer capability evidence and select the next shape only by a new design | No-go or a separately authorized positive design |
| 5 | Closeout | Status/docs/regression handoff | All selected gates green, or exact no-go recorded |

Track A is the recommended implementation order. Track B may run after Task 1 because it is method-specific and does not depend on public ownership syntax. Track C must not widen codegen merely because A or B passes.

### Task 1: Freeze the baseline and inventory the remaining boundaries

**Files:**
- Verify: `doc/start_here.md`
- Verify: `doc/roadmap_status.md`
- Verify: `doc/pending_blocked.md`
- Verify: `doc/host_abi_blockers.md`
- Modify: the four files above only after fresh command output

**Interfaces:**
- Consumes the pushed `main` commit `8ad3824` and the current pinned-tool versions.
- Produces a dated baseline with no stale claim that private D2 or bounded G6.2 slices are generic.

- [x] **Step 1: Verify checkout and remote identity.**

```bash
git status --short --branch
git rev-parse main origin/main
git log -1 --oneline main
```

Expected: clean worktree, equal `main` and `origin/main`, and commit
`8ad3824 Promote private D2 filesystem async methods`.

- [x] **Step 2: Run the compiler and release baselines.**

```bash
cd src && zig test main.zig
cd ..
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

Expected: `zig test main.zig` is `308/308`, the normal harness is
`pass=1149 fail=0 skip=3`, the Wasm harness is `pass=1151 fail=0 skip=3` with
Wasm smoke `6/6`, and release smoke is green. If any baseline changes, stop
feature work and diagnose the regression first.

Observed on 2026-08-08: all expected counts matched and ReleaseSmall smoke
passed.

- [x] **Step 3: Record the exact remaining stop conditions.**

Keep these rows explicit in the status documents: generic async-call
composition, arbitrary producer expressions, generic list/borrowed/variant
payloads, general filesystem async, external HTTP runtime, root hard-cancel,
and public ownership syntax remain closed.

### Task 2: Probe the next root-owned async-call shape (Track A)

**Files:**
- Create: `docs/superpowers/specs/2026-08-08-async-call-scalar-argument-design.md`
- Create: `examples/p3-runtime/async-call-scalar-argument-probe.wat`
- Create: `examples/p3-runtime/test_async_call_scalar_argument_probe.sh`
- Verify: `examples/p3-runtime/async-call-component.wit`
- Verify: `examples/p3-runtime/assemble_wasmtime_p3_legacy.sh`

**Interfaces:**
- Reuse the registered package `do:generic-async-call-probe@0.1.0`.
- Host import: `work: async func()`.
- Export: `run: async func()`.
- Exact Do source candidate:

```do
work = @host("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
helper(value u32) -> nil {
    pending Future<nil> = work()
    @await(pending)
}
run() -> nil {
    child Future<nil> = @async(helper(7))
    @await(child)
}
start() {}
```

- [x] **Step 1: Freeze the ABI question before compiler changes.**

The Core probe must carry the `u32` helper argument in the root-owned local
frame across the child continuation. It must expose only the root async export,
never a helper `task.return` endpoint, and preserve child-before-parent cleanup.

- [x] **Step 2: Run both pinned assembly checks.**

```bash
WASM_TOOLS_EXPECT_VERSION=1.255.0 \
  bash examples/p3-runtime/test_async_call_scalar_argument_probe.sh
legacy_wasm_tools=/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools \
  WASM_TOOLS="$legacy_wasm_tools" \
  bash examples/p3-runtime/test_async_call_scalar_argument_probe.sh
```

The script must assert the exact version/hash where applicable, parse Core WAT,
assemble the Component, and validate with `cm-async,cm-more-async-builtins`.

- [x] **Step 3: Keep the probe fail-closed.**

Record rejection for a second scalar argument, a non-`u32` argument, helper
payload, two live child futures, nested helper, `Stream`/resource payload, and
legacy `async` declaration. If any of these is accidentally accepted by the
toolchain, stop and investigate the ABI instead of widening the compiler.

- [x] **Step 4: Stop or authorize implementation.**

If the scalar frame probe fails, update the design and blocker ledger with the
exact stderr and do not modify the registry or emitter. Only a green probe
allows Task 3.

### Task 3: Implement the bounded scalar-argument async-call adapter (Track A)

**Files:**
- Modify: `src/build/codegen_component_async_call_plan.zig`
- Modify: `src/build/codegen_component_async_call.zig`
- Modify: `src/build/codegen_component_async.zig`
- Create: `src/build/test/compile_ok/466_async_call_scalar_argument_component.do`
- Create: `src/build/test/compile_ok/466_async_call_scalar_argument_component.expect`
- Create: `src/build/test/compile_err/467_async_call_scalar_argument_payload.do`
- Create: `src/build/test/compile_err/467_async_call_scalar_argument_payload.expect`
- Create: `src/build/test/compile_err/468_async_call_scalar_argument_two_children.do`
- Create: `src/build/test/compile_err/468_async_call_scalar_argument_two_children.expect`
- Create: `src/build/test/compile_err/469_async_call_scalar_argument_nested.do`
- Create: `src/build/test/compile_err/469_async_call_scalar_argument_nested.expect`
- Create: `examples/p3-runtime/async-call-scalar-argument.do`
- Create: `examples/p3-runtime/test_do_async_call_scalar_argument.sh`
- Create: `examples/p3-runtime/test_rust_async_call_scalar_argument.sh`
- Create or modify: `examples/p3-runtime/rust-host-runner/src/bin/async_call_scalar_argument.rs`

**Interfaces:**
- Extend `GuestAsyncCallPlan` with one validated scalar argument slot and its
  constant source value; retain the existing root/helper/host descriptor facts.
- Keep `emit_component_wat` and `emit_component_wit` under the existing
  `--p3-async-call-component` target; do not route this shape through v1/v2.

- [x] **Step 1: Add red analyzer and emitter assertions.**

Run:

```bash
cd src
zig test build/codegen_component_async_call_plan_test.zig
zig test build/codegen_component_async_call_test.zig --test-filter 'scalar argument'
```

The new positive shape must be absent before implementation, while existing
no-argument async-call tests remain green.

- [x] **Step 2: Implement exact argument admission.**

Accept only `helper(value u32) -> nil`, one literal `helper(7)` call, one
`@await`, one registered zero-payload host operation, and no extra body or
module operations. Reject every other argument and payload shape with
`UnsupportedP3AsyncCallComponent` before WAT.

- [x] **Step 3: Add one frame slot and preserve cleanup order.**

Store the scalar argument in the root-owned frame before entering the helper;
resume the helper from the root callback; then release host subtask, child
future/frame, helper argument slot, parent continuation, and root frame in that
order. Emit stable markers for argument storage, parent resume, child drop, and
root terminal cleanup.

- [x] **Step 4: Run the compiler-generated Component gate.**

```bash
bash examples/p3-runtime/test_do_async_call_scalar_argument.sh
bash examples/p3-runtime/test_rust_async_call_scalar_argument.sh \
  /tmp/async-call-scalar-argument.component.wasm
```

Require `ready`, `pending`, and `cancel` to show exactly-once child cleanup,
one root terminal, and an empty `ResourceTable`. Existing no-argument and v1/v2
targets must remain unchanged.

### Task 4: Probe one D2 filesystem method without generic lowering (Track B)

**Files:**
- Create: `docs/superpowers/specs/2026-08-08-d2-filesystem-async-get-flags-design.md`
- Create: `examples/p3-runtime/wit/wasi-filesystem-get-flags.wit`
- Create: `examples/p3-runtime/wasi-filesystem-get-flags.core.wat`
- Create: `examples/p3-runtime/wasi-filesystem-get-flags-cancel.core.wat`
- Create: `examples/p3-runtime/test_d2_wasi_filesystem_get_flags_abi.sh`
- Create or modify: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_get_flags.rs`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_get_flags.sh`
- Verify: `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit`

**Interfaces:**
- Pinned member: `wasi:filesystem/types@0.3.0-rc-2025-09-16` /
  `descriptor.get-flags`.
- Shape: `(descriptor) -> result<descriptor-flags, error-code>`.
- The probe must use the existing opaque descriptor ownership contract and no
  borrowed result payload, list, stream, or resource-valued result.

- [x] **Step 1: Measure canonical WIT/Core ABI.**

Record the upstream WIT hash, core parameter/result words, flags encoding, task
completion layout, descriptor drop import, and result tag/payload offsets. Add
ready, pending, error, and cancellation paths to the hand-authored Component.

- [x] **Step 2: Run the pinned ABI and Rust/Wasmtime probe.**

```bash
WASM_TOOLS_EXPECT_VERSION=1.255.0 \
  bash examples/p3-runtime/test_d2_wasi_filesystem_get_flags_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_get_flags.sh
```

Require exactly-once descriptor cleanup and `table-empty=true` for every
terminal path. A rejected flags encoding, unstable result shape, or runtime
cleanup failure is a no-go; do not add a registry row.

### Task 5: Promote `descriptor.get-flags` only if Task 4 is green

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/sema_imports.zig`
- Create: `src/build/codegen_component_wasi_filesystem_get_flags.zig`
- Modify: `src/build/codegen_component_async.zig`
- Create: `src/build/test/compile_ok/471_wasi_filesystem_get_flags_component.do`
- Create: `src/build/test/compile_ok/471_wasi_filesystem_get_flags_component.expect`
- Create: `src/build/test/compile_err/472_wasi_filesystem_get_flags_unregistered.do`
- Create: `src/build/test/compile_err/472_wasi_filesystem_get_flags_unregistered.expect`
- Create: `src/build/test/compile_err/473_wasi_filesystem_get_flags_wrong_result.do`
- Create: `src/build/test/compile_err/473_wasi_filesystem_get_flags_wrong_result.expect`
- Create: `src/build/test/compile_err/474_wasi_filesystem_get_flags_borrowed_payload.do`
- Create: `src/build/test/compile_err/474_wasi_filesystem_get_flags_borrowed_payload.expect`

**Interfaces:**
- Add one private descriptor with fixed upstream hash, method, result layout,
  and cleanup metadata. Keep `get-type` and `sync` registry entries unchanged.
- Add one isolated emitter/dispatcher branch. Ordinary `do build` and every
  unregistered filesystem method continue to reject before WAT.

- [x] **Step 1: Add manifest/sema red tests.**

Cover hash drift, wrong flags result, wrong descriptor resource, borrowed
payload, unknown locator, and a second await. Run the focused manifest and sema
suites before adding the adapter.

- [x] **Step 2: Implement the exact private adapter.**

Reuse the measured result-area and resource-drop helpers; do not infer flags
layout from a source type. The adapter accepts one descriptor method call and
one completion terminal only.

- [x] **Step 3: Run compiler and runtime gates.**

```bash
bash examples/p3-runtime/test_do_wasi_filesystem_get_flags.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_get_flags.sh
```

Require the same ready/pending/error/cancel cleanup evidence as the hand-written
probe and preserve all existing D2 gates.

Observed: the current and legacy pinned `wasm-tools` ABI probes, compiler
admission, and Rust/Wasmtime gates all pass. The private adapter admits only
`(Dir) -> u8 | FlagsError` for fixture `471`; fixtures `472`-`474` reject
unregistered, wrong-result, and borrowed-payload drift. Every runtime row has
one host call, one descriptor drop, an empty resource table, and exactly-once
future cleanup; cancellation has one pending-future drop and zero completion.

### Task 6: Re-evaluate G6.2 residual capability without widening codegen (Track C)

**Files:**
- Verify: `examples/p3-runtime/test_borrow_capability_matrix.sh`
- Verify: `examples/p3-runtime/test_do_g6_general_boundary_rejection.sh`
- Verify: `examples/p3-runtime/test_do_borrowed_resource_rejection.sh`
- Verify: `doc/design/2026-08-03-g6-2-general-resource-ownership.md`
- Modify: `doc/pending_blocked.md` only with fresh evidence

**Interfaces:**
- Consumes current `wasm-tools 1.255.0` and the existing private producer
  descriptors.
- Produces either an explicit no-go, or a new named positive-design request.

- [x] **Step 1: Re-run the pinned borrow matrix.**

```bash
WASM_TOOLS_EXPECT_VERSION=1.255.0 \
  bash examples/p3-runtime/test_borrow_capability_matrix.sh
```

Keep direct/record/variant/list borrow rows separate from the rejected
`stream<record { ticket: borrow<ticket> }>` and `future<borrow<ticket>>` rows.

- [x] **Step 2: Re-run generic producer rejection.**

```bash
bash examples/p3-runtime/test_do_g6_general_boundary_rejection.sh
bash examples/p3-runtime/test_do_borrowed_resource_rejection.sh
```

Require arbitrary producer expressions, borrowed stream/future payloads,
seventh-level nested resource fields, and public ownership syntax to remain
rejected before WAT.

- [x] **Step 3: Record the decision.**

The default result is **no-go** for generic producer and borrowed payload. A
positive G6.2 continuation may begin only after a new bounded design fixes one
canonical WIT shape, measured layout, ownership matrix, negative fixtures, and
Component/Rust/Wasmtime cleanup gate. Do not infer generic support from the
existing C-min, dynamic, or batched descriptors.

Observed: `test_borrow_capability_matrix.sh` passes on `wasm-tools 1.255.0`;
direct/record/variant/list borrow and owned future/stream rows are accepted,
while borrowed stream/future rows are rejected at embed. The generic producer
and borrowed-resource rejection scripts remain green, so no public ownership
syntax or generic producer lowering is authorized.

### Task 7: Close the phase with status and full verification

**Files:**
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/master_plan.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes all green results or explicit no-go evidence from Tasks 1-6.
- Produces a truthful next handoff; no generic capability claim may be added
  from a private descriptor gate.

- [x] **Step 1: Run focused gates.**

```bash
cd src
zig test build/codegen_component_async_call_plan_test.zig
zig test build/codegen_component_async_call_test.zig
zig test build/p3_async_manifest.zig
zig test build/sema_imports.zig
cd ..
```

- [x] **Step 2: Run the complete acceptance matrix.**

```bash
cd src && zig test main.zig
cd ..
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

- [x] **Step 3: Synchronize documents from observed output.**

Record the exact admitted scalar async-call shape and any `get-flags` shape,
their tool versions and cleanup counters, while retaining explicit pending rows
for arbitrary producer expressions, borrowed/list/variant payloads, general
filesystem async, external HTTP, root hard-cancel, and public ownership syntax.

Observed: `zig test main.zig` is `308/308`; the default harness is
`pass=1149 fail=0 skip=3`; the WASM harness is `pass=1151 fail=0 skip=3`
with `wasm run` `6/6`; ReleaseSmall smoke passed. The async-call scalar
adapter and private `descriptor.get-flags` adapter are closed bounded slices.

## Stop Conditions

- A baseline regression stops all feature work until diagnosed and verified.
- A pinned WIT/Component rejection stops its track before registry/sema/codegen changes.
- Any duplicate release, parent-before-child cleanup, non-empty `ResourceTable`,
  or cancellation path that claims external rollback stops the relevant track.
- A green private descriptor does not authorize public `own<T>`, `borrow<T>`,
  `ref<T>`, generic producer expressions, or unrestricted generated WIT lowering.
