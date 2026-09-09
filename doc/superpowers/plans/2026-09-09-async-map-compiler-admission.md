# Async Map Compiler Admission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Goal:** Add a private opt-in compiler route for the exact `HashMap<u32,u32>` async host shape while keeping generic async/map lowering fail-closed.

**Status:** implementation and verification complete

**Architecture:** A token-exact plan validates one pinned registry descriptor and one fixture topology. A fixed canonical WAT/WIT emitter consumes only that plan; CLI and harness wiring expose the route without changing default GC compilation. The existing Rust/Wasmtime async-map capability runner is reused for lifecycle evidence.

**Tech Stack:** Zig 0.16 compiler, WAT, WIT, current `wasm-tools`/Wasmtime adapter, Rust host runner.

**Spec:** `doc/superpowers/specs/2026-09-09-async-map-compiler-admission-design.md`

## Global Constraints

- Normal compilation remains Wasm GC-only; ARC is test-only.
- Only `--p3-async-map-component` admits this route.
- The descriptor, WIT hash, Core signature, two pair values, and cleanup order are pinned.
- Generic maps, Stream buffers, arbitrary producers, and public ownership/reference syntax remain rejected.
- Preserve all existing worktree changes and do not push.

### Task 1: Lock RED source and analyzer contract

**Files:**
- Modify: `examples/p3-runtime/async-map-component.do`
- Create: `src/build/codegen_component_async_map_plan_test.zig`

**Interfaces:**
- The fixture is the one positive source contract from the spec.
- The focused test will call `analyze` and expect `UnsupportedP3AsyncMapComponent` until the plan exists.

- [x] **Step 1: Write the positive fixture**

  The fixture constructs `[7,70]` and `[9,90]`, calls `submit(HashMap<u32,u32>)`, and awaits `u32` through helper and root.

- [x] **Step 2: Add the RED analyzer test**

  Embed a minimal matching source and assert:

  ```zig
  const tokens = try lexer.tokenize(std.testing.allocator, source);
  defer std.testing.allocator.free(tokens);
  try std.testing.expectError(error.UnsupportedP3AsyncMapComponent, plan.analyze(std.testing.allocator, tokens));
  ```

- [x] **Step 3: Run the focused test**

  Run `zig test src/build/codegen_component_async_map_plan_test.zig`.

  Expected: compile/test failure because the plan module and analyzer error are not implemented.

### Task 2: Add the pinned descriptor and strict plan/emitter

**Files:**
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/p3_async_manifest.zig`
- Create: `src/build/codegen_component_async_map_plan.zig`
- Create: `src/build/codegen_component_async_map.zig`
- Create: `src/build/async_map_component_template.wat`
- Modify: `src/build/codegen_component_async_map_plan_test.zig`

**Interfaces:**
- `pub fn analyze(allocator, tokens) !AsyncMapPlan` returns only the pinned source facts.
- `pub fn emit_component_wat(allocator, plan) ![]u8` emits the measured template.
- `pub fn emit_component_wit(allocator) ![]u8` emits the pinned WIT.

- [x] **Step 1: Add the registry row and manifest validation**

  Accept effect `async-map-u32-u32` only when every descriptor, canonical, and WIT field equals the spec, including the checked-in hash.

- [x] **Step 2: Implement strict source inspection**

  Require the exact host binding, `HashMap<u32,u32>` helper parameter, `Future<u32>` host await, two literal `hash_put` calls, one root `@async(helper(values))`, one root await, and no extra top-level declarations/operations.

- [x] **Step 3: Emit the fixed template**

  Reuse the measured `(ptr,len,result_area) -> i32` import, two-entry copy, post-call overwrite, result-area load, callback, cancel/drop, context clear, and frame-free markers. Reject a plan whose descriptor does not match the pinned shape.

- [x] **Step 4: Turn the test GREEN**

  Assert the positive plan facts and add negative sources for wrong value type, dynamic map construction, extra pair, `@host_func`, and a second await. Run `zig test src/build/codegen_component_async_map_plan_test.zig` and expect all tests to pass.

### Task 3: Wire the private target through compiler APIs

**Files:**
- Modify: `src/build/codegen_model.zig`
- Modify: `src/build/codegen_runtime_api.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/codegen_api.zig`
- Modify: `src/build/cli.zig`
- Modify: `src/build/run.zig`
- Modify: `src/main.zig`
- Modify: `src/build/diag.zig`

**Interfaces:**
- `EmitOptions.p3_async_map_component: bool` selects the route.
- CLI parses `--p3-async-map-component` and enforces target exclusivity.
- `run.zig` forwards the flag and writes the plan's WIT sidecar.

- [x] **Step 1: Add option/CLI fields and guard combinations**

  Include the flag in the special-target count, `--p3-wit-output` requirement, usage text, and mutual-exclusion tests.

- [x] **Step 2: Dispatch before generic async lowering**

  Analyze the tokens, map `UnsupportedP3AsyncMapComponent` to the stable diagnostic, and emit only the fixed route.

- [x] **Step 3: Add API/WIT exports and diagnostics**

  Export `emit_p3_async_map_component_wit`, add the user-facing hint, and keep default build errors unchanged.

- [x] **Step 4: Run compiler checks**

  Build the compiler and run CLI/API focused tests; the positive flag must emit WAT/WIT and the default invocation must fail with `AsyncLoweringUnavailable`.

### Task 4: Add Component and lifecycle gates

**Files:**
- Modify: `src/build/test/test_cases.zig`
- Modify: `src/build/test/test_harness.zig`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/pending_blocked.md`

**Interfaces:**
- The pure-lowering matrix compiles the positive Do fixture with the new flag.
- The route validates current Core/Component assembly and reuses `do-p3-async-map-capability-host-runner` for ready/pending/cancel/drop.

- [x] **Step 1: Add the positive matrix case**

  Compare generated WIT/WAT to the checked-in capability snapshots and require the copy/overwrite/result/cleanup markers.

- [x] **Step 2: Add negative command checks**

  Invoke the new flag for each negative source and require `UnsupportedP3AsyncMapComponent` before any WAT artifact is accepted.

- [x] **Step 3: Run the focused harness**

  Run `./src/build/test/run_tests.sh` with the current toolchain and verify the new case reaches the four-mode Rust gate.

- [x] **Step 4: Synchronize status docs**

  Record compiler admission separately from runtime capability; keep generic async map, Stream, and ownership rows pending.

### Task 5: Full verification and handoff

**Files:**
- Test: `src/build/codegen_component_async_map_plan_test.zig`
- Test: `src/build/test/run_tests.sh`
- Test: `examples/p3-runtime/test_async_map_capability.sh`

**Interfaces:**
- No new public API beyond the explicit private CLI target.

- [x] **Step 1: Run focused and full verification**

  Run `zig test src/build/codegen_component_async_map_plan_test.zig`, `cd src && zig build -Doptimize=ReleaseSmall`, `./src/build/test/run_tests.sh`, `RUN_WASM=1 RUN_GC_CORE=1 ./src/build/test/run_tests.sh`, and `bash examples/p3-runtime/test_async_map_capability.sh`.

- [x] **Step 2: Inspect scoped diff**

  Run `git diff --check` and inspect only the new route plus explicitly touched docs/API files; preserve all unrelated existing changes.

- [x] **Step 3: Report evidence and residual blockers**

  Report exact pass counts, the default rejection, and that generic async-map lowering remains pending. Do not push.
