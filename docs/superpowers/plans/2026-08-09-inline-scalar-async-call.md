# Inline Scalar Async-Call Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the opt-in `--p3-async-call-component` target to admit one leading inline `helper(u32)` call followed by one explicit `@async(helper(u32))` child, while preserving the existing unit and child-only scalar slices.

**Architecture:** Keep ordinary Do functions colorless and keep the helper local to the root-owned continuation. Extend `GuestAsyncCallPlan` with an inline scalar literal, reuse the existing 20-byte frame slot at offset `12`, and lower inline and child host futures through phases `1` and `2` before one terminal root completion. Do not add a helper WIT export, a new WIT descriptor, or public ownership syntax.

**Tech Stack:** Zig 0.16.0, Do compiler, Core WAT, Component Model async builtins, pinned `wasm-tools` 1.254.0 legacy assembly, pinned `wasm-tools` 1.255.0 parsing where already used, Rust 1.97.1, Wasmtime 47.0.2, existing Cargo/Rust host runner.

## Global Constraints

- The accepted source shape is `helper(value u32) -> nil`, a leading `helper(7)`, one `child Future<nil> = @async(helper(7))`, and one `@await(child)` in a colorless `run() -> nil`.
- `GuestAsyncCallPlan.argument_value` remains the child literal; add `inline_argument_value: ?u32` for the leading inline literal.
- The root-owned frame is 20 bytes: waitable set at `0`, current host future at `4`, phase at `8`, current `u32` argument at `12`.
- The inline and child calls execute sequentially and reuse the one argument slot; no two helper calls are live simultaneously.
- The inline phase must not emit `[task-return]helper`, `[async-lift]helper`, or a helper WIT export.
- `examples/p3-runtime/async-call-component.wit` remains unchanged: `host.work` and `probe.run` are still `async func()` with no WIT argument.
- Preserve `--p3-async-component`, `--p3-async-component-v2`, the unit inline slice, and the child-only scalar slice.
- Rejected forms fail before WAT emission with `UnsupportedP3AsyncCallComponent` and do not leave a partial output file.
- Do not add `own<T>`, `borrow<T>`, `ref<T>`, pointers, references, or lifetime syntax.
- Cancellation drops the active future/subtask, waitable set, and frame exactly once; it never rolls back an already-issued host effect.
- Every task ends with focused verification and its own concise commit.

---

### Task 1: Add the inline-scalar contract and red tests

**Files:**
- Create: `examples/p3-runtime/async-call-inline-scalar-argument.do`
- Create: `src/build/test/check/477_async_call_inline_scalar_argument.do`
- Create: `src/build/test/compile_ok/477_async_call_inline_scalar_argument_component.do`
- Create: `src/build/test/compile_ok/477_async_call_inline_scalar_argument_component.expect`
- Create: `src/build/test/compile_err/478_async_call_inline_scalar_dynamic.do`
- Create: `src/build/test/compile_err/478_async_call_inline_scalar_dynamic.expect`
- Create: `src/build/test/compile_err/479_async_call_inline_scalar_two_params.do`
- Create: `src/build/test/compile_err/479_async_call_inline_scalar_two_params.expect`
- Create: `src/build/test/compile_err/480_async_call_inline_scalar_two_inline_calls.do`
- Create: `src/build/test/compile_err/480_async_call_inline_scalar_two_inline_calls.expect`
- Create: `src/build/test/compile_err/481_async_call_inline_scalar_payload.do`
- Create: `src/build/test/compile_err/481_async_call_inline_scalar_payload.expect`
- Modify: `src/build/codegen_component_async_call_plan_test.zig`
- Modify: `src/build/codegen_component_async_call_test.zig`

**Interfaces:**
- Consumes: the existing `466_async_call_scalar_argument_component.do` child-only fixture and the accepted unit inline fixture.
- Produces: a positive inline-scalar source contract and compile/check fixtures that fail closed for dynamic arguments, multiple parameters, duplicate inline calls, and payload returns.

- [ ] **Step 1: Create the positive source and check fixture.**

Use this exact source in both the example and positive compile fixture:

```do
work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
helper(value u32) -> nil {
    pending Future<nil> = work()
    @await(pending)
}
run() -> nil {
    helper(7)
    child Future<nil> = @async(helper(7))
    @await(child)
}
start() {}
```

The check fixture must pass `./bin/do check` without an `async` modifier on `helper` or `run`.

- [ ] **Step 2: Add the positive compile expectation.**

`477_async_call_inline_scalar_argument_component.expect` must require:

```text
# build-arg: --p3-async-call-component
[guest-inline-helper]
[guest-inline-arg-store]
[guest-inline-arg-load]
[guest-inline-resume]
[guest-async-child]
[guest-async-arg-store]
[guest-async-arg-load]
[guest-async-child-drop]
[guest-async-root-terminal]
```

- [ ] **Step 3: Add the dynamic-argument rejection fixture.**

Use a valid local value so semantic analysis reaches the component-plan guard:

```do
work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
helper(value u32) -> nil {
    pending Future<nil> = work()
    @await(pending)
}
run() -> nil {
    selected u32 = 7
    helper(selected)
    child Future<nil> = @async(helper(selected))
    @await(child)
}
start() {}
```

Its `.expect` file must contain `# build-arg: --p3-async-call-component` and `UnsupportedP3AsyncCallComponent`.

- [ ] **Step 4: Add the remaining negative fixtures.**

`479` changes the helper signature to `helper(first u32, second u32) -> nil` and both calls to `helper(7, 8)`. `480` inserts a second leading `helper(7)` statement before the child declaration. `481` changes the helper result to `i32`, keeps the inline and child calls, and returns `1` after the await. Each expectation contains the opt-in build argument and `UnsupportedP3AsyncCallComponent`.

- [ ] **Step 5: Add red unit assertions.**

Add a plan test that tokenizes the new positive fixture, expects `inline_helper_call == true`, `inline_argument_value == 7`, and `argument_value == 7`. Add emitter assertions for the four new inline markers and two `call $host-work` sites. Before implementation, the new plan test must fail with `UnsupportedP3AsyncCallComponent` while the existing child-only scalar test remains accepted.

- [ ] **Step 6: Run the red checkpoint.**

Run:

```bash
cd src && zig test build/codegen_component_async_call_plan_test.zig
zig test build/codegen_component_async_call_test.zig
cd ..
./bin/do check src/build/test/check/477_async_call_inline_scalar_argument.do
./bin/do build examples/p3-runtime/async-call-inline-scalar-argument.do \
  --p3-async-call-component -o /tmp/inline-scalar-red.wat
```

Expected: the check fixture passes, the new positive component build fails before WAT with `UnsupportedP3AsyncCallComponent`, and the focused unit tests expose the missing inline-scalar implementation.

- [ ] **Step 7: Commit the red tests.**

```bash
git add examples/p3-runtime/async-call-inline-scalar-argument.do \
  src/build/test/check/477_async_call_inline_scalar_argument.do \
  src/build/test/compile_ok/477_async_call_inline_scalar_argument_component.do \
  src/build/test/compile_ok/477_async_call_inline_scalar_argument_component.expect \
  src/build/test/compile_err/478_async_call_inline_scalar_dynamic.do \
  src/build/test/compile_err/478_async_call_inline_scalar_dynamic.expect \
  src/build/test/compile_err/479_async_call_inline_scalar_two_params.do \
  src/build/test/compile_err/479_async_call_inline_scalar_two_params.expect \
  src/build/test/compile_err/480_async_call_inline_scalar_two_inline_calls.do \
  src/build/test/compile_err/480_async_call_inline_scalar_two_inline_calls.expect \
  src/build/test/compile_err/481_async_call_inline_scalar_payload.do \
  src/build/test/compile_err/481_async_call_inline_scalar_payload.expect \
  src/build/codegen_component_async_call_plan_test.zig \
  src/build/codegen_component_async_call_test.zig
git commit -m "test: define inline scalar async-call shape"
```

### Task 2: Extend the exact async-call plan

**Files:**
- Modify: `src/build/codegen_component_async_call_plan.zig`
- Modify: `src/build/codegen_component_async_call_plan_test.zig`

**Interfaces:**
- Consumes: lexer tokens and the registered `do:generic-async-call-probe/host@0.1.0` descriptor.
- Produces: `GuestAsyncCallPlan.inline_argument_value: ?u32`, with `null` for existing unit and child-only scalar shapes and `7` for the new inline-scalar fixture.

- [ ] **Step 1: Add the independent inline value field.**

Add `inline_argument_value: ?u32` beside `argument_value`, free no additional memory in `deinit`, and initialize it on every successful return. Existing unit and child-only scalar fixtures must continue to set it to `null`.

- [ ] **Step 2: Add an exact scalar-inline root matcher.**

Keep `root_body_is_exact` for the unit child-only shape and `root_body_with_inline` for the unit inline shape. Add a separate matcher whose token sequence is:

```text
helper ( NUMBER )
child Future < nil > = @ async ( helper ( NUMBER ) )
@ await ( child )
```

Require both `NUMBER` tokens to parse as `u32`, allow the two literals to be recorded independently, and reject any extra statement or call in `run`.

- [ ] **Step 3: Select the correct root shape without contagion.**

When `helper` has one `u32` parameter, accept only the existing child-only scalar matcher or the new scalar-inline matcher. When `helper` is unit, retain the existing unit matchers. Keep the existing checks for one host binding, one `@async`, two `@await`, no `@cancel`, one helper declaration, one root declaration, exact helper body, and unit root result.

- [ ] **Step 4: Preserve the old scalar plan.**

Continue parsing `466_async_call_scalar_argument_component.do` as `argument_name = "value"`, `argument_value = 7`, `inline_helper_call = false`, and `inline_argument_value = null`. Do not broaden `find_scalar_argument` beyond exactly one `u32` parameter.

- [ ] **Step 5: Run the green analyzer tests.**

```bash
cd src && zig test build/codegen_component_async_call_plan_test.zig
```

Expected: the new positive plan exposes both values as `7`, the old scalar plan remains unchanged, and fixtures `478` through `481` fail with `UnsupportedP3AsyncCallComponent`.

- [ ] **Step 6: Commit the plan checkpoint.**

```bash
git add src/build/codegen_component_async_call_plan.zig \
  src/build/codegen_component_async_call_plan_test.zig
git commit -m "feat: admit bounded inline scalar async calls"
```

### Task 3: Lower both scalar phases through one root frame

**Files:**
- Modify: `src/build/codegen_component_async_call.zig`
- Modify: `src/build/codegen_component_async_call_test.zig`

**Interfaces:**
- Consumes: `GuestAsyncCallPlan.argument_value`, `inline_argument_value`, and `inline_helper_call`.
- Produces: 20-byte root-owned WAT with inline argument store/load, child argument store/load, two host call sites, and exactly-once cleanup.

- [ ] **Step 1: Keep the existing templates unchanged for old plans.**

The child-only unit and scalar paths must continue selecting `async_call_component_wat`. Keep their existing argument markers and frame-size behavior. Select the inline template only when `inline_helper_call` is true.

- [ ] **Step 2: Parameterize the inline template for the scalar slot.**

Add these replacements to `emit_component_wat`:

```text
__INLINE_ARGUMENT_STORE__
__INLINE_ARGUMENT_LOAD__
__CHILD_ARGUMENT_STORE__
__CHILD_ARGUMENT_LOAD__
__INLINE_ARGUMENT__
__CHILD_ARGUMENT__
```

For the inline-scalar plan, set frame size to `20`, emit `i32.const 7` into the inline store and child store, and emit a load/drop at each helper phase. For the existing unit inline plan, replace all six tokens with empty text and retain the current 16-byte frame.

- [ ] **Step 3: Add phase-specific markers and transitions.**

In the inline template:

- place `[guest-inline-arg-store]` before the first `call $host-work`;
- place `[guest-inline-arg-load]` in `$inline-resume` before dropping the inline future;
- place `[guest-inline-resume]` at the transition to child phase;
- place `[guest-async-arg-store]` before the child host call and
  `[guest-async-arg-load]` in the child path;
- retain `[guest-inline-helper]`, `[guest-async-child]`,
  `[guest-async-child-drop]`, and `[guest-async-root-terminal]`.

The callback must distinguish phase `1` from phase `2`, drop only the active handle, write the child argument before starting the child phase, and invoke `[task-return]run` only from terminal cleanup.

- [ ] **Step 4: Add emitter assertions.**

Extend `codegen_component_async_call_test.zig` with a scalar-inline source and assert:

```zig
try std.testing.expect(std.mem.count(u8, wat, "call $host-work") == 2);
try std.testing.expect(std.mem.indexOf(u8, wat, "[guest-inline-arg-store]") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "[guest-inline-arg-load]") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 7") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]helper") == null);
try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]helper") == null);
```

Retain the existing unit-inline assertions and verify the old child-only scalar emitter still has no inline markers.

- [ ] **Step 5: Run focused emitter tests.**

```bash
cd src && zig test build/codegen_component_async_call_test.zig
```

Expected: old unit/scalar tests remain green; the scalar-inline WAT contains the 20-byte frame and all phase markers; no helper endpoint appears.

- [ ] **Step 6: Commit the lowering checkpoint.**

```bash
git add src/build/codegen_component_async_call.zig \
  src/build/codegen_component_async_call_test.zig
git commit -m "feat: lower inline scalar async-call phases"
```

### Task 4: Add the pinned Component and Rust/Wasmtime gate

**Files:**
- Create: `examples/p3-runtime/test_do_async_call_inline_scalar_argument.sh`
- Keep unchanged: `examples/p3-runtime/async-call-component.wit`
- Reuse: `examples/p3-runtime/test_rust_async_call_component.sh`
- Reuse: `examples/p3-runtime/rust-host-runner/src/bin/async_call_component.rs`

**Interfaces:**
- Consumes: `examples/p3-runtime/async-call-inline-scalar-argument.do` and the existing host runner.
- Produces: pinned Component assembly plus ready/pending/cancel-inline/cancel-child evidence for the scalar-inline shape.

- [ ] **Step 1: Create the Do/WAT gate.**

The new script must follow `test_do_async_call_scalar_argument.sh`: build the new source with `--p3-async-call-component`, compare the generated WIT with `async-call-component.wit`, assert all inline/child markers and `i32.const 7`, reject `[task-return]helper` and `[async-lift]helper`, parse with pinned `wasm-tools-1.254.0`, and call `assemble_wasmtime_p3_legacy.sh`.

- [ ] **Step 2: Run the Component gate.**

```bash
bash examples/p3-runtime/test_do_async_call_inline_scalar_argument.sh \
  /tmp/async-call-inline-scalar.component.wasm
```

Expected: WIT comparison, Core WAT parsing, Component assembly, and validation all pass; the generated sidecar is byte-identical to the existing WIT snapshot.

- [ ] **Step 3: Run the existing four runtime modes.**

```bash
bash examples/p3-runtime/test_rust_async_call_component.sh \
  /tmp/async-call-inline-scalar.component.wasm
```

Expected output remains the existing generic runner contract: `ready` and `pending` observe two host completions and two drops; `cancel-inline` observes one pending drop; `cancel-child` observes one completed and one pending drop; completed modes report `root-terminal=1 duplicate-drop=0`; every mode reports `table-empty=true`.

- [ ] **Step 4: Keep the old scalar gate green.**

```bash
bash examples/p3-runtime/test_do_async_call_scalar_argument.sh \
  /tmp/async-call-scalar.component.wasm
bash examples/p3-runtime/test_rust_async_call_scalar_argument.sh \
  /tmp/async-call-scalar.component.wasm
```

Expected: the child-only scalar fixture still emits its existing markers and frame slot without inline markers.

- [ ] **Step 5: Commit the runtime gate.**

```bash
git add examples/p3-runtime/test_do_async_call_inline_scalar_argument.sh
git commit -m "test: gate inline scalar async-call component"
```

### Task 5: Synchronize status and close the full regression gate

**Files:**
- Modify: `doc/master_plan.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/start_here.md`
- Modify: `examples/p3-runtime/README.md`

**Interfaces:**
- Consumes: the analyzer, WAT, Component, and Rust/Wasmtime evidence from Tasks 2-4.
- Produces: truthful project status that records only the bounded inline scalar checkpoint as complete and leaves broader async/resource work pending.

- [ ] **Step 1: Record the bounded checkpoint.**

Document the exact source shape, 20-byte frame, pinned assembly/runtime gates, and no-helper-export result. State that `u32` is a probe type rather than a final scalar limitation.

- [ ] **Step 2: Preserve pending boundaries.**

Keep general async-call composition, arbitrary producer expressions, multiple parameters, non-`u32` scalars, payload/list/record/resource/stream futures, public ownership syntax, general filesystem async, external HTTP, and independent guest child tasks listed as pending.

- [ ] **Step 3: Run the full verification matrix.**

```bash
./src/build/test/run_tests.sh
cd src && zig test build/codegen_component_async_call_plan_test.zig
zig test build/codegen_component_async_call_test.zig
cd ..
bash examples/p3-runtime/test_do_async_call_component.sh
bash examples/p3-runtime/test_do_async_call_inline_scalar_argument.sh \
  /tmp/async-call-inline-scalar.component.wasm
bash examples/p3-runtime/test_do_async_call_scalar_argument.sh \
  /tmp/async-call-scalar.component.wasm
git diff --check
git status --short
```

Expected: the repository harness reports `fail=0`, all focused tests and all three async-call Component gates pass, and `git status --short` shows only intentional documentation changes before the final commit.

- [ ] **Step 4: Commit the documentation checkpoint.**

```bash
git add doc/master_plan.md doc/pending_blocked.md doc/start_here.md \
  examples/p3-runtime/README.md
git commit -m "docs: record inline scalar async-call checkpoint"
```

- [ ] **Step 5: Handoff for integration.**

Report the five implementation commits, the exact verification commands and results, the remaining pending boundaries, and the fact that the current `main` branch may still need an explicit `git push origin main` integration step.
