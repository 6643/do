# Inline Colorless Async-Call Lowering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax and are executed with a verification checkpoint after each task.

**Goal:** Extend the opt-in `--p3-async-call-component` target with one synchronous colorless `helper()` call before one explicit `@async(helper())` call, while preserving Do's non-contagious async semantics.

**Architecture:** Keep ordinary Do function signatures synchronous and keep `@host_async_func` as the direct WIT async boundary that produces `Future<T>`. Add an explicit `inline_helper_call` operation to the bounded async-call plan. Lower that operation as a root-owned continuation phase which completes before the existing explicit child phase; do not export or independently schedule the inline helper. The existing no-inline and scalar-argument slices remain unchanged and continue to fail closed for all broader forms.

**Tech Stack:** Zig 0.16.0, Do compiler, Core WAT, Component Model async builtins, pinned `wasm-tools` 1.254.0 legacy assembly, pinned `wasm-tools` 1.255.0 parsing where already used, Rust 1.97.1, Wasmtime 47.0.2, existing Cargo/Rust host runner.

## Global Constraints

- `@host_async_func(locator, member, () -> nil)` binds a WIT `async func`; the Do call directly produces `Future<nil>` and the source declaration does not spell `Future`.
- Ordinary `helper() -> nil` and `run() -> nil` declarations remain colorless; a body containing `@await` does not change its signature or its callers' call type.
- A normal `helper()` call is inline and synchronous at the source level; only `@async(helper())` creates a new `Future<nil>` task handle.
- Admit exactly one leading inline `helper()` call, followed by exactly one `child Future<nil> = @async(helper())` and one `@await(child)` in `run`; reject a second inline call, arguments, payload returns, nested helpers, branches, loops, recursion, multiple children, streams, resources, arbitrary producer expressions, cancellation syntax, and unrelated host descriptors.
- Preserve `--p3-async-component` v1 and `--p3-async-component-v2` behavior and all existing accepted async-call fixtures byte-for-byte when `inline_helper_call` is false.
- Keep the WIT sidecar unchanged: `host.work` remains `async func()` and `probe.run` remains `async func()`; no helper export is added.
- Cancellation releases the active guest/Component state exactly once and never rolls back an already-issued host effect.
- Do not add `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, or lifetime syntax.
- Preserve the user's current uncommitted edit to `examples/p3-runtime/async-call-component.do`; do not reset, clean, or overwrite it.
- Every rejected shape must fail before WAT emission with `UnsupportedP3AsyncCallComponent` and must not create a partial output file.

---

### Task 1: Freeze the source contract and add red tests

**Files:**
- Modify: `examples/p3-runtime/async-call-component.do`
- Modify: `src/build/codegen_component_async_call_plan_test.zig`
- Modify: `src/build/codegen_component_async_call_test.zig`
- Create: `src/build/test/check/455_colorless_async_inline_helper.do`
- Create: `src/build/test/compile_err/475_async_call_component_two_inline_calls.do`
- Create: `src/build/test/compile_err/475_async_call_component_two_inline_calls.expect`
- Create: `src/build/test/compile_err/476_async_call_component_inline_helper_payload.do`
- Create: `src/build/test/compile_err/476_async_call_component_inline_helper_payload.expect`

**Interfaces:**
- Consumes: the existing `GuestAsyncCallPlan`, `async-call-component.do`, and colorless `@await` semantic rules.
- Produces: a positive source fixture whose `run` body starts with `helper()`, plus negative fixtures that prove the bounded target does not silently generalize.

- [x] **Step 1: Record the positive source shape.**

Keep the fixture in this exact order:

```do
work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
helper() -> nil {
    pending Future<nil> = work()
    @await(pending)
}
run() -> nil {
    helper()
    child Future<nil> = @async(helper())
    @await(child)
}
start() {}
```

The check fixture must call `./bin/do check` successfully and must not add an `async` modifier to either user function.

- [x] **Step 2: Add the failing analyzer expectation.**

Add a plan-unit test that tokenizes the positive source, calls `plan.analyze`, and expects `result.inline_helper_call == true`. Before implementation this test must fail with `UnsupportedP3AsyncCallComponent` because `root_body_is_exact` currently accepts only the child declaration and await.

- [x] **Step 3: Add the bounded negative cases.**

`475_async_call_component_two_inline_calls.do` must contain two `helper()` statements before the child declaration and expect `UnsupportedP3AsyncCallComponent`. `476_async_call_component_inline_helper_payload.do` must change `helper() -> nil` to `helper() -> i32` while keeping the inline call and expect the same diagnostic. Add emitter assertions that the existing no-inline source still contains no inline markers and the new source expects the future inline markers introduced in Task 3.

- [x] **Step 4: Run the red tests.**

Run:

```bash
cd src && zig test build/codegen_component_async_call_plan_test.zig
cd ../ && zig test src/build/codegen_component_async_call_test.zig
./bin/do check src/build/test/check/455_colorless_async_inline_helper.do
./bin/do build examples/p3-runtime/async-call-component.do --p3-async-call-component -o /tmp/inline-colorless-red.wat
```

Expected: the ordinary `check` command succeeds, while the opt-in Component build and new positive analyzer test fail before WAT with `UnsupportedP3AsyncCallComponent`.

- [x] **Step 5: Commit the red-test checkpoint.**

```bash
git add examples/p3-runtime/async-call-component.do src/build/codegen_component_async_call_plan_test.zig src/build/codegen_component_async_call_test.zig src/build/test/check/455_colorless_async_inline_helper.do src/build/test/compile_err/475_async_call_component_two_inline_calls.do src/build/test/compile_err/475_async_call_component_two_inline_calls.expect src/build/test/compile_err/476_async_call_component_inline_helper_payload.do src/build/test/compile_err/476_async_call_component_inline_helper_payload.expect
git commit -m "test: define inline colorless async-call shape"
```

### Task 2: Extend the bounded call plan without async contagion

**Files:**
- Modify: `src/build/codegen_component_async_call_plan.zig`
- Modify: `src/build/codegen_component_async_call_plan_test.zig`
- Modify: `src/build/diag.zig` only if a distinct stable plan error is required; otherwise retain `UnsupportedP3AsyncCallComponent`.

**Interfaces:**
- Consumes: lexer tokens and the registered `do:generic-async-call-probe/host@0.1.0` async descriptor.
- Produces: `GuestAsyncCallPlan.inline_helper_call: bool`, with `false` for the existing source shape and `true` for the new leading-inline shape.

- [x] **Step 1: Add the plan field and preserve the old path.**

Add `inline_helper_call: bool` to `GuestAsyncCallPlan`, initialize it in every return path, and leave the existing no-inline and scalar-argument paths returning `false`. Do not infer this field from a function name or from the presence of `Future` alone.

- [x] **Step 2: Recognize exactly one inline call.**

Replace the unit root exact matcher with two explicit token matchers:

```text
root_body_without_inline = child Future<nil> = @async(helper()); @await(child)
root_body_with_inline    = helper(); child Future<nil> = @async(helper()); @await(child)
```

The second matcher must require the first statement to be the zero-argument call `helper()`, require exactly one `@async` pair and two `@await` pairs across the module (one inside `helper`, one in `run`), and reject any other call expression in `run`. Keep `helper_body_is_exact` unchanged: it remains the only admitted helper body and still calls the registered host binding directly.

- [x] **Step 3: Verify red-to-green plan tests.**

Run:

```bash
cd src && zig test build/codegen_component_async_call_plan_test.zig
```

Expected: the positive inline plan reports `inline_helper_call=true`; the old positive plan reports `false`; the two-inline and payload fixtures remain rejected before emission.

- [x] **Step 4: Commit the analyzer checkpoint.**

```bash
git add src/build/codegen_component_async_call_plan.zig src/build/codegen_component_async_call_plan_test.zig src/build/diag.zig
git commit -m "feat: admit bounded inline colorless async calls"
```

### Task 3: Lower the inline phase in the root-owned frame

**Files:**
- Modify: `src/build/codegen_component_async_call.zig`
- Modify: `src/build/codegen_component_async_call_test.zig`
- Modify: `src/build/codegen_component_async.zig` only if dispatcher plumbing must expose the plan field.

**Interfaces:**
- Consumes: `GuestAsyncCallPlan.inline_helper_call` and the existing root-owned frame template.
- Produces: WAT with an inline helper phase followed by the existing explicit child phase, no helper export, and exactly-once cleanup for each active host Future.

- [x] **Step 1: Add explicit frame phases.**

Keep the existing frame layout for `inline_helper_call=false`. For `true`, reserve a phase slot that distinguishes `inline-host-pending`, `child-host-pending`, and `terminal`. Start `run` by invoking the helper's host operation inline; do not create a public subtask or call `[task-return]helper` for this phase.

- [x] **Step 2: Route the callback by phase.**

On completion of the inline host Future, drop that Future exactly once, advance the root-owned phase, and start the explicit `@async(helper())` child operation. On completion of the child, reuse the current child-resume/drop path and then call `[task-return]run` exactly once. A ready result must take the same transitions without entering a duplicate callback path.

- [x] **Step 3: Emit stable markers and negative assertions.**

Add `[guest-inline-helper]` at the inline host call and `[guest-inline-resume]` at its completion transition. Keep `[guest-async-child]`, `[guest-async-child-drop]`, and `[guest-async-root-terminal]`. The generated WAT must not contain `[task-return]helper` or `[async-lift]helper`, and it must contain one host import with two call sites.

- [x] **Step 4: Run emitter tests.**

Run:

```bash
cd src && zig test build/codegen_component_async_call_test.zig
zig test build/codegen_component_async.zig
```

Expected: the old template remains byte-identical for `inline_helper_call=false`; the new template contains both phases and all marker/cleanup assertions.

- [x] **Step 5: Commit the lowering checkpoint.**

```bash
git add src/build/codegen_component_async_call.zig src/build/codegen_component_async_call_test.zig src/build/codegen_component_async.zig
git commit -m "feat: lower inline colorless async-call phase"
```

### Task 4: Close the Component/Rust runtime matrix

**Files:**
- Modify: `examples/p3-runtime/test_do_async_call_component.sh`
- Modify: `examples/p3-runtime/test_rust_async_call_component.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/async_call_component.rs`
- Keep unchanged: `examples/p3-runtime/async-call-component.wit`

**Interfaces:**
- Consumes: the inline-enabled Component WAT and the existing `work: async func()` host runner.
- Produces: ready, pending, cancellation-during-inline, and cancellation-during-explicit-child observations with exact host-Future completion/drop counts.

- [x] **Step 1: Extend the Do/component gate.**

Build the modified fixture with `--p3-async-call-component`, assert `[guest-inline-helper]`, `[guest-inline-resume]`, the existing child/root markers, two host call sites, and no helper export. Continue comparing the generated WIT with `async-call-component.wit` and assembling with the pinned legacy toolchain.

- [x] **Step 2: Add runtime modes for both pending phases.**

Keep `ready` and `pending`, but expect two host calls, two completions, and two Future drops. Split cancellation into `cancel-inline` (cancel after the first host call, before the inline completion; one call and one pending drop) and `cancel-child` (cancel after the second host call; two calls, one completed drop, one pending drop). Keep `table-empty=true`, `guest_completed=false` for cancellation, and `async-call root-terminal=1 duplicate-drop=0` for every completed root.

- [x] **Step 3: Run the pinned gates.**

Run:

```bash
legacy_wasm_tools=/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-inline-colorless.XXXXXX")
./bin/do build examples/p3-runtime/async-call-component.do \
  --p3-async-call-component --p3-wit-output "$tmp_dir/async-call.wit" \
  -o "$tmp_dir/async-call.wat"
"$legacy_wasm_tools" parse "$tmp_dir/async-call.wat" -o "$tmp_dir/async-call.core.wasm"
WASM_TOOLS="$legacy_wasm_tools" bash examples/p3-runtime/assemble_wasmtime_p3_legacy.sh \
  "$tmp_dir/async-call.wit" "$tmp_dir/async-call.core.wasm" probe \
  "$tmp_dir/async-call.component.wasm"
bash examples/p3-runtime/test_rust_async_call_component.sh \
  "$tmp_dir/async-call.component.wasm"
```

Expected: Component parse/embed/new/validate succeeds, all four runtime modes pass, and no external-effect rollback marker is emitted.

- [x] **Step 4: Commit the runtime checkpoint.**

```bash
git add examples/p3-runtime/test_do_async_call_component.sh examples/p3-runtime/test_rust_async_call_component.sh examples/p3-runtime/rust-host-runner/src/bin/async_call_component.rs
git commit -m "test: verify inline async-call cleanup phases"
```

### Task 5: Synchronize specifications and close the regression gate

**Files:**
- Modify: `docs/superpowers/specs/2026-08-07-general-async-call-lowering-design.md`
- Modify: `docs/superpowers/plans/2026-08-07-general-async-call-lowering.md`
- Modify: `doc/spec_rules.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `examples/p3-runtime/README.md`

**Interfaces:**
- Consumes: the verified plan field, frame phases, and runtime matrix from Tasks 2-4.
- Produces: a truthful source/lowering boundary: colorless ordinary functions are permitted semantically, one inline unit helper is admitted only under the opt-in Component target, and general async-call composition remains pending.

- [x] **Step 1: Document the non-contagious source rule.**

State that an ordinary function may contain explicit `@await`/`@cancel` when its body has an admitted async operation, but its signature remains ordinary; a normal call is inline and `@async(call)` is the only user-function Future creation boundary.

- [x] **Step 2: Record the exact admission boundary.**

Record both accepted unit shapes (with and without the leading inline call), the stable `UnsupportedP3AsyncCallComponent` rejection for broader forms, and the fact that v1/default dispatch remains unchanged.

- [x] **Step 3: Run the full verification matrix.**

```bash
./src/build/test/run_tests.sh
cd src && zig test build/codegen_component_async_call_plan_test.zig
zig test build/codegen_component_async_call_test.zig
zig test build/codegen_component_async.zig
cd ..
git diff --check
```

Expected: the repository harness summary reports `fail=0`, all focused Zig tests pass, the modified fixture builds only under `--p3-async-call-component`, and the working tree contains only the planned changes.

- [x] **Step 4: Commit the documentation and final gate.**

```bash
git add docs/superpowers/specs/2026-08-07-general-async-call-lowering-design.md docs/superpowers/plans/2026-08-07-general-async-call-lowering.md doc/spec_rules.md doc/pending_blocked.md doc/roadmap_status.md examples/p3-runtime/README.md
git commit -m "docs: close inline colorless async-call boundary"
```

## Stop Conditions

- If the inline host operation cannot be resumed and the explicit child cannot be started from one root-owned frame under the pinned Component async ABI, stop at the plan/analyzer boundary and record the ABI evidence; do not fake inline execution by silently dropping the first host Future.
- If either cancellation phase produces duplicate drops or leaves a non-empty `ResourceTable`, stop the runtime promotion and retain the source check-only behavior.
- If supporting `helper()` requires changing ordinary function signatures to `Future<T>` or reintroducing an `async` declaration, reject that implementation as async contagion and return to the source contract.
- Do not expand this phase to payloads, resources, streams, lists, arbitrary producer expressions, filesystem async, HTTP, or D2 host I/O.
