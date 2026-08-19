# Component Async Function Plan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed clocks token patterns with one descriptor-driven plan for the verified Component async subset, then make the existing emitters consume it.

**Architecture:** `codegen_component_async_plan.zig` owns source-shape validation and produces an ordered operation list plus the shared `AsyncFunctionPlan`. The clocks/unit emitter uses that plan without changing its pinned ABI strings; unsupported control flow, payload layouts, WIT worlds, and descriptors remain explicit errors. The resource Result probe stays on its existing emitter until its canonical payload representation can be made part of the same model.

**Tech Stack:** Zig compiler, existing lexer/function collector, `p3_async_manifest.Registry`, Wasm GC frame table, WAT and Component assembly regression scripts.

## Global Constraints

- Keep source `ref<T>`, `own<T>`, and `borrow<T>` absent; resource ownership remains an internal sema/ABI concern.
- Keep ordinary `do build` async rejection until general lowering is verified.
- Preserve the direct Component cancellation contract: wait for the ABI terminal state and do not claim rollback of external effects.
- Do not accept real HTTP, list, Stream, branch, or loop lowering in this phase.
- Use failing tests before production code and run the repository standard regression entrypoint before completion.

---

### Task 1: Shared Component Async Plan

**Files:**
- Create: `src/build/codegen_component_async_plan.zig`
- Modify: `src/build/codegen_p3_wait_for.zig`

**Interfaces:**
- Produces `ComponentAsyncFunctionPlan.analyze(allocator, tokens, registry)`.
- The result owns `async_model.AsyncFunctionPlan`, an ordered `operations` slice, and a terminal action of `.await` or `.cancel`.
- `deinit` releases every owned plan allocation.

- [x] **Step 1: Write failing plan tests**

```zig
const plan = try component_plan.ComponentAsyncFunctionPlan.analyze(
    std.testing.allocator, tokens, registry,
);
defer plan.deinit(std.testing.allocator);
try std.testing.expectEqual(@as(usize, 3), plan.operations.len);
try std.testing.expectEqual(component_plan.TerminalAction.await, plan.terminal);
```

- [x] **Step 2: Verify red state**

Run: `cd src && zig test build/codegen_component_async_plan.zig`

Expected: fail because the module and `ComponentAsyncFunctionPlan` do not exist.

- [x] **Step 3: Implement parsing and ownership**

```zig
pub const ComponentAsyncFunctionPlan = struct {
    export_name: []const u8,
    parameter: Parameter,
    operations: []Operation,
    terminal: TerminalAction,
    async_plan: async_model.AsyncFunctionPlan,

    pub fn analyze(...) !ComponentAsyncFunctionPlan { ... }
    pub fn deinit(self: *ComponentAsyncFunctionPlan, allocator: std.mem.Allocator) void { ... }
};
```

Only append an operation when its host binding resolves through the registry, its parameter storage matches the function parameter, and it shares the first operation's WIT package/interface/world.

- [x] **Step 4: Verify green**

Run: `cd src && zig test build/codegen_component_async_plan.zig`

Expected: all plan tests pass, including rejection of a descriptor from another world.

### Task 2: Migrate Verified Scalar/Unit Emitter

**Files:**
- Modify: `src/build/codegen_p3_wait_for.zig`
- Test: existing tests in `src/build/codegen_p3_wait_for.zig`

**Interfaces:**
- Consumes `ComponentAsyncFunctionPlan` from Task 1.
- Keeps WIT sidecar generation and the existing single/two-await WAT artifacts unchanged for their accepted inputs.

- [x] **Step 1: Write a failing emitter migration test**

```zig
const wat = try emit_component_wat(...);
defer std.testing.allocator.free(wat);
try std.testing.expect(std.mem.indexOf(u8, wat, "[async-state] 2") != null);
```

- [x] **Step 2: Verify red state**

Run: `cd src && zig test build/codegen_p3_wait_for.zig --test-filter 'uses the shared Component async plan'`

Expected: fail before the emitter is routed through the shared plan.

- [x] **Step 3: Replace private analysis**

```zig
var plan = try component_plan.ComponentAsyncFunctionPlan.analyze(allocator, tokens, registry);
defer plan.deinit(allocator);
return emit_component_core_wat(allocator, plan);
```

Retain the pinned WAT templates for one await, cancellation, and two awaits while deriving descriptor and frame data exclusively from `plan`.

- [x] **Step 4: Verify green**

Run: `cd src && zig test build/codegen_p3_wait_for.zig && cd .. && bash examples/p3-runtime/test_do_wait_for_lowering.sh && bash examples/p3-runtime/test_do_two_await_lowering.sh && bash examples/p3-runtime/test_do_cancel_wait_for_lowering.sh`

Expected: all focused tests and Component assembly/runtime probes pass.

### Task 3: General Sequential Scalar/Unit State Dispatch

**Files:**
- Modify: `src/build/codegen_p3_wait_for.zig`
- Test: `src/build/codegen_p3_wait_for.zig` and `examples/p3-runtime/`

**Interfaces:**
- Consumes `plan.operations` of arbitrary non-zero length.
- Produces one resume state per awaited operation and a single terminal cleanup path.

- [x] **Step 1: Write a failing three-await source test**

```zig
try std.testing.expect(std.mem.indexOf(u8, wat, "[async-state] 3") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "call $third-host-call") != null);
```

- [x] **Step 2: Verify red state**

Run: `cd src && zig test build/codegen_p3_wait_for.zig --test-filter 'three sequential awaits'`

Expected: fail with `UnsupportedP3WaitForComponent`.

- [x] **Step 3: Emit indexed state dispatch**

Generate imports and callback state branches from `plan.operations`; use the shared frame layout and emit exactly one terminal cleanup sequence. Keep the former templates only if the generated output is byte-for-byte equivalent for existing fixtures.

- [x] **Step 4: Verify green**

Run: focused Zig test, relevant Component assembly test, then `./src/build/test/run_tests.sh`.

Expected: new three-await behavior passes; unsupported control flow still returns a lowering diagnostic.

### Task 4: Resource Result Migration and Boundary Audit

**Files:**
- Modify: `src/build/codegen_component_resource_async.zig`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `doc/host_abi_blockers.md`

**Interfaces:**
- Adds a resource Result operation adapter only after its two-word completion fields have an explicit representation in the shared plan.
- Leaves real `wasi:http/client.send` rejected until canonical request/completion lowering is validated.

- [x] **Step 1: Write a failing resource-plan test**

```zig
try std.testing.expectEqual(component_plan.PayloadShape.resource_result_2word,
    plan.operations[0].payload_shape);
```

- [x] **Step 2: Verify red state**

Run: `cd src && zig test build/codegen_component_async_plan.zig --test-filter 'resource Result payload shape'`

Expected: fail because the shared plan has no resource payload representation.

- [x] **Step 3: Implement and validate only the private probe**

Extend the plan and resource emitter with the two registered i32 completion values. Do not infer an HTTP layout from the private probe.

- [x] **Step 4: Verify green and boundaries**

Run: `cd src && zig test build/codegen_component_async.zig && cd .. && bash examples/p3-runtime/test_do_async_resource_result.sh && bash examples/p3-runtime/test_rust_async_resource_result.sh`

Expected: resource probe passes; the HTTP fixture continues to return `UnsupportedP3AsyncComponent`.
