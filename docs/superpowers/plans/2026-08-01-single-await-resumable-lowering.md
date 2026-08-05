# Single Await Resumable Lowering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lower one pinned scalar/unit async clock function through a real frame and resume branch while preserving the ordinary async build guard.

**Architecture:** Reuse `codegen_async_model.AsyncFunctionPlan` as the frame metadata source, add a narrow body contract for one pinned `Future<nil>` await, and connect it to the existing Core Component task callback path. The implementation emits only scalar `u64` frame slots and uses the existing terminal cleanup helper; unsupported source shapes continue to fail with `UnsupportedP3AsyncComponent`.

**Tech Stack:** Zig compiler, Core Wasm WAT, pinned WIT metadata, `wasm-tools`, Rust/Wasmtime runner, shell regression tests.

## Global Constraints

- The only accepted async descriptor is the pinned `wasi:clocks@0.3.0/monotonic-clock.wait-for` scalar/unit shape.
- The only new source shape has one `Future<nil>` and one `await`.
- `--p3-async-component` is required for async lowering; ordinary `do build` keeps `AsyncLoweringUnavailable`.
- Cancellation observes the pinned Component terminal state before waitable/frame cleanup and never rolls back external effects.
- No public `own<T>`, `borrow<T>`, `ref<T>`, resource, list, Result payload, or Stream syntax is added by this plan.
- Every code change follows red -> focused green -> full regression.

---

### Task 1: Lock The New Source Contract With A Red Fixture

**Files:**
- Create: `examples/p3-runtime/single-await-post-compute-component.do`
- Create: `examples/p3-runtime/test_do_single_await_post_compute_lowering.sh`
- Modify: `src/build/test/run_tests.sh` only if a compiler-facing fixture is needed; the P3 script is the primary red/green gate.

**Interfaces:**
- Consumes: the existing pinned clock descriptor and `--p3-async-component` CLI target.
- Produces: a source shape that requires a live `u64` local after suspension and currently fails with `UnsupportedP3AsyncComponent`.

- [x] **Step 1: Add the failing source fixture.**

```do
wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)

async run(input u64) -> nil {
    deadline u64 = @add(input, 1)
    pending Future<nil> = wait_for(deadline)
    await(pending)
    after u64 = @add(deadline, 1)
    _ = after
    return
}

start() {}
```

- [x] **Step 2: Add the focused shell assertion.**

The script must invoke:

```bash
do build --p3-async-component --p3-wit-output "$wit" \
  "$repo_root/examples/p3-runtime/single-await-post-compute-component.do" \
  -o "$wat"
```

Before implementation, the command must fail with the existing
`UnsupportedP3AsyncComponent` diagnostic. The script must not accept a
metadata-only output or a synchronous Core artifact.

- [x] **Step 3: Run the red test and inspect the failure.**

Run:

```bash
bash examples/p3-runtime/test_do_single_await_post_compute_lowering.sh
```

Expected: non-zero exit caused by the unsupported source shape, not a parser,
missing descriptor, or malformed fixture error.

### Task 2: Add The Narrow Resumable Body Plan

**Files:**
- Modify: `src/build/codegen_component_async_plan.zig`
- Modify: `src/build/codegen_p3_wait_for.zig`
- Modify: `src/build/codegen_async_model.zig` only if the existing frame plan lacks a required source position or slot lookup.
- Test: `src/build/codegen_async_model.zig` and `src/build/codegen_p3_wait_for.zig` unit tests.

**Interfaces:**
- Consumes: `ComponentAsyncFunctionPlan`, `AsyncFunctionPlan.frame`, and `FrameLayout.slots`.
- Produces: a validated one-await body plan containing the host descriptor, argument expression, await binding, post-await scalar assignment, and terminal return.

- [x] **Step 1: Add a unit red test for the body plan.**

The test tokenizes the Task 1 fixture and asserts the new plan constructor
returns `UnsupportedP3WaitForComponent` before implementation. It also asserts
that the existing simple `wait-for-component.do` shape remains accepted by its
current plan.

- [x] **Step 2: Implement guarded parsing of the exact body shape.**

Accept only the following sequence after the host binding:

```text
typed u64 local = @add(parameter, literal)
Future<nil> binding = host(local)
await(binding)
typed u64 local = @add(local, literal)
discard(local)
return
```

Reject a second await, branches, loops, Result/Stream expressions, unsupported
storage, or any operation not represented by the existing scalar expression
emitter. Return the existing unsupported error rather than silently falling
back to the old template.

- [x] **Step 3: Run the focused unit test.**

Run:

```bash
cd src && zig test build/codegen_component_async_plan.zig
cd .. && zig test src/build/codegen_p3_wait_for.zig
```

Expected: the new plan test passes and all existing P3 plan tests remain green.

### Task 3: Emit A Real Frame Resume And Cleanup Path

**Files:**
- Modify: `src/build/codegen_p3_wait_for.zig`
- Modify: `src/build/codegen_emit_async.zig` only for reusable WAT fragments that are not already present.
- Modify: `src/build/codegen_gc_async_frame.zig` only if the existing frame table emitter cannot expose the required live slot.
- Test: `src/build/codegen_p3_wait_for.zig`

**Interfaces:**
- Consumes: the Task 2 one-await body plan and existing `AsyncFunctionPlan` frame/layout.
- Produces: Core WAT with reachable entry/resume dispatch, persisted `deadline` slot, post-await `i64.add`, and one terminal cleanup path.

- [x] **Step 1: Add WAT assertions before emission changes.**

Extend the focused test to require these markers in the generated WAT:

```text
(type $async-frame (struct
(table $async-frames
br $async_resume_1
[async-slot] deadline
[async-terminal] returned
```

The red run must fail because the current fixed template does not emit the
post-await body and reachable slot use for this fixture.

- [x] **Step 2: Emit frame allocation and slot stores.**

Use the existing frame table/allocator and `FrameLayout` offsets. Store the
computed `deadline` before invoking the pinned host import; do not add a second
allocator or a global completion state. The frame state is the only source for
the resumed `deadline` value.

- [x] **Step 3: Emit entry/resume dispatch and post-await body.**

Set the frame state to the resume state before returning pending. In the task
callback export, dispatch state `1` to the resume label, load `deadline` from
the frame, emit `i64.const 1` plus `i64.add`, discard the result using the
existing scalar discard path, then enter terminal cleanup.

- [x] **Step 4: Route every terminal path through shared cleanup.**

Use `codegen_emit_async.emit_async_terminal_cleanup` for normal return,
failure, and cancellation. Confirm the waitable/subtask is terminal before
drop, run active defers in reverse order, free the frame, and call the typed
`task-return`. Do not emit a Do-level cancellation event or rollback branch.

### Task 4: Assemble And Execute The Narrow Slice

**Files:**
- Modify: `examples/p3-runtime/test_do_single_await_post_compute_lowering.sh`
- Create or modify: `examples/p3-runtime/test_rust_single_await_post_compute.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/main.rs` only if a separate runner entry is needed; reuse the existing clock adapter when possible.
- Modify: `doc/host_abi_blockers.md`
- Modify: `docs/superpowers/plans/2026-08-01-single-await-resumable-lowering.md`

**Interfaces:**
- Consumes: generated Core WAT and WIT from Task 3.
- Produces: pinned Component assembly and runtime evidence for pending and immediate completion.

- [x] **Step 1: Add assembly assertions.**

Run `wasm-tools component embed`, `component new`, and `validate`. Assert the
generated WIT remains the pinned clock world and the Core module contains no
`(component` block.

- [x] **Step 2: Add pending and immediate Rust/Wasmtime assertions.**

Reuse the existing adapter's two modes. Require one pending poll, one external
wake, one completion in pending mode, and zero pending polls/wakes in immediate
mode. Require the clock argument to equal `input + 1` and the component to
complete without a trap.

- [x] **Step 3: Run the focused P3 matrix.**

```bash
bash examples/p3-runtime/test_do_single_await_post_compute_lowering.sh
bash examples/p3-runtime/test_rust_single_await_post_compute.sh
bash examples/p3-runtime/test_do_wait_for_lowering.sh
```

- [x] **Step 4: Run the full regression and record boundaries.**

```bash
./src/build/test/run_tests.sh
git diff --check
```

Record the exact pass/fail/skip result and state that arbitrary async bodies,
Result payloads, Stream operations, resources, and ordinary `do build` remain
outside this slice.

## Self-Review

- The fixture exercises a local value that is live across the await and a
  scalar statement after resume; it cannot pass through the old return-only
  template unchanged.
- The plan introduces no public syntax or new ABI ownership model.
- All implementation tasks have a red test before production code and a
  focused plus full verification step.
