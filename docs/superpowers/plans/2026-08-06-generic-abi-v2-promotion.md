# Generic ABI v2 Promotion Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** expose exactly the verified variant-resource-stream and generated
`Future<i64>` Generic ABI v2 shapes through one deliberate Component runtime
profile, without changing the v1 default path.

**Architecture:** Add a mutually exclusive `--p3-async-component-v2` target
that flows through CLI parsing, `EmitOptions`, and a separate v2 component
dispatcher. The dispatcher recognizes only the two already-probed identities
and invokes their independent adapters. Every other target fails before WAT
emission; the existing `--p3-async-component` dispatcher is unchanged.

**Tech Stack:** Zig 0.16.0, Do compiler CLI/codegen, existing pinned WIT
registry and generated manifests, `wasm-tools 1.254.0`, Rust 1.97.1, Wasmtime
47.0.2, existing Bash runtime gates.

## Global Constraints

- Preserve the default `--p3-async-component` v1 dispatcher byte-for-byte in
  behavior and do not make v2 the default.
- Admit only `do:variant-resource-stream-canonical@0.1.0/read-via-stream` and
  the generated `do:generic-async-scalar-i64-probe@0.1.0/host.completion`
  `Future<i64>` shape with `offset=16`, `byte_size=8`, `alignment=8`,
  `core-s64`.
- Reject scalar-u32, unit, HTTP, filesystem, producer, list, text, resource,
  generic payload, public ownership syntax, and every unmeasured shape before
  WAT emission.
- Keep legacy `--p3-async-v2-scalar-i64` working as a single-shape compatibility
  target; it and the new profile must render identical scalar-i64 WAT.
- Do not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax; do not change
  nested borrowed stream/future rejection.
- Use existing local deterministic Rust/Wasmtime runners only; no network test.
- Preserve all current dirty worktree changes and do not stage, commit, reset,
  clean, or push during this plan.

The red-only pre-implementation steps below were not replayed after resuming
this dirty worktree because the target plumbing and adapters were already
present. No implementation was reverted to recreate those failures; current
green focused tests and the Component/Rust/Wasmtime gates are the authoritative
evidence for the implemented behavior.

---

### Task 1: Add a mutually exclusive v2 Component profile

**Files:**
- Modify: `src/build/cli.zig`
- Modify: `src/build/run.zig`
- Modify: `src/build/codegen_model.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/main.zig`
- Test: CLI parser unit tests in `src/build/cli.zig`

**Interfaces:**
- Produces `Args.p3_async_component_v2: bool` and
  `EmitOptions.p3_async_component_v2: bool`.
- `--p3-async-component-v2` is a special target eligible for
  `--p3-wit-output`; it cannot coexist with any other special target,
  `--component-core`, or `--host-export`.
- `codegen_pipeline.emit_wat_with_options` calls the distinct v2 dispatcher
  only when `p3_async_component_v2` is true.

- [x] **Step 1: Write failing CLI parser tests.**

  Add these exact tests in `src/build/cli.zig`:

  ```zig
  test "parse_build accepts the Generic ABI v2 Component profile" {
      const args = [_][]const u8{ "build", "app.do", "--p3-async-component-v2", "--p3-wit-output", "app.wit" };
      const parsed = try parse_build(&args);
      try std.testing.expect(parsed.p3_async_component_v2);
      try std.testing.expectEqualStrings("app.wit", parsed.p3_wit_output_path.?);
  }

  test "parse_build rejects a v2 Component profile combined with v1" {
      const args = [_][]const u8{ "build", "app.do", "--p3-async-component-v2", "--p3-async-component" };
      try std.testing.expectError(error.UnexpectedCliArg, parse_build(&args));
  }
  ```

- [ ] **Step 2: Run the focused parser test and confirm red.**

  Run:

  ```bash
  cd src && zig test build/cli.zig --test-filter 'Generic ABI v2 Component profile'
  ```

  Expected: compilation fails because `p3_async_component_v2` and the new flag
  do not exist.

- [x] **Step 3: Implement the smallest target plumbing.**

  Add the boolean to CLI args, parse the exact flag, include it in the P3
  special-target count and WIT sidecar eligibility, and thread it through
  `run.zig` and `EmitOptions`. Extend the usage line in `src/main.zig`. In
  `emit_wat_with_options`, call `codegen_component_async.emit_component_wat_v2`
  before the existing v1 `p3_async_component` branch. Do not modify the v1
  branch.

- [x] **Step 4: Run focused parser and pipeline tests.**

  Run:

  ```bash
  cd src && zig test build/cli.zig
  cd src && zig test build/codegen_pipeline.zig
  ```

  Expected: parser accepts the profile, mixed targets remain rejected, and the
  pipeline compiles with the new option but has no newly admitted WAT shape.

### Task 2: Implement fail-closed v2 adapter dispatch

**Files:**
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/diag.zig`
- Test: unit tests in `src/build/codegen_component_async.zig`

**Interfaces:**
- Add:

  ```zig
  pub fn emit_component_wat_v2(
      allocator: std.mem.Allocator,
      program: parser.Program,
      tokens: []const lexer.Token,
      module_graph: ?*const imports.ModuleGraph,
  ) ![]u8
  ```

- It returns finalized Component WAT only for `Target.variant_resource_stream`
  or the exact scalar-i64 generated lowering. It maps all other targets and
  scalar adapter rejection to `error.UnsupportedGenericAbiV2Promotion`.
- Add the named diagnostic `UnsupportedGenericAbiV2Promotion`; it must say the
  profile admits only the two pinned v2 private shapes.

- [x] **Step 1: Write failing dispatch tests.**

  Add tests that construct the existing exact variant source and scalar-i64
  graph, then assert `emit_component_wat_v2` contains respectively:

  ```text
  generic ABI v2 independent variant-resource-stream emitter template
  generic ABI v2 independent scalar-i64 emitter template
  ```

  Add separate tests using the existing scalar-u32 fixture/graph and an exact
  v1 `Future<nil>` source; both must return
  `error.UnsupportedGenericAbiV2Promotion`. Finally call the default
  `emit_component_wat` for the variant source and assert it does not contain
  the v2 variant template marker.

- [ ] **Step 2: Run the focused dispatch tests and confirm red.**

  Run:

  ```bash
  cd src && zig test build/codegen_component_async.zig --test-filter 'v2 promotion'
  ```

  Expected: compilation fails because `emit_component_wat_v2` and its diagnostic
  do not exist.

- [x] **Step 3: Implement exact selection without v1 fallback.**

  Use `target_for_tokens_with_graph` only to select a route. For the variant
  route, load the existing registry, invoke `codegen_component_async_v2_adapter`,
  and finalize its artifact. For the generated-scalar route, invoke
  `codegen_component_async_v2_scalar_adapter`; map all mismatch errors to the
  promotion diagnostic. Any other `Target`, missing graph, or adapter error
  fails closed. Do not call `emit_component_wat` from the v2 dispatcher.

- [x] **Step 4: Run adapter, dispatcher, and diagnostic tests.**

  Run:

  ```bash
  cd src && zig test build/codegen_component_async_v2_adapter.zig
  cd src && zig test build/codegen_component_async.zig
  cd src && zig test build/diag.zig
  ```

  Expected: both exact adapters emit their own templates, scalar-u32 and v1
  unit shapes fail before WAT, and default v1 dispatch remains unchanged.

### Task 3: Exercise the profile through Component/Rust/Wasmtime gates

**Files:**
- Modify: `src/build/run.zig`
- Modify: `examples/p3-runtime/test_do_variant_resource_stream_lowering.sh`
- Modify: `examples/wit-bindgen-do/test_generic_abi_v2_scalar_i64.sh`
- Create: `examples/p3-runtime/test_generic_abi_v2_promotion.sh`
- Test: `examples/wit-bindgen-do/test_generated_async_scalar_lowering.sh`

**Interfaces:**
- Existing variant and scalar-i64 scripts accept an optional target flag through
  a shell variable, defaulting to their current flags.
- The new promotion script calls those gates with
  `--p3-async-component-v2`, verifies both runtime matrices, and verifies a
  generated scalar-u32 input leaves no WAT output and reports the named v2
  promotion diagnostic.

- [x] **Step 1: Add the promotion gate before shell changes.**

  Create `examples/p3-runtime/test_generic_abi_v2_promotion.sh` that invokes:

  ```bash
  DO_P3_ASYNC_COMPONENT_TARGET=--p3-async-component-v2 \
    bash examples/p3-runtime/test_do_variant_resource_stream_lowering.sh
  DO_GENERIC_ABI_V2_SCALAR_TARGET=--p3-async-component-v2 \
    bash examples/wit-bindgen-do/test_generic_abi_v2_scalar_i64.sh
  ```

  Add a temporary generated scalar-u32 binding/caller, invoke the new profile,
  assert the command fails, assert the output WAT is absent, and match
  `UnsupportedGenericAbiV2Promotion`.

- [ ] **Step 2: Run the new gate and confirm red.**

  Run:

  ```bash
  bash examples/p3-runtime/test_generic_abi_v2_promotion.sh
  ```

  Expected: the CLI rejects the unknown profile until Task 1 exists.

- [x] **Step 3: Parameterize only the existing build flags.**

  In the variant script, set
  `component_target=${DO_P3_ASYNC_COMPONENT_TARGET:---p3-async-component}`
  and use it only in the `do build` command. In the scalar-i64 script, set
  `scalar_target=${DO_GENERIC_ABI_V2_SCALAR_TARGET:---p3-async-v2-scalar-i64}`
  and use it for both normal and manifest-mutation builds. Retain current
  defaults and all existing WAT/component/Rust assertions. In `run.zig`, route
  the new profile through `emit_p3_async_component_wit`.

- [x] **Step 4: Run all three runtime gates.**

  Run:

  ```bash
  bash examples/p3-runtime/test_do_variant_resource_stream_lowering.sh
  bash examples/wit-bindgen-do/test_generic_abi_v2_scalar_i64.sh
  bash examples/p3-runtime/test_generic_abi_v2_promotion.sh
  ```

  Expected: default scripts remain green; the new profile proves the same
  Component assembly and Rust/Wasmtime cleanup matrices for both shapes;
  scalar-u32 fails closed before WAT.

### Task 4: Record promotion truthfully and run the regression matrix

**Files:**
- Modify: `docs/superpowers/plans/2026-08-05-generic-wit-component-abi-v2.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`

**Interfaces:**
- Mark only the registry/runtime promotion checkpoint complete.
- Preserve open entries for nested borrowed stream/future reevaluation and
  generic producer/payload expansion.

- [x] **Step 1: Update the status documents from observed results only.**

  Add the profile command to `doc/start_here.md`; state that v1 remains the
  default and the profile covers exactly two private shapes. Update the v2 plan
  post-review checklist only after Task 3 is green. Keep the generic payload
  and borrow boundaries unchecked.

- [x] **Step 2: Run focused and full verification.**

  Run:

  ```bash
  cd src && zig test main.zig
  cd .. && ./src/build/test/run_tests.sh
  cd .. && RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  cd .. && ./src/build/test/run_release_smoke.sh
  git diff --check
  ```

  Expected: all repository regressions remain green. If the system Node runner
  fails as previously observed, rerun through the established Bun-compatible
  PATH shim and report that environment limitation separately.

- [x] **Step 3: Update the execution plan checkboxes.**

  Mark each completed step only after its command passed. Do not mark borrowed
  stream/future or generic producer/payload work complete.
