# General Async-Call Lowering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admit one real user-function `@async(call)` edge in an opt-in Component target with a compiler-managed local helper continuation under the root task, while keeping v1 and Generic ABI v2 unchanged.

**Architecture:** Build an internal call graph and frame plan for an ordinary helper invoked from a root function. The first admitted shape has no parameters, a `nil` result, one registered async host call inside the helper, and one parent await. A separate `--p3-async-call-component` dispatcher emits only this shape and fails closed for every broader form. The pinned ABI rejects an independent helper `task.return`, so the implementation uses a root-owned local helper frame/state and the root callback/task.return path.

**Current execution status:** The original Tasks 1-5 and the 2026-08-08
colorless-inline follow-up are implemented. The opt-in target accepts both the
existing child-only unit root and exactly one leading inline `helper()` before
the explicit `@async(helper())` child. Component/Rust/Wasmtime gates cover
ready, pending, `cancel-inline`, and `cancel-child`; broader
parameter/resource/Stream/list/legacy forms remain explicit residual
boundaries rather than admitted shapes.

The source remains non-contagious: `helper()` and `run()` are ordinary
functions, a normal call is inline, and only `@async(call)` creates a
user-function Future. The inline phase is root-owned and does not synthesize a
helper export or a second `task.return` endpoint.

**Tech Stack:** Zig `0.16.0`, Do compiler, WIT/Core WAT, legacy `wasm-tools 1.254.0`, Rust `1.97.1`, Wasmtime `47.0.2`, existing Cargo/Rust host runner.

## Global Constraints

- Preserve `--p3-async-component` v1 behavior byte-for-byte and keep `--p3-async-component-v2` limited to its two measured private shapes.
- Add no public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Admit only the exact no-parameter, `nil` helper shape defined in the design spec; reject payload, resource, Stream, list, branch, loop, recursion, and multiple-child forms before WAT.
- Do not admit arbitrary producer expressions, filesystem async methods, external HTTP, or D2 host I/O.
- Use `wasm-tools 1.254.0 (bb58fdf91 2026-07-20)` for legacy assembly and Wasmtime `47.0.2`; never substitute 1.255.0 when validating this target.
- Cancellation releases guest/Component child state exactly once and never compensates an already-issued host effect.
- Preserve unrelated dirty worktree changes; do not stage, commit, reset, clean, or push.

---

### Task 1: Probe the Component ABI before compiler changes

**Files:**
- Create: `examples/p3-runtime/async-call-component-probe.wat`
- Create: `examples/p3-runtime/async-call-component-local-frame-probe.wat`
- Create: `examples/p3-runtime/test_async_call_component_probe.sh`
- Verify: `examples/p3-runtime/generic-async-runtime.wit`
- Verify: `examples/p3-runtime/assemble_wasmtime_p3_legacy.sh`

**Interfaces:**
- Consumes: the existing `do:generic-async-runtime-probe@0.1.0` `probe` world and the legacy async callback assembler.
- Produces: a pinned answer to whether one exported async root can contain an internal helper continuation and preserve root-owned cleanup.

- [x] **Step 1: Write the hand-written Core module and explicit markers.**

The module must contain these ABI boundaries, with the exact import names taken
from the existing templates:

```wat
(import "do:generic-async-runtime-probe/host@0.1.0" "[async-lower]work"
  (func $host-work (result i32)))
(import "[export]do:generic-async-runtime-probe/probe@0.1.0" "[task-return]run"
  (func $task-return))
(import "$root" "[subtask-cancel]" (func $subtask-cancel (param i32) (result i32)))
(import "$root" "[subtask-drop]" (func $subtask-drop (param i32)))
```

The probes must expose an async-lifted `run`, a separate `$helper` state
function, an explicit parent continuation state, and comments/markers
`[guest-async-child]`, `[guest-async-parent-resume]`,
`[guest-async-child-drop]`. It must not add a WIT export for `$helper`.
The independent-task probe retains the synthetic `[task-return]helper` import
and captures its rejection; the local-frame probe omits that import and uses
only root `[task-return]run`.

- [x] **Step 2: Run the pinned assembly probe.**

Run:

```bash
legacy_wasm_tools=/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools
WASM_TOOLS="$legacy_wasm_tools" bash examples/p3-runtime/test_async_call_component_probe.sh
```

The script must assert the exact version and SHA-256, parse both Core modules,
embed `generic-async-runtime.wit` with `--world probe --dummy-names legacy
--async-callback`, expect the independent-task rejection with its complete
diagnostic, and create/validate the local-frame Component with
`--skip-validation` and `cm-async,cm-more-async-builtins`.

- [x] **Step 3: Run the probe's runtime smoke only if assembly is green.**

The ABI-only probe establishes assembly and validation for the local-frame
route. Runtime ready/pending/cancel observations are deferred to Task 4, where
the compiler-emitted frame and cleanup code exist; no runtime claim is made by
this hand-written gate.

Use a temporary Rust host or the existing `generic_async_runtime` runner only
after the local-frame emitter exists. Require one helper terminal/drop and one
root terminal per run. The absence of an independent guest-task primitive is a
recorded ABI boundary, not permission to expose `$helper` as a WIT export or
route through the v1 dispatcher.

- [x] **Step 4: Record the capability result.**

Update `docs/superpowers/specs/2026-08-07-general-async-call-lowering-design.md`
with the exact command, tool version, diagnostic, and local-frame assembly
observations. Keep independent guest child-task creation explicitly deferred.

---

### Task 2: Add the bounded call-graph analyzer with red tests

**Files:**
- Create: `src/build/codegen_component_async_call_plan.zig`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/diag.zig`
- Test: `src/build/test/check/441_async_call_component.do`
- Create: `src/build/test/compile_err/441_async_call_component_payload.do`
- Create: `src/build/test/compile_err/441_async_call_component_payload.expect`
- Create: `src/build/test/compile_err/442_async_call_component_two_children.do`
- Create: `src/build/test/compile_err/442_async_call_component_two_children.expect`
- Create: `src/build/test/compile_err/443_async_call_component_nested_helper.do`
- Create: `src/build/test/compile_err/443_async_call_component_nested_helper.expect`

**Interfaces:**
- Consumes: the Task 1 ABI result, `parser.Program`, `lexer.Token`, existing generated async plan records, and the pinned generic host descriptor.
- Produces: `GuestAsyncCallPlan` with `root_name`, `helper_name`, `host_locator`, `host_member`, `child_state`, `parent_resume_state`, and exact terminal actions.

- [x] **Step 1: Write the positive and negative source fixtures.**

The positive fixture must be exactly:

```do
work = @host("do:generic-async-runtime-probe/host@0.1.0", "work", () -> nil)
helper() -> nil {
    pending Future<nil> = work()
    @await(pending)
}
run() -> nil {
    child Future<nil> = @async(helper())
    @await(child)
}
start() {}
```

The payload fixture changes the helper result to `i32`; the two-child fixture
creates two live `@async(helper())` futures before awaiting either; the nested
fixture adds `inner() -> nil` and calls it from `helper`. Each must fail before
WAT with `UnsupportedP3AsyncCallComponent` (or its stable diagnostic wrapper).

- [x] **Step 2: Run the red analyzer tests.**

Run:

```bash
cd src
zig test build/codegen_component_async_call_plan_test.zig
zig test build/codegen_component_async_call_test.zig --test-filter "async call component"
```

The initial red phase was completed before implementation; the resulting
fixtures and focused unit tests now cover the positive plan and the three
fail-closed negative shapes without routing through v1/v2.

- [x] **Step 3: Implement exact admission and fail-closed rejection.**

The analyzer must locate ordinary declarations by name, verify the helper
signature and body token sequence, verify the root `@async`/`@await` sequence,
and reject all extra tokens. It must never infer a helper's async behavior from
its name or from an unregistered host descriptor. A missing or mismatched
shape returns `error.UnsupportedP3AsyncCallComponent`.

- [x] **Step 4: Verify analyzer green.**

Run the two focused test files again and require the positive plan fields to
match `helper`, `run`, `work`, `child_state=host-pending`, and
`parent_resume_state=child-complete`.

---

### Task 3: Add the opt-in dispatcher and guest frame emitter

**Files:**
- Create: `src/build/codegen_component_async_call.zig`
- Modify: `src/build/cli.zig`
- Modify: `src/build/run.zig`
- Modify: `src/build/codegen_model.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/main.zig`
- Modify: `src/build/codegen_component_async.zig`
- Test: CLI, pipeline, frame-emitter, and dispatcher unit tests

**Interfaces:**
- Consumes: `GuestAsyncCallPlan` and the Task 1 ABI result.
- Produces: `emit_component_wat_async_call(...) ![]u8` and
  `EmitOptions.p3_async_call_component: bool`, selected only by
  `--p3-async-call-component`.

- [x] **Step 1: Add CLI red tests and target plumbing.**

Add parser tests for accepting `--p3-async-call-component --p3-wit-output
out.wit` and rejecting combinations with `--p3-async-component`,
`--p3-async-component-v2`, `--component-core`, or `--host-export`. Run the
focused parser test before implementation and confirm the new flag is unknown.

- [x] **Step 2: Implement the separate dispatcher.**

Route the new flag to `emit_component_wat_async_call` before v1/v2 dispatch.
The function may call only `codegen_component_async_call_plan` and the new
emitter. It must not call `emit_component_wat` as a fallback and must map any
plan/emitter mismatch to `UnsupportedP3AsyncCallComponent`.

- [x] **Step 3: Emit the parent/child state machine.**

Emit one child frame, one parent continuation state, the existing registered
`[async-lower]work` import, child terminal/drop helpers, and root
`[task-return]run`. The child helper must not be exported in WIT. The cleanup
epilogue must be ordered:

```text
host subtask -> child future/frame -> parent continuation slot -> root frame
```

Emit stable markers `[guest-async-child]`, `[guest-async-parent-resume]`,
`[guest-async-child-drop]`, and `[guest-async-root-terminal]` for focused WAT
assertions.

- [x] **Step 4: Verify target isolation.**

Run CLI, pipeline, emitter, and dispatcher tests. Compile the positive fixture
with the new flag and verify that the same fixture under v1 still follows its
old target/diagnostic path and that v2 still rejects it before WAT.

---

### Task 4: Add Component/Rust/Wasmtime runtime gates

**Files:**
- Create: `examples/p3-runtime/async-call-component.wit`
- Create: `examples/p3-runtime/async-call-component.do`
- Create: `examples/p3-runtime/test_do_async_call_component.sh`
- Create: `examples/p3-runtime/test_rust_async_call_component.sh`
- Create or modify: `examples/p3-runtime/rust-host-runner/src/bin/async_call_component.rs`

**Interfaces:**
- Consumes: the Task 3 WAT/WIT emitter and the Task 1 pinned assembly contract.
- Produces: a real `ready`/`pending`/`cancel` cleanup matrix with one child
  continuation and an empty resource table after every terminal path.

- [x] **Step 1: Add the positive source/WIT snapshot.**

Use package `do:generic-async-call-probe@0.1.0`, world `probe`, host `work:
async func()`, and export `run: async func()`. The generated sidecar must not
contain a helper export or public ownership syntax.

- [x] **Step 2: Add the Do lowering gate.**

The shell gate must build with `--p3-async-call-component`, compare the WIT
snapshot, parse/embed/create/validate with pinned `wasm-tools 1.254.0`, and
require all four guest-task markers. It must also compile the same source with
v1 and assert that v1 does not emit the new markers.

- [x] **Step 3: Add the Rust host modes.**

The runner must drive `ready`, `pending`, and `cancel` through Wasmtime 47.0.2.
It must report exactly one child completion/drop in ready and pending, and one
child cancellation/drop plus an empty resource table in cancel. Any duplicate
drop, parent-before-child cleanup, or completed external effect rollback claim
fails the gate.

- [x] **Step 4: Run the complete positive matrix.**

Run:

```bash
legacy_wasm_tools=/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools
WASM_TOOLS="$legacy_wasm_tools" bash examples/p3-runtime/test_do_async_call_component.sh
# Build/assemble the component from the positive fixture, then pass its path:
bash examples/p3-runtime/test_rust_async_call_component.sh /tmp/async-call.component.wasm
```

---

### Task 5: Close the boundary and regression gates

**Files:**
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/master_plan.md`
- Modify: `doc/start_here.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-08-07-general-async-call-lowering-design.md`

**Interfaces:**
- Consumes: all prior probe, analyzer, codegen, and runtime evidence.
- Produces: truthful status for the one admitted async-call shape and explicit
  residual boundaries.

- [x] **Step 1: Add negative regression coverage.**

Run the three compile-error fixtures from Task 2 through the normal harness and
the dedicated opt-in target. Require `UnsupportedP3AsyncCallComponent` and no
WAT output for payload, two-child, and nested-helper forms. Parameter,
resource, Stream, list, and legacy-declaration forms remain covered by the
existing `AsyncLoweringUnavailable`/capability-boundary fixtures and are not
promoted by this bounded target.

- [x] **Step 2: Run focused and full verification.**

Run:

```bash
cd src
zig test build/codegen_component_async_call_plan_test.zig
zig test build/codegen_component_async_call_test.zig
zig test build/codegen_component_async.zig
zig test main.zig
cd ..
NODE_BIN="$(command -v bun)" ./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 NODE_BIN="$(command -v bun)" ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

- [x] **Step 3: Update status without overclaiming.**

Record the exact admitted shape, tool versions, three runtime modes, and
negative diagnostics. Keep generic async-call composition, arbitrary producer
expressions, payload/Stream/resource futures, public ownership syntax,
filesystem async, and D2 host I/O pending.

## Stop Conditions

- If Task 1 cannot assemble the internal continuation, stop before Task 2 and
  record the exact ABI diagnostic in the design spec and blocker ledger.
- If any runtime path shows parent-before-child cleanup or duplicate release,
  stop codegen expansion and repair the state machine before widening shape.
- If the full regression fails for an unrelated dirty-worktree change, record
  the command and preserve the change; do not reset or hide it.
