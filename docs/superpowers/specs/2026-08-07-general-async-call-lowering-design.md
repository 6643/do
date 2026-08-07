# General Async-Call Lowering Design

Status: bounded root-owned local-frame slice implemented and verified; general
async-call composition remains pending.

Date: 2026-08-07

## Goal

Add a Component-only, opt-in lowering for a user function invoked through
`@async(call)`. The first slice must prove a real guest-to-guest async call
with a compiler-managed local helper continuation under one root task, while
keeping the existing v1 and Generic ABI v2 dispatch paths unchanged.

This is the first step toward general async-call composition. It is not a
claim that arbitrary async functions, payloads, resources, or producer
expressions are complete.

## Current Boundary

The source contract is colorless:

- user functions use ordinary declarations;
- `@async(call)` creates a `Future<T>` for a synchronous user call;
- a registered WIT async host binding already returns `Future<T>` and must not
  be wrapped in `@async`;
- `@await` and `@cancel` consume futures.

The Core generic async emitter already has a bounded synchronous-call shape,
but the Component analyzer currently admits only direct registered host
sequences and generated manifest capabilities. A user helper called through
`@async` is therefore rejected by the Component target. This design closes
that specific boundary without changing ordinary `do build` behavior.

Pinned evidence for the first probe is:

| Tool | Version |
| --- | --- |
| Zig | `0.16.0` |
| wasm-tools legacy assembly | `1.254.0 (bb58fdf91 2026-07-20)` |
| Wasmtime | `47.0.2` |
| Rust | `1.97.1` |

`wasm-tools 1.255.0` remains capability-probe-only and is not used to claim
legacy async assembly compatibility.

## Recommended Architecture

Use an internal continuation graph rather than whole-program inlining. Each
admitted `@async(helper(...))` edge produces a compiler-managed helper frame
and a parent continuation record inside the root async task:

```text
root task/frame
  -> local helper frame/state
       -> registered async host subtask
       -> root callback(parent continuation)
  -> root await/cancel terminal
```

The compiler remains responsible for the graph and cleanup ordering; no task
handle, raw pointer, or reference is exposed in Do source. The internal plan
must contain:

- a stable function identity for every admitted user helper;
- the helper frame layout and state number;
- the parent continuation state after child completion;
- the helper terminal action (`return` or cancellation);
- ownership actions for the helper future, host subtask, and frame.

The root and helper are both represented in the generated Core module. The
helper does not become a WIT export and therefore has no independent
`task.return` endpoint. Its completion is delivered through the root callback
and the root's existing `task.return` path; the parent continuation resumes
only after the helper terminal state is observed. The helper subtask/frame is
dropped before the root frame slot is cleared.

The new Component route is opt-in and mutually exclusive with existing
special targets:

```text
--p3-async-call-component
```

`--p3-async-component` remains the v1 dispatcher. The
`--p3-async-component-v2` profile remains limited to its two measured private
shapes. No existing target silently routes to the new dispatcher.

## First Admitted Shape

The first source fixture uses the already pinned private async host:

```do
work = @host("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)

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

Admission is deliberately exact for this first slice:

- one ordinary helper declaration with no parameters and `nil` result;
- one direct registered async host call in the helper;
- one `@await` of that host future;
- one root `@async(helper())` call and one root `@await(child)`;
- no branches, loops, `defer`, multiple live children, or second helper edge;
- no payload, `Stream`, resource, list, borrowed value, or external producer;
- no `async` function declaration.

The WIT sidecar is the private `do:generic-async-call-probe@0.1.0` `probe`
world with `host.work: async func` and `export run: async func()`. The helper
is an internal guest function and must not add a WIT import or export.

## Cancellation Contract

The positive runtime gate drives three host modes:

1. `ready`: the host work completes immediately and the helper returns once;
2. `pending`: the helper remains in-flight until the host wakes it, then the
   parent continuation completes;
3. `cancel`: the host cancels the root while the helper host operation is
   pending; the helper subtask, helper future, and root frame are released
   exactly once.

Cancellation is a guest/Component lifecycle transition. It does not undo a
host effect that was already issued and does not add an operation id,
compensation callback, or rollback protocol.

Required runtime observations are:

- pending: one helper subtask, one host wake, one helper completion, one helper
  drop, one root completion;
- ready: zero external wakes, one helper completion, one helper drop, one root
  completion;
- cancel: one root cancellation, one helper cancellation/drop, no duplicate
  frame or subtask release, and an empty Component resource table.

## Negative Boundary

The compiler must reject each case before WAT emission with a stable named
diagnostic for this target:

- helper parameters or a non-`nil` helper result;
- helper payload future (`Future<i32>`, `Future<text>`, or `Future<Result<...>>`);
- a helper with two host futures or two `@await` operations;
- two live `@async` children in one parent;
- nested helper-to-helper calls, recursion, or a helper passed as a value;
- branches, loops, `defer`, or dynamic call expressions in the helper;
- `Stream<T>`, list, resource, `borrow<T>`, or variant payloads;
- an unregistered host locator/member or a generated manifest without the
  exact admitted capability;
- legacy `async helper(...)` declarations.

The negative fixtures must remain separate from the existing v1 and v2
negative suites so that a future target cannot accidentally broaden an older
dispatcher.

## Pinned Probe Before Codegen

Before compiler changes, add a hand-written Core/WIT probe and run it through
the pinned legacy assembler. The probe must demonstrate that the selected
Component model accepts:

- one exported async root task;
- one internal helper continuation/frame owned by that root task;
- one imported async host operation;
- the root callback resuming the helper state;
- the root `task.return` terminal path.

The probe commands are:

```bash
legacy_wasm_tools=/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools
WASM_TOOLS="$legacy_wasm_tools" bash examples/p3-runtime/test_async_call_component_probe.sh
```

The script must verify the exact version and SHA-256, parse both Core modules,
embed the WIT sidecar with legacy async callback names, expect the independent
task endpoint rejection with its complete diagnostic, and create/validate the
root-owned local-frame Component with `cm-async,cm-more-async-builtins`. The
runtime ready/pending/cancel matrix is implemented with the compiler emitter in
the later runtime task; this ABI probe does not claim those observations.

### Probe result (2026-08-07)

The hand-written probes are
`examples/p3-runtime/async-call-component-probe.wat` (the rejected synthetic
independent child endpoint) and
`examples/p3-runtime/async-call-component-local-frame-probe.wat` (the accepted
root-owned continuation), driven by
`examples/p3-runtime/test_async_call_component_probe.sh` with:

```bash
legacy_wasm_tools=/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools
WASM_TOOLS="$legacy_wasm_tools" bash examples/p3-runtime/test_async_call_component_probe.sh
```

The pinned tool reports `wasm-tools 1.254.0 (bb58fdf91 2026-07-20)` and
SHA-256
`cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6`.
Core parsing, legacy async dummy metadata generation, and custom-section
attachment succeed. Component assembly rejects the synthetic internal endpoint
before validation:

```text
error: failed to encode a component from module

Caused by:
    0: failed to decode world from module
    1: module was not valid
    2: failed to resolve import `[export]$root::[task-return]helper`
    3: no export `helper` found
```

This is the expected ABI boundary: `task.return` is generated for the WIT
async export `run`; an ordinary guest `$helper` that is absent from the WIT
world has no independent Component task endpoint. The `wit-bindgen` guest-Rust
`spawn_local` facility is an executor-local queue and does not add a guest
Component task or a second `task.return` endpoint.

The same pinned assembler accepts the local-frame probe. Its `$helper` calls
the registered async host import, stores the packed subtask in the root frame,
and returns through the root callback and `[task-return]run`; it does not import
`[task-return]helper`. Both `component new --skip-validation` and
`validate --features cm-async,cm-more-async-builtins` pass. This closes the ABI
question for the selected root-owned local-frame route. Independent guest
child-task creation remains a deferred ABI capability and is not part of the
compiler target.

## Implementation Result (2026-08-07)

The bounded slice is implemented by `codegen_component_async_call_plan.zig` and
`codegen_component_async_call.zig`, exposed only through
`--p3-async-call-component`. The registry contains a separate private
`do:generic-async-call-probe/host@0.1.0` descriptor; the existing generic
runtime descriptor and v1/v2 dispatch paths are unchanged. The generated WIT
snapshot is `examples/p3-runtime/async-call-component.wit` and contains no
helper export or public ownership syntax.

The Do/Component gate is reproducible with:

```bash
WASM_TOOLS=/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools \
  bash examples/p3-runtime/test_do_async_call_component.sh
```

It verifies the four guest-frame markers, rejects helper `task.return` and
`async-lift` endpoints, attaches the pinned legacy metadata, and validates the
Component. The same source under v1 is rejected before WAT with
`UnsupportedP3AsyncComponent`, so it cannot silently route to this target.

The Wasmtime 47.0.2 / Rust 1.97.1 matrix is reproducible with:

```bash
WASM_TOOLS=/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools \
  bash examples/p3-runtime/test_rust_async_call_component.sh <component.wasm>
```

The measured modes are `ready` and `pending`: one host future completion and
one drop; `cancel`: one pending future drop, zero completion, no duplicate
drop, and an empty `ResourceTable`. Scheduler polling is intentionally not
asserted as an exact count.

Future widening may add the following internal modules:

- `codegen_component_async_call_plan.zig` for call-graph admission and frame
  states;
- `codegen_component_async_call.zig` for root/helper frame and continuation
  emission;
- a dedicated v2-style adapter or target dispatcher for the new opt-in flag;
- focused `check`, `compile_err`, Component, and Rust/Wasmtime fixtures.

It must not modify public ownership syntax, generic WIT type parsing, the v1
registry, the existing Generic ABI v2 profile, or ordinary Core async lowering
unless a separate design explicitly authorizes that change.

## Alternatives Rejected

### Whole-program inlining

Inlining the helper's source body into the root would pass a one-fixture test
but would not give the compiler a stable helper frame/state boundary for
parent continuation and cancellation. It would have to be replaced when
parameters, multiple children, or recursion are introduced.

### Reusing the Core generic emitter

The Core emitter's bounded markers do not establish Component `task.return`,
subtask cancellation, or resource-table cleanup. Reusing it would conflate
two different ABI contracts and could make a synchronous artifact look like a
Component async proof.

## Exit Criteria

This bounded design phase is complete for the admitted shape when:

1. the pinned hand-written probe passes or records an exact toolchain blocker;
2. the source positive and all negative fixtures are specified;
3. the ownership/cancellation invariants are executable in the runtime gate;
4. a separate implementation plan exists; and
5. v1, v2, public ownership syntax, arbitrary producer expressions, generic
   payloads, filesystem async, and D2 host I/O remain explicitly unchanged.

These criteria are met for the one no-parameter/nil helper shape. The broader
items remain explicit follow-up boundaries rather than implicit admissions.
