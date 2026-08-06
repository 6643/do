# Generic Async Runtime Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Replace the current generic Component async contract-only probe with one
real, observable pending/ready/cancel runtime slice while preserving explicit
negative boundaries for every unsupported async shape.

**Architecture:** Keep the existing synchronous \`@host\` fixture as an eager
metadata/ABI smoke. Add a separate pinned async-host probe whose runtime is
driven by one Wasmtime Component future. The compiler owns a small affine task
frame and a waitable-set state machine; the Rust runner supplies controlled
pending, immediate-ready, and cancellation observations. No operation IDs,
rollback protocol, public ownership syntax, or generic payload ABI is added.

**Tech Stack:** Zig 0.16.0, existing Do parser/sema/codegen pipeline,
wasm-tools 1.254.0, Wasmtime 47.0.2 with
\`component-model-async\` and \`cm-more-async-builtins\`, Rust host runner.

## Global Constraints

- Keep \`AsyncLoweringUnavailable\` for all non-admitted ordinary builds.
- Keep the current synchronous \`generic-async-single-future\` fixture as an
  eager/metadata smoke; do not label it a pending runtime.
- Add one separately pinned async host descriptor; do not infer async effect
  from locator/member text.
- One active Component future per Wasmtime Store; the guest scheduler owns
  logical tasks and the host drives only the Component future.
- Cancellation follows \`subtask.cancel -> terminal observation -> subtask.drop\`.
- Cancellation never rolls back an external side effect.
- Admit only unit payload, two sequential awaits, one independent cancel, and
  one root.
- Keep Result payloads, Stream scheduling, resources, callbacks, timeout,
  aggregate await, arbitrary async declarations, and \`own/borrow/ref\`
  outside this slice.

---

### Task 1: Correct the current contract evidence and add Component negative boundaries

**Files:**
- Modify: \`doc/pending_blocked.md\`
- Modify: \`src/build/codegen_component_async.zig\`
- Create: \`src/build/test/compile_err/424_generic_component_payload_unavailable.do\`
- Create: \`src/build/test/compile_err/424_generic_component_payload_unavailable.expect\`
- Create: \`src/build/test/compile_err/425_generic_component_multiple_await.do\`
- Create: \`src/build/test/compile_err/425_generic_component_multiple_await.expect\`

**Interfaces:**
- Consumes: current \`Target.generic_async\` admission and the synchronous
  fixture.
- Produces: explicit component-target rejection coverage and documentation
  that calls the current runner contract-only.

- [x] Add a payload Future and a second-await component fixture using the same
  generic host locator; both must fail with \`UnsupportedP3AsyncComponent\`
  under \`--p3-async-component\`.
- [x] Run each new fixture before implementation changes and confirm the
  failure is the target guard, not a parser error.
- [x] Add a unit assertion that an async declaration with the generic host
  locator cannot select \`Target.generic_async\`.
- [x] Narrow the pending-blocked wording from “exactly-once runtime cleanup”
  to “observed synchronous eager completion plus structural ABI markers”.
- [x] Run:

  \`\`\`bash
  cd src
  zig test build/codegen_component_async.zig
  cd ..
  ./src/build/test/run_tests.sh
  \`\`\`

### Task 2: Pin the real async-host probe and define its source contract

**Files:**
- Modify: \`src/build/p3_async_registry.json\`
- Modify: \`src/build/p3_async_manifest.zig\`
- Create: \`examples/p3-runtime/generic-async-runtime.wit\`
- Create: \`examples/p3-runtime/generic-async-runtime.do\`
- Create: \`src/build/test/compile_err/426_generic_async_runtime_payload.do\`
- Create: \`src/build/test/compile_err/426_generic_async_runtime_payload.expect\`

**Interfaces:**
- Consumes: the existing descriptor registry and Component async naming
  convention.
- Produces: one pinned descriptor with explicit WIT package/interface/member,
  async Core import, task-return shape, and WIT hash.

- [x] Pin \`do:generic-async-runtime-probe@0.1.0/host.work\` as an async unit
  operation with explicit \`async_import_module\`,
  \`async_import_name\`, \`completion = task-return\`, and WIT names.
- [x] Define the WIT world with \`work: async func()\` and
  \`export run: async func()\`; keep the WIT package private to the probe.
- [x] Choose and document the source spelling: an async host binding produces
  a \`Future<nil>\` according to the pinned descriptor, while \`@async\` remains
  reserved for eager creation from an ordinary synchronous call. Do not
  silently create \`Future<Future<T>>\).
- [x] Add a negative payload descriptor/source fixture and assert
  \`AsyncLoweringUnavailable\` or the precise pinned-shape diagnostic.
- [x] Run registry unit tests and WIT hash validation before codegen changes.

### Task 3: Implement a real generic task/frame state model

**Files:**
- Create: \`src/build/codegen_generic_async_runtime.zig\`
- Modify: \`src/build/codegen_generic_async_frame.zig\`
- Modify: \`src/build/codegen_generic_async_plan.zig\`
- Create: \`src/build/test/check/427_generic_async_runtime_contract.do\`

**Interfaces:**
- Consumes: the exact plan from Task 2.
- Produces:

  \`\`\`zig
  pub const GenericRuntimeState = enum {
      new, running, waiting, ready, cancelling, cancelled, terminal,
  };

  pub const GenericRuntimeEvent = union(enum) {
      host_pending,
      host_ready,
      host_failed,
      cancel_requested,
      cancel_terminal,
  };

  pub fn transition(
      state: GenericRuntimeState,
      event: GenericRuntimeEvent,
  ) !GenericRuntimeState;
  \`\`\`

- [x] Write failing transition tests for pending->ready, pending->cancelled,
  duplicate terminal, cancel-after-ready, and double cleanup.
- [x] Implement guard-style transitions with exactly one terminal cleanup.
- [x] Add frame slots for waitable-set, subtask handle, state, and terminal
  flag; reject a second active frame in the admitted single-root shape.
- [x] Make the analyzer expose whether the operation is synchronous eager or
  descriptor-backed async; do not infer this in the emitter.
- [x] Run:

  \`\`\`bash
  cd src
  zig test build/codegen_generic_async_runtime.zig
  zig test build/codegen_generic_async_frame.zig
  \`\`\`

### Task 4: Lower the frame into an executable Component async state machine

**Files:**
- Modify: \`src/build/codegen_emit_generic_async.zig\`
- Modify: \`src/build/codegen_component_async.zig\`
- Modify: \`src/build/wat_component_metadata.zig\`
- Create: \`src/build/test/compile_ok/427_generic_async_runtime.do\`

**Interfaces:**
- Consumes: \`GenericRuntimeState\`, pinned descriptor metadata, and existing
  \`[async-lift]\`, callback, \`[task-return]\`, \`[subtask-cancel]\`,
  \`[subtask-drop]\` names.
- Produces: Core WAT with executable pending/ready/cancel branches and no
  contract-only dead cancellation branch.

- [x] Write a failing WAT assertion requiring a reachable
  \`call $subtask-cancel\), \`call $subtask-drop\), callback state dispatch,
  and one \`call $task-return\) on each terminal branch.
- [x] Emit the async host import from the registry's canonical module/name.
- [x] On immediate host completion, clear frame context and call
  \`task-return\` exactly once.
- [x] On pending host completion, store the subtask/waitable handle and return
  the encoded waitable status; callback resumes the frame and releases it only
  after terminal completion.
- [x] On cancellation, call \`subtask-cancel\), validate terminal status, then
  call \`subtask-drop\` and frame cleanup exactly once.
- [x] Keep the synchronous fixture on its existing eager path.
- [x] Parse and validate the generated Core WAT before the runtime runner.

### Task 5: Replace the Rust placeholder runner with observable runtime tests

**Files:**
- Modify: \`examples/p3-runtime/rust-host-runner/Cargo.toml\`
- Modify: \`examples/p3-runtime/rust-host-runner/src/bin/generic_async_single_future.rs\`
- Create: \`examples/p3-runtime/rust-host-runner/src/bin/generic_async_runtime.rs\`
- Create: \`examples/p3-runtime/test_do_generic_async_runtime.sh\`

**Interfaces:**
- Consumes: Task 4 component and WIT artifacts.
- Produces: host assertions that observe polls, external wakes,
  completion count, cancellation order, and drop count.

- [x] Implement a \`PendingWork\) Future that increments poll count, wakes once
  on a controlled signal, and increments drop count in \`Drop\`.
- [x] Implement an immediate-ready Future with zero external wakes.
- [x] Run the same component in pending, immediate-ready, and cancel modes;
  the mode must change host Future behavior, not only output text.
- [x] Fail on duplicate callback, duplicate completion, drop-before-cancel
  terminal observation, or any completion after cancellation.
- [x] Require these exact markers:

  \`\`\`text
  pending external-wakes=2 completions=2 drops=1
  immediate external-wakes=0 completions=3 drops=0
  cancel cancel-before-completion=1 completions=2
  \`\`\`

- [x] Run the runner with Wasmtime 47.0.2 and the pinned async feature flags.

### Task 6: Close the phase with negative, full, and release verification

**Files:**
- Modify: \`src/build/test/run_tests.sh\`
- Modify: \`doc/host_abi_blockers.md\`
- Modify: \`doc/pending_blocked.md\`
- Modify: \`doc/spec_rules.md\`
- Modify: \`docs/superpowers/plans/2026-08-05-generic-async-runtime.md\`

**Interfaces:**
- Consumes: all Tasks 1-5 artifacts.
- Produces: a bounded phase record with no claim beyond the verified runtime
  matrix.

- [x] Add the new negative fixtures to the standard compile-error matrix.
- [x] Assert that ordinary unsupported async builds still produce
  \`AsyncLoweringUnavailable\`.
- [x] Record exact Wasmtime/wasm-tools versions, WIT hash, frame layout,
  pending/ready/cancel observations, and known non-goals.
- [x] Run:

  \`\`\`bash
  cd src
  zig test main.zig
  cd ..
  ./src/build/test/run_tests.sh
  bash examples/p3-runtime/test_do_generic_async_runtime.sh
  ./src/build/test/run_release_smoke.sh
  \`\`\`

- [x] Do not mark the phase complete unless the Rust runner observes real
  pending/wake/cancel behavior; structural WAT markers alone are insufficient.

The public syntax decision is closed with the colorless form: ordinary user
functions plus explicit `@async`, `@await`, and `@cancel`. The old
`async name(...) -> T` spelling is parser-only migration compatibility; it is
rejected by the generic runtime target and must not appear in new examples.
Removing that parser branch is deferred until the remaining descriptor-specific
WASI/Stream fixtures are migrated.

## Dependencies and non-blocking work

Tasks 1 and 2 are independent of the runtime emitter and can be reviewed
first. Task 3 must precede Task 4; Task 5 depends on Task 4; Task 6 is the
closeout gate. WIT bindgen documentation and generic locator work may continue
in parallel, but must not broaden this runtime admission boundary.

## Explicitly deferred

Public \`own<T>\`, \`borrow<T>\`, \`ref<T>\`, Result payloads, Stream scheduling,
resource ownership crossing, aggregate await, timeout, arbitrary async
function declarations, rollback semantics, and multi-root/concurrent Store
execution remain separate phases.
