# Mainline Replan After Bounded Probes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-sequence the mainline after the bounded G6.2 and colorless-async probes, then promote the already-verified async host scalar-argument ABI into one private compiler capability without adding public ownership syntax or reopening completed probes.

**Architecture:** The existing `do:async-call-arg-probe@0.1.0` WIT/Core/Rust/Wasmtime artifact is the ABI oracle and remains unchanged. M1 adds a separate opt-in compiler target, registry admission, strict source-shape analysis, and a root-owned frame emitter for exactly one `u32` host argument. M2-M4 are follow-up lanes with explicit entry gates; they are not silently opened by M1.

**Tech Stack:** Zig 0.16.0, the Do compiler, WIT/Core WAT, `wasm-tools` 1.255.0 plus the legacy 1.254.0 async assembler, Rust 1.97.1, Wasmtime 47.0.2, Bash gates, and `src/build/test/run_tests.sh`.

## Global Constraints

- Preserve the verified probe artifacts in `examples/p3-runtime/wit/async-call-arg-probe.wit`, `examples/p3-runtime/async-call-arg-probe-canonical.wat`, and `examples/p3-runtime/test_async_call_arg_probe.sh`; do not rerun the probe as feature work or weaken its assertions.
- Keep ordinary public result APIs as `T | E` or `nil | E`; private WIT/Component `Result<T, E>` rows remain ABI metadata only.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, lifetime, `externref`, `anyref`, or `funcref` syntax.
- Keep ordinary functions colorless. The only task-creation spelling remains `@async(call)`; host async bindings use `@host_async_func(...)`; `@await` and `@cancel` retain their current consumption and cancellation semantics.
- Add a separate opt-in target named `--p3-async-host-arg-component`. Do not widen the existing `--p3-async-call-component`, default dispatch, Generic ABI v2, or ordinary `do build` paths.
- Admit exactly one private descriptor: locator `do:async-call-arg-probe/host@0.1.0`, member `work`, WIT `async func(value: u32)`, Do result `nil`, Core import `(i32) -> i32`, no completion payload, and `task-return` completion.
- The accepted source topology has one `@host_async_func` binding, one `helper(value u32) -> nil`, one `work(value)` call, one root literal `@async(helper(7))`, and two `@await` sites (one in the helper and one in the root). No helper payload, second child, second inline phase, branch, loop, recursion, dynamic argument expression, resource, list, stream, or arbitrary producer is admitted.
- Every compiler capability requires positive and negative fixtures, a pinned WIT hash, measured frame/layout markers, Component validation, Rust/Wasmtime ready/pending/cancel cleanup evidence, and a full regression run.
- Cancellation terminates live Component/guest state and releases still-owned values; it never rolls back an already-issued host effect.

## Baseline and Mainline Order

The following state is already verified and must not be scheduled again:

- The scalar host-argument ABI probe is complete and remains probe-only: WIT hash `b9f5f8355e87231317ec05cccf692ee465c6f339bd509640aedc196e58f81e61`, frame size 20, argument slot `+12`, host value `7`, and ready/pending/cancel cleanup.
- Bounded scalar-list producer promotion, private owned-future promotion, inline scalar async-call, and D2 `descriptor.get-type`/`descriptor.sync`/`descriptor.get-flags` are complete.
- The remaining general async-call, general filesystem/HTTP, arbitrary producer, borrowed async value, and public ownership work stays pending.

Execution order:

1. M1: promote the existing scalar host-argument probe into the private compiler target below.
2. M2: only after M1 is green, decide whether duplicated bounded async-call frame logic justifies a shared internal descriptor/frame abstraction.
3. M3: choose one D2 filesystem method and create a separate method-specific design/probe/gate; no method is inferred from a neighboring descriptor.
4. M4: revisit general producer/resource ownership only after an explicit producer graph, ownership transfer, and cancellation contract exists.

### Task 1: Freeze the M1 design and red boundaries

**Files:**
- Create: `doc/superpowers/specs/2026-08-09-async-host-scalar-argument-promotion-design.md`
- Verify: `doc/roadmap_status.md:49-67` as the probe evidence source.
- Verify: `examples/p3-runtime/wit/async-call-arg-probe.wit`
- Verify: `examples/p3-runtime/async-call-arg-probe-canonical.wat`

**Interfaces:**
- Consumes: the existing probe WIT hash and canonical frame facts.
- Produces: an exact source-shape contract for the compiler promotion and stable rejection names for every out-of-scope topology.

- [ ] **Step 1: Record the exact accepted source shape.**

  The design must include:

  ```do
  work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)

  helper(value u32) -> nil {
      pending Future<nil> = work(value)
      @await(pending)
  }

  run() -> nil {
      child Future<nil> = @async(helper(7))
      @await(child)
  }
  ```

- [ ] **Step 2: Freeze the frame and cleanup contract.**

  State `waitable-set@0`, active host subtask `@4`, helper phase `@8`, and
  `u32` argument `@12` in a 20-byte, 4-byte-aligned root-owned frame. On
  normal completion drop the subtask, waitable set, context, and frame once;
  on cancellation cancel/drop the active subtask first, then perform the same
  cleanup and call root `task-cancel`.

- [ ] **Step 3: Write the red boundary list.**

  Before implementation, list the required negative cases: unregistered
  locator, `@host_func` marker mismatch, non-`u32` argument, two host
  arguments, dynamic root argument, helper payload, nested helper, second
  child, resource/list/stream payload, and legacy `async` declaration.

- [ ] **Step 4: Commit the design-only change.**

  ```bash
  git add doc/superpowers/specs/2026-08-09-async-host-scalar-argument-promotion-design.md
  git commit -m "docs: define async host scalar argument promotion"
  ```

### Task 2: Add the private registry and CLI target

**Files:**
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/cli.zig`
- Modify: `src/build/codegen_model.zig`
- Modify: `src/build/run.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/codegen_api.zig`
- Modify: `src/main.zig`
- Test: `src/build/p3_async_manifest.zig`
- Test: `src/build/cli.zig`

**Interfaces:**
- Consumes: the exact private WIT package `do:async-call-arg-probe@0.1.0` and member `host.work`.
- Produces: `EmitOptions.p3_async_host_arg_component`, CLI parsing, WIT sidecar selection, and a registry descriptor that rejects signature or hash drift.

- [ ] **Step 1: Add the descriptor.**

  Add one `effect: "async-host-scalar-argument"` descriptor with:

  ```text
  locator: do:async-call-arg-probe/host@0.1.0
  member: work
  params: [u32]
  result: nil
  wit_sha256: b9f5f8355e87231317ec05cccf692ee465c6f339bd509640aedc196e58f81e61
  canonical.core_params: [i32]
  canonical.core_results: []
  canonical.completion_params: []
  canonical.completion: task-return
  canonical.async_import_name: [async-lower]work
  ```

- [ ] **Step 2: Add `--p3-async-host-arg-component`.**

  Wire the flag through CLI parsing, special-target exclusivity, start-entry
  checks, WIT output handling, `EmitOptions`, pipeline dispatch, and help text.
  The target must reject simultaneous component targets and must not alter
  default `do build` behavior.

- [ ] **Step 3: Add manifest unit tests.**

  Verify descriptor effect, package/world/interface/member, hash, Core import,
  and rejection of a changed parameter, result, hash, or completion shape.

- [ ] **Step 4: Run focused checks.**

  ```bash
  cd src && zig test build/p3_async_manifest.zig
  zig test build/cli.zig
  cd ..
  ./bin/do --help
  ```

- [ ] **Step 5: Commit registry/target plumbing.**

  ```bash
  git add src/build/p3_async_registry.json src/build/p3_async_manifest.zig \
    src/build/cli.zig src/build/codegen_model.zig src/build/run.zig \
    src/build/codegen_pipeline.zig src/build/codegen_api.zig src/main.zig
  git commit -m "Add private async host scalar argument target"
  ```

### Task 3: Implement strict source analysis and root-frame lowering

**Files:**
- Create: `src/build/codegen_component_async_host_arg_plan.zig`
- Create: `src/build/codegen_component_async_host_arg.zig`
- Create: `src/build/codegen_component_async_host_arg_plan_test.zig`
- Create: `src/build/codegen_component_async_host_arg_test.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/codegen_api.zig`

**Interfaces:**
- Consumes: the registry descriptor and existing lexer/token helpers.
- Produces: `AsyncHostScalarArgPlan`, `emit_component_wit`, and `emit_component_wat` for the exact source shape.

- [ ] **Step 1: Write failing planner tests.**

  Add tests for the accepted fixture and every Task 1 rejection. The planner
  must return `error.UnsupportedP3AsyncHostArgComponent` before WAT whenever a
  contract predicate fails.

- [ ] **Step 2: Implement descriptor-backed source analysis.**

  Match `@host_async_func` by locator/member/signature against the registry;
  require exactly one helper parameter named by the source, typed `u32`, one
  `work(value)` call, one root literal `@async(helper(7))`, two `@await`
  tokens, and no `@cancel` source call. Do not infer async behavior from the
  function name or from a generic `Future<nil>` result.

- [ ] **Step 3: Add the WIT emitter.**

  Emit the existing package/world shape byte-for-byte:

  ```wit
  package do:async-call-arg-probe@0.1.0;

  interface host {
    work: async func(value: u32);
  }

  world probe {
    import host;
    export run: async func();
  }
  ```

- [ ] **Step 4: Add the Core emitter.**

  Reuse the probe's measured frame and event markers, but generate the module
  from the validated plan. The generated module must import
  `[async-lower]work` as `(param i32) (result i32)`, store/load the argument at
  frame `+12`, expose only root `run` task-return/callback endpoints, and use
  the exact once-only cleanup order.

- [ ] **Step 5: Run focused Zig tests.**

  ```bash
  cd src
  zig test build/codegen_component_async_host_arg_plan_test.zig
  zig test build/codegen_component_async_host_arg_test.zig
  cd ..
  ```

- [ ] **Step 6: Commit the lowering slice.**

  ```bash
  git add src/build/codegen_component_async_host_arg_plan.zig \
    src/build/codegen_component_async_host_arg.zig \
    src/build/codegen_component_async_host_arg_plan_test.zig \
    src/build/codegen_component_async_host_arg_test.zig \
    src/build/codegen_pipeline.zig src/build/codegen_api.zig
  git commit -m "Lower private async host scalar argument"
  ```

### Task 4: Add compiler fixtures and generated runtime gates

**Files:**
- Create: `src/build/test/check/490_async_host_scalar_argument_component.do`
- Create: `src/build/test/compile_ok/490_async_host_scalar_argument_component.do`
- Create: `src/build/test/compile_err/490_async_host_scalar_argument_unregistered.do`
- Create: `src/build/test/compile_err/490_async_host_scalar_argument_unregistered.expect`
- Create: `src/build/test/compile_err/491_async_host_scalar_argument_wrong_marker.do`
- Create: `src/build/test/compile_err/491_async_host_scalar_argument_wrong_marker.expect`
- Create: `src/build/test/compile_err/492_async_host_scalar_argument_type.do`
- Create: `src/build/test/compile_err/492_async_host_scalar_argument_type.expect`
- Create: `src/build/test/compile_err/493_async_host_scalar_argument_two_params.do`
- Create: `src/build/test/compile_err/493_async_host_scalar_argument_two_params.expect`
- Create: `src/build/test/compile_err/494_async_host_scalar_argument_dynamic.do`
- Create: `src/build/test/compile_err/494_async_host_scalar_argument_dynamic.expect`
- Create: `src/build/test/compile_err/495_async_host_scalar_argument_payload.do`
- Create: `src/build/test/compile_err/495_async_host_scalar_argument_payload.expect`
- Create: `src/build/test/compile_err/496_async_host_scalar_argument_nested.do`
- Create: `src/build/test/compile_err/496_async_host_scalar_argument_nested.expect`
- Create: `src/build/test/compile_err/497_async_host_scalar_argument_two_children.do`
- Create: `src/build/test/compile_err/497_async_host_scalar_argument_two_children.expect`
- Create: `examples/p3-runtime/async-host-scalar-argument.do`
- Create: `examples/p3-runtime/test_do_async_host_scalar_argument.sh`

**Interfaces:**
- Consumes: the new private target and existing probe WIT.
- Produces: compiler acceptance and fail-closed coverage before WAT.

- [ ] **Step 1: Add the positive fixture.**

  Use the exact Task 1 source. Its expected WAT must contain the argument
  store/load and host import markers, frame size `20`, and no helper
  `[task-return]` endpoint.

- [ ] **Step 2: Add the negative fixtures.**

  Each `.expect` file must name `UnsupportedP3AsyncHostArgComponent` (or the
  narrower existing diagnostic selected by the planner) and the build arg
  `--p3-async-host-arg-component`. No negative fixture may silently fall back
  to generic Core-Wasm lowering.

- [ ] **Step 3: Add the Do-side Component gate.**

  The shell gate must build the fixture, emit the WIT sidecar, compare it to
  the existing probe package, run both pinned `wasm-tools` assembly routes,
  validate the Component, and assert the measured markers.

- [ ] **Step 4: Run fixture and boundary tests.**

  ```bash
  ./bin/do test src/build/test/check/490_async_host_scalar_argument_component.do
  bash examples/p3-runtime/test_do_async_host_scalar_argument.sh
  ./src/build/test/run_tests.sh
  ```

- [ ] **Step 5: Commit compiler fixtures.**

  ```bash
  git add src/build/test/check/490_async_host_scalar_argument_component.do \
    src/build/test/compile_ok/490_async_host_scalar_argument_component.do \
    src/build/test/compile_err/49{0,1,2,3,4,5,6,7}_async_host_scalar_argument* \
    examples/p3-runtime/async-host-scalar-argument.do \
    examples/p3-runtime/test_do_async_host_scalar_argument.sh
  git commit -m "Gate async host scalar argument compiler promotion"
  ```

### Task 5: Run the Rust/Wasmtime promotion gate

**Files:**
- Verify: `examples/p3-runtime/rust-host-runner/src/bin/async_call_arg_probe.rs`
- Verify: `examples/p3-runtime/test_async_call_arg_probe.sh`
- Create: `examples/p3-runtime/test_rust_async_host_scalar_argument.sh`

**Interfaces:**
- Consumes: the compiler-generated Component from Task 4.
- Produces: ready/pending/cancel runtime evidence for the promoted compiler path.

- [ ] **Step 1: Reuse the existing host runner without changing its oracle.**

  The generated Component must expose the same private `probe.run` world as
  the canonical probe, so the existing Rust runner can observe `value=7`.
  Do not duplicate or weaken the host counters.

- [ ] **Step 2: Add the generated-component Rust gate.**

  Run the existing runner for `ready`, `pending`, and `cancel`. Require the
  same counters as the canonical probe: one call, observed argument `7`, one
  Future drop, no resource drops, and an empty `ResourceTable`.

- [ ] **Step 3: Run both toolchain routes and the gate.**

  ```bash
  bash examples/p3-runtime/test_do_async_host_scalar_argument.sh
  bash examples/p3-runtime/test_rust_async_host_scalar_argument.sh
  WASM_TOOLS_EXPECT_VERSION=1.255.0 bash examples/p3-runtime/test_async_call_arg_probe.sh
  WASM_TOOLS_EXPECT_VERSION=1.254.0 \
    WASM_TOOLS=/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools \
    bash examples/p3-runtime/test_async_call_arg_probe.sh
  ```

- [ ] **Step 4: Commit the runtime gate.**

  ```bash
  git add examples/p3-runtime/test_rust_async_host_scalar_argument.sh
  git commit -m "Run async host scalar argument promotion"
  ```

### Task 6: Close M1 and update the mainline handoff

**Files:**
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/master_plan.md`
- Modify: `doc/pending_blocked.md`
- Modify: `CHANGELOG.md`
- Modify: `README.md` only if the new private opt-in target is documented there

**Interfaces:**
- Consumes: all green M1 compiler and runtime evidence.
- Produces: a status record that distinguishes probe completion from compiler promotion and preserves all remaining no-go boundaries.

- [ ] **Step 1: Update only verified status.**

  Move the scalar host-argument item from `probe-only` to `private bounded
  compiler promotion` only after Tasks 2-5 pass. Keep general async-call,
  arbitrary producer expressions, payload/resource/list/stream futures, D2
  general filesystem/HTTP, borrowed async values, root hard-cancel, and public
  ownership syntax pending.

- [ ] **Step 2: Run the closeout matrix.**

  ```bash
  cd src && zig test main.zig
  cd ..
  ./src/build/test/run_tests.sh
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  git diff --check
  ```

  Expected: no default-target acceptance outside the new opt-in flag, no new
  skips, and the existing bounded G6.2/D2 gates remain green.

- [ ] **Step 3: Commit the handoff.**

  ```bash
  git add doc/roadmap_status.md doc/start_here.md doc/master_plan.md \
    doc/pending_blocked.md CHANGELOG.md README.md
  git commit -m "docs: replan mainline after bounded async probes"
  ```

## Post-M1 Lanes And Entry Gates

These lanes are recorded here to re-sequence the mainline, but are not opened
by this plan and must not be implemented in the M1 commits.

### M2: Bounded async-call internal consolidation

Entry requires all M1 gates green plus a measured duplication report across
unit, scalar helper, inline scalar, and host scalar-argument emitters. The
follow-up design may extract a descriptor-driven frame/continuation helper,
but it must preserve separate capability predicates and fail-closed negative
fixtures. It must not infer generic `Future<T>` lowering from one descriptor,
change `@async/@await/@cancel`, or widen default dispatch.

M2 Step 1 is complete in
[`2026-08-09-async-call-internal-consolidation-assessment.md`](../specs/2026-08-09-async-call-internal-consolidation-assessment.md).
The report is `GO-limited`: proceed to a design-only Step 2, with a valid
`NO-GO` outcome if the shared layer obscures the existing mode-specific
cleanup and admission contracts.

The Step 2 contract is recorded in
[`2026-08-09-async-call-internal-consolidation-design.md`](../specs/2026-08-09-async-call-internal-consolidation-design.md).
It selects descriptor-only structural reuse, keeps the three admission and
cleanup paths explicit, and requires output/rejection differential gates before
any emitter implementation.

The executable implementation sequence is recorded in
[`2026-08-09-async-call-internal-consolidation.md`](2026-08-09-async-call-internal-consolidation.md).

### M3: One D2 method-specific promotion

Choose exactly one row from the D2 matrix and create a separate dated design,
pinned WIT hash, canonical WAT, positive/negative fixtures, Component gate,
and Rust/Wasmtime ready/pending/error/cancel matrix. `read-via-stream` and
`read-directory` require stream plus completion-future ownership; `open-at`
requires an owned-resource presence/drop protocol; borrowed methods remain
blocked by the pinned toolchain and source ownership boundary.

### M4: General producer/resource ownership

Entry requires a separate producer graph and ownership contract covering
producer nodes, transfer points, payload cleanup, multiple awaits, overlap
limits, cancellation, and terminal states. Generic list/variant/borrowed
payloads and arbitrary producer expressions remain rejected until each has its
own canonical probe and runtime gate. Public `own<T>`/`borrow<T>`/`ref<T>` is a
separate language-design decision, not an implicit consequence of M1.

## Self-Review

- **Coverage:** the plan distinguishes the completed ABI probe from M1 compiler promotion and records M2-M4 entry gates.
- **No syntax drift:** all M1 source examples use existing `@host_async_func`, `Future`, `@async`, and `@await` forms.
- **No probe duplication:** existing WIT, canonical WAT, and Rust oracle artifacts are verified/reused rather than recreated.
- **Boundary integrity:** public ownership syntax, generic async lowering, arbitrary producers, D2 general methods, and default dispatch remain closed.
- **Verification:** every implementation task has focused commands, and the closeout task repeats the full repository regression and release smoke.
