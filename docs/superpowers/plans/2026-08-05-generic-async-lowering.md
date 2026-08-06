# Generic Async Lowering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `AsyncLoweringUnavailable` for one verified colorless async
vertical slice: three `Future<nil>` values created by `@async`, two sequential
`@await` operations, and one separate terminal `@cancel`, with resumable frame
lowering and a Rust/Wasmtime runtime gate.

## Current Checkpoint (2026-08-06)

The implementation and verification are complete in the current working tree;
no commit or push was performed. The admitted shape is exactly:

```text
Future<nil> = @async(work())
@await(first)
Future<nil> = @async(work())
@await(second)
Future<nil> = @async(work())
@cancel(third)
```

Verified gates: focused Zig tests, compiler regression `pass=1095 fail=0
skip=3`, Wasm regression `pass=1097 fail=0 skip=3`, Core WAT parse, the
pending/immediate/cancel generic Component Rust gate, and ReleaseSmall smoke.

**Architecture:** Reuse the existing `codegen_async_model.zig` frame/lifecycle
types and the descriptor-specific async plan conventions, but add a separate
generic admission analyzer and emitter. The normal pipeline asks the generic
analyzer for an exact admitted plan; unsupported async shapes still fail with
`AsyncLoweringUnavailable` before WAT emission. Task 8 Step 3 runs first as a
runtime baseline and remains an independent release gate.

**Tech Stack:** Zig 0.16.0, existing Do parser/sema/codegen modules,
`wasm-tools 1.254.0`, the checked-in Rust host runner under
`examples/p3-runtime/rust-host-runner`, and the existing compiler/Wasm/release
regression harness.

## Global Constraints

- Canonical source operations remain `@async`, `@await`, and `@cancel`.
- The first generic admission is only an ordinary root function with three
  distinct `Future<nil>` values, two sequential awaits, and one separate
  terminal cancel.
- `async name(...) -> T` source declarations remain guarded in this phase.
- `Result<T,E>` payloads, `Stream<T>`, resources, callbacks, aggregate await,
  timeout, and arbitrary Future producers remain rejected.
- Public `own<T>`, `borrow<T>`, `ref<T>`, pointers, references, `funcref`, and
  rollback semantics are not introduced.
- Existing descriptor-specific Component emitters remain unchanged except for
  shared helper extraction proven by tests.
- Async lowering must never silently become synchronous WAT.
- Cancellation does not roll back external effects; terminal cleanup is
  exactly once.
- `.deps/wit-bindgen` remains a differential oracle and is not a production
  dependency of this phase.
- Every task ends with a focused test command before the next task begins.

---

### Task 1: Close the Task 8 Step 3 runtime baseline

**Files:**
- Create: `examples/p3-runtime/test_task8_step3_baseline.sh`
- Create: `doc/async-runtime-baseline-2026-08-05.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`

**Interfaces:**
- Consumes: the currently admitted scalar Result, resource Result,
  cancellation, stream, filesystem, and socket Component fixtures.
- Produces: a reproducible baseline report separating green admitted gates from
  pinned-toolchain or intentionally unsupported shapes.

- [x] **Step 1: Write the baseline runner.**

  Add an executable script that runs the existing gate entry points in a fixed
  order and prints one marker per gate. The script must stop on any gate
  failure; known pinned-toolchain limitations are recorded in the report from
  the observed stderr rather than converted into a pass:

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
  run_gate() {
      name=$1
      shift
      if "$@"; then
          printf 'baseline %s: PASS\n' "$name"
      else
          printf 'baseline %s: FAIL\n' "$name" >&2
          exit 1
      fi
  }
  run_gate cancel-wait-for bash "$repo_root/examples/p3-runtime/test_rust_cancel_wait_for.sh"
  run_gate scalar-result bash "$repo_root/examples/p3-runtime/test_rust_scalar_result.sh"
  run_gate resource-result bash "$repo_root/examples/p3-runtime/test_rust_async_resource_result.sh"
  run_gate stream-reader bash "$repo_root/examples/p3-runtime/test_rust_stream_reader_descriptor.sh"
  run_gate stream-writer bash "$repo_root/examples/p3-runtime/test_rust_stream_writer.sh"
  run_gate filesystem bash "$repo_root/examples/p3-runtime/test_rust_wasi_filesystem_preopen.sh"
  run_gate sockets bash "$repo_root/examples/p3-runtime/test_rust_wasi_sockets_real.sh"
  ```

  Do not add a second runtime implementation to make a gate pass.

- [x] **Step 2: Run the baseline before changing lowering.**

  Run:

  ```bash
  chmod +x examples/p3-runtime/test_task8_step3_baseline.sh
  examples/p3-runtime/test_task8_step3_baseline.sh
  ```

  Expected: every currently admitted gate prints `PASS`; any known external
  limitation is named with its existing diagnostic and does not get converted
  into a green result.

- [x] **Step 3: Record exact outputs and boundaries.**

  Write `doc/async-runtime-baseline-2026-08-05.md` with the command, tool
  versions, each gate marker, and a table containing `descriptor`, `result`,
  `evidence`, and `unblock condition`. State explicitly that this baseline is
  not generic async lowering.

- [x] **Step 4: Synchronize blocker documentation.**

  Update `doc/host_abi_blockers.md` and `doc/pending_blocked.md` only with the
  observed results. Keep `AsyncLoweringUnavailable` and the narrow unsigned
  task-return limitation documented if the pinned runtime still exhibits them.

- [x] **Step 5: Verify and commit the baseline.**

  Run:

  ```bash
  git diff --check
  examples/p3-runtime/test_task8_step3_baseline.sh
  git add examples/p3-runtime/test_task8_step3_baseline.sh \
    doc/async-runtime-baseline-2026-08-05.md doc/host_abi_blockers.md \
    doc/pending_blocked.md
  git commit -m "Record async runtime baseline"
  ```

### Task 2: Add exact generic async admission analysis

**Files:**
- Create: `src/build/codegen_generic_async_plan.zig`
- Create: `src/build/test/check/417_generic_async_single_future.do`
- Create: `src/build/test/compile_err/418_generic_async_payload_unavailable.do`
- Create: `src/build/test/compile_err/418_generic_async_payload_unavailable.expect`
- Create: `src/build/test/compile_err/419_generic_async_stream_unavailable.do`
- Create: `src/build/test/compile_err/419_generic_async_stream_unavailable.expect`
- Create: `src/build/test/compile_err/420_generic_async_multiple_await.do`
- Create: `src/build/test/compile_err/420_generic_async_multiple_await.expect`
- Create: `src/build/test/compile_err/421_generic_async_function_decl.do`
- Create: `src/build/test/compile_err/421_generic_async_function_decl.expect`

**Interfaces:**
- Consumes: parser tokens, `parser.Program`, and the existing module graph.
- Produces: `GenericAsyncPlan` or a named unsupported-shape error for the
  generic emitter.

  ```zig
  pub const GenericAsyncPlan = struct {
      root_name: []const u8,
      work_name: []const u8,
      await_future_name: []const u8,
      second_await_future_name: []const u8,
      cancel_future_name: []const u8,
      await_token_index: usize,
      second_await_token_index: usize,
      cancel_token_index: usize,
      pub fn deinit(self: *GenericAsyncPlan, allocator: std.mem.Allocator) void;
  };

  pub fn analyze(
      allocator: std.mem.Allocator,
      program: parser.Program,
      tokens: []const lexer.Token,
      module_graph: ?*const imports.ModuleGraph,
  ) !GenericAsyncPlan;
  ```

- [x] **Step 1: Write the admitted and rejected fixtures.**

  The admitted check fixture must contain exactly:

  ```do
  work() -> nil { return }
  run() -> nil {
      ready Future<nil> = @async(work())
      @await(ready)
      middle Future<nil> = @async(work())
      @await(middle)
      pending Future<nil> = @async(work())
      @cancel(pending)
  }
  start() { run() }
  ```

  The rejected fixtures must each isolate one reason: a payload Future, a
  Stream operation, three awaits, and an `async name(...) -> T` declaration.
  Their `.expect` files must each contain this single diagnostic substring:

  ```text
  AsyncLoweringUnavailable
  ```

- [x] **Step 2: Run the red unit and checker tests.**

  Add `test` blocks to `codegen_generic_async_plan.zig` for the exact admitted
  sequence and each rejection. Run:

  ```bash
  cd src
  zig test build/codegen_generic_async_plan.zig
  ../bin/do check build/test/check/417_generic_async_single_future.do
  ../bin/do build build/test/compile_err/418_generic_async_payload_unavailable.do -o /tmp/async-red.wat
  ```

  Expected: the new admission test fails because `analyze` does not exist yet;
  the compile-error fixtures retain their expected lowering guard.

- [x] **Step 3: Implement the smallest analyzer.**

  Parse only the top-level `run() -> nil` body. Require three distinct
  `Future<nil>` bindings produced by `@async(work())`, two bare sequential
  `@await(future)` operations, then one terminal `@cancel(future)` on the third
  future. Reject all other statements, payload types, nested functions, and
  additional async operations with
  `error.UnsupportedGenericAsyncShape`.

- [x] **Step 4: Verify the analyzer and source boundary.**

  Run:

  ```bash
  cd src
  zig test build/codegen_generic_async_plan.zig
  ../bin/do check build/test/check/417_generic_async_single_future.do
  ../bin/do check build/test/compile_err/418_generic_async_payload_unavailable.do
  ```

  Expected: the admitted fixture yields a stable plan; every rejection keeps a
  named error and no WAT is emitted.

- [x] **Step 5: Commit the admission boundary.**

  ```bash
  git add src/build/codegen_generic_async_plan.zig src/build/test/check/417_generic_async_single_future.do \
    src/build/test/compile_err/418_generic_async_payload_unavailable.do \
    src/build/test/compile_err/418_generic_async_payload_unavailable.expect \
    src/build/test/compile_err/419_generic_async_stream_unavailable.do \
    src/build/test/compile_err/419_generic_async_stream_unavailable.expect \
    src/build/test/compile_err/420_generic_async_multiple_await.do \
    src/build/test/compile_err/420_generic_async_multiple_await.expect \
    src/build/test/compile_err/421_generic_async_function_decl.do \
    src/build/test/compile_err/421_generic_async_function_decl.expect
  git commit -m "Admit the minimal generic async shape"
  ```

### Task 3: Model the generic frame lifecycle

**Files:**
- Create: `src/build/codegen_generic_async_frame.zig`
- Modify: `src/build/codegen_async_model.zig`
- Modify: `src/build/codegen_emit_async.zig`

**Interfaces:**
- Consumes: `GenericAsyncPlan` from Task 2 and existing `FrameModel` helpers.
- Produces: an immutable frame layout and checked lifecycle transitions.

  ```zig
  pub const GenericAsyncState = enum {
      created,
      running,
      suspended,
      ready,
      cancelled,
      terminal,
  };

  pub const GenericAsyncFrame = struct {
      state_offset: u32,
      future_offset: u32,
      terminal_offset: u32,
      size: u32,
      pub fn start(self: *GenericAsyncFrame) !void;
      pub fn suspend(self: *GenericAsyncFrame) !void;
      pub fn resume_ready(self: *GenericAsyncFrame) !void;
      pub fn cancel(self: *GenericAsyncFrame) !void;
      pub fn cleanup(self: *GenericAsyncFrame) !void;
  };
  ```

- [x] **Step 1: Add lifecycle tests before the implementation.**

  Test these transitions with `std.testing.expectError` for illegal edges:

  ```zig
  test "generic frame has one terminal cleanup" {
      var frame = try GenericAsyncFrame.init();
      try frame.start();
      try frame.suspend();
      try frame.resume_ready();
      try frame.cleanup();
      try std.testing.expectError(error.AsyncFrameAlreadyTerminal, frame.cleanup());
  }
  ```

  Also test `created -> running -> cancelled -> terminal`, rejecting cancel
  after terminal and rejecting resume after cancel.

- [x] **Step 2: Run the red frame tests.**

  ```bash
  cd src
  zig test build/codegen_generic_async_frame.zig
  ```

  Expected: compilation or the lifecycle assertion fails because the generic
  frame type and transitions are not implemented.

- [x] **Step 3: Implement the frame layout and guarded transitions.**

  Reuse the existing alignment rules from `codegen_async_model.zig`. Allocate
  state at offset 0, the Future owner slot at offset 4, the terminal flag at
  offset 8, and align the frame size to 8 bytes. Every terminal path must set
  the terminal flag before releasing the owner slot.

- [x] **Step 4: Verify model and shared cleanup output.**

  Run:

  ```bash
  cd src
  zig test build/codegen_generic_async_frame.zig
  zig test build/codegen_emit_async.zig
  ```

  Expected: lifecycle transitions pass and existing defer/frame cleanup tests
  remain green.

- [x] **Step 5: Commit the frame model.**

  ```bash
  git add src/build/codegen_generic_async_frame.zig src/build/codegen_async_model.zig src/build/codegen_emit_async.zig
  git commit -m "Add generic async frame lifecycle"
  ```

### Task 4: Emit the minimal resumable WAT state machine

**Files:**
- Create: `src/build/codegen_emit_generic_async.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/codegen_model.zig`
- Create: `src/build/test/compile_ok/417_generic_async_single_future.do`
- Create: `src/build/test/compile_ok/417_generic_async_single_future.expect`

**Interfaces:**
- Consumes: `GenericAsyncPlan` and `GenericAsyncFrame`.
- Produces: `emit_if_supported(...) !?[]u8`, returning WAT only for the exact
  admitted plan and `null` when no generic async operation exists.

  ```zig
  pub fn emit_if_supported(
      allocator: std.mem.Allocator,
      program: parser.Program,
      tokens: []const lexer.Token,
      module_graph: ?*const imports.ModuleGraph,
  ) !?[]u8;
  ```

- [x] **Step 1: Write the structural WAT test.**

  Add a unit test that feeds the Task 2 fixture to
  `emit_if_supported` and asserts the WAT contains exactly one frame
  allocation, two ordered suspend states, one ready resume branch, one cancel branch,
  and one terminal cleanup marker:

  ```zig
  try std.testing.expectEqual(@as(usize, 1), count(wat, "[generic-async-frame]"));
  try std.testing.expectEqual(@as(usize, 2), count(wat, "[generic-async-suspend]"));
  try std.testing.expectEqual(@as(usize, 1), count(wat, "[generic-async-cancel]"));
  try std.testing.expectEqual(@as(usize, 1), count(wat, "[generic-async-terminal]"));
  try std.testing.expectEqual(@as(usize, 3), count(wat, "call $work"));
  ```

  The checked-in `src/build/test/compile_ok/417_generic_async_single_future.expect`
  must contain exactly these required markers, one per line:

  ```text
  [generic-async-frame]
  [generic-async-suspend]
  [generic-async-cancel]
  [generic-async-terminal]
  ```

- [x] **Step 2: Run the red emitter test.**

  ```bash
  cd src
  zig test build/codegen_emit_generic_async.zig
  ```

  Expected: the emitter entry point is absent or returns no WAT for the
  admitted plan.

- [x] **Step 3: Implement the WAT state machine.**

  Emit a frame allocation and state 0 entry, call the synchronous `work`,
  store the Future owners, and branch through two ordered suspend states. The
  resume path loads each owner, performs both awaits in order, then starts the
  independent third Future and enters terminal cancellation. The cancel path
  calls the existing cancellation operation, clears the owner, and enters the
  same terminal cleanup. Emit metadata comments for state ids and
  frame offsets so tests can detect replayed work or duplicate cleanup.

- [x] **Step 4: Install the generic emitter before the fallback guard.**

  In `codegen_pipeline.emit_wat_with_options`, call
  `codegen_emit_generic_async.emit_if_supported` after the explicit
  descriptor-specific options and before `AsyncLoweringUnavailable`:

  ```zig
  if (try codegen_emit_generic_async.emit_if_supported(allocator, program, tokens, module_graph)) |wat| {
      return wat;
  }
  if (program_requires_async_lowering(program, tokens, module_graph)) {
      return error.AsyncLoweringUnavailable;
  }
  ```

  Keep all non-admitted shapes on the old error path.

- [x] **Step 5: Verify WAT and ordinary build.**

  ```bash
  cd src
  zig test build/codegen_emit_generic_async.zig
  zig test build/codegen_pipeline.zig
  cd ..
  ./bin/do build src/build/test/compile_ok/417_generic_async_single_future.do -o /tmp/generic-async-single.wat
  wasm-tools parse /tmp/generic-async-single.wat -o /tmp/generic-async-single.wasm
  ```

  Expected: the admitted fixture emits valid WAT; payload, stream, multiple
  await, and async-declaration fixtures still fail with
  `AsyncLoweringUnavailable`.

- [x] **Step 6: Commit the emitter integration.**

  ```bash
  git add src/build/codegen_emit_generic_async.zig src/build/codegen_pipeline.zig \
    src/build/codegen_model.zig src/build/test/compile_ok/417_generic_async_single_future.do \
    src/build/test/compile_ok/417_generic_async_single_future.expect
  git commit -m "Lower the minimal generic async state machine"
  ```

### Task 5: Add the component metadata and host-drive contract

**Files:**
- Create: `examples/p3-runtime/generic-async-single-future.wit`
- Create: `examples/p3-runtime/generic-async-single-future.do`
- Create: `examples/p3-runtime/test_do_generic_async_lowering.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/generic_async_single_future.rs`
- Modify: `src/build/wat_component_metadata.zig`
- Modify: `src/build/codegen_component_async_plan.zig`
- Modify: `src/build/codegen_component_async.zig`

**Interfaces:**
- Consumes: the generic WAT and frame markers from Task 4.
- Produces: a test-only component world and Rust host runner that drive
  pending, immediately-ready, and cancelled terminal paths.

- [x] **Step 1: Write the WIT and Rust red probe.**

  Define the test-only world with one synchronous host operation and one async
  root export:

  ```wit
  package do:generic-async-probe@0.1.0;

  interface host {
    work: func();
  }

  world probe {
    import host;
    export run: async func();
  }
  ```

  The Do source fixture must be:

  ```do
  work = @host("do:generic-async-probe/host@0.1.0", "work", () -> nil)

  run() -> nil {
      ready Future<nil> = @async(work())
      @await(ready)
      middle Future<nil> = @async(work())
      @await(middle)
      pending Future<nil> = @async(work())
      @cancel(pending)
  }

  start() {}
  ```

  The Rust binary must accept a component path and an optional
  `DO_GENERIC_ASYNC_IMMEDIATE=1` switch, and must fail until the generated
  component exports the expected async lift/callback and task-return symbols.

- [x] **Step 2: Run the red probe.**

  ```bash
  bash examples/p3-runtime/test_do_generic_async_lowering.sh
  ```

  Expected: the script fails because the generic emitter does not yet produce
  the component metadata or host-drive entry points.

- [x] **Step 3: Emit the minimal component metadata.**

  Reuse the established async names (`[async-lift]`, callback async-lift,
  `[task-return]`, subtask cancel/drop) and the existing component metadata
  writer. Add `Target.generic_async` to
  `codegen_component_async_plan.zig`/`codegen_component_async.zig` and route it
  only when `GenericAsyncPlan.analyze` accepts the exact source shape. Do not
  add a new cancellation result or operation id. The generated WIT must
  describe only the unit operation and must be stable byte-for-byte.

- [x] **Step 4: Implement the Rust host assertions.**

  The runner must assert:

  ```text
  pending: two external wakes, two completions, one terminal cleanup
  immediate: zero external wakes, three completions, one terminal cleanup
  cancel: the third Future is cancelled after two completions
  ```

  It must return non-zero on duplicate callback, duplicate drop, or a
  cancellation that reports a completed task twice.

- [x] **Step 5: Verify all three runtime paths.**

  ```bash
  tmp_dir=$(mktemp -d /tmp/do-generic-async.XXXXXX)
  trap 'rm -rf "$tmp_dir"' EXIT
  ./bin/do build examples/p3-runtime/generic-async-single-future.do \
    --p3-async-component --p3-wit-output "$tmp_dir/generic.wit" \
    -o "$tmp_dir/generic.wat"
  wasm-tools parse "$tmp_dir/generic.wat" -o "$tmp_dir/generic.core.wasm"
  wasm-tools component embed "$tmp_dir/generic.wit" "$tmp_dir/generic.core.wasm" \
    --world probe -o "$tmp_dir/generic.embedded.wasm"
  wasm-tools component new "$tmp_dir/generic.embedded.wasm" \
    -o "$tmp_dir/generic.component.wasm"
  wasm-tools validate --features cm-async,cm-more-async-builtins "$tmp_dir/generic.component.wasm"
  bash examples/p3-runtime/test_do_generic_async_lowering.sh
  DO_GENERIC_ASYNC_IMMEDIATE=1 bash examples/p3-runtime/test_do_generic_async_lowering.sh
  cargo test --locked --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml
  ```

  Expected: pending, immediate, and cancel markers pass; the runner does not
  claim rollback of an external effect.

- [x] **Step 6: Commit the generic runtime gate.**

  ```bash
  git add examples/p3-runtime/generic-async-single-future.wit \
    examples/p3-runtime/generic-async-single-future.do \
    examples/p3-runtime/test_do_generic_async_lowering.sh \
    examples/p3-runtime/rust-host-runner/Cargo.toml \
    examples/p3-runtime/rust-host-runner/src/bin/generic_async_single_future.rs \
    src/build/wat_component_metadata.zig src/build/codegen_component_async.zig
  git commit -m "Add generic async pending ready cancel gate"
  ```

### Task 6: Preserve negative boundaries and regression coverage

**Files:**
- Modify: `src/build/test/run_tests.sh`
- Modify: `src/build/diag.zig`
- Modify: `doc/async-design.md`
- Modify: `doc/spec_rules.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `docs/superpowers/plans/2026-08-05-generic-async-lowering.md`

**Interfaces:**
- Consumes: the admitted generic fixture and runtime gate from Tasks 2-5.
- Produces: an explicit language/compiler contract with all unsupported async
  shapes still rejected.

- [x] **Step 1: Add negative regression assertions.**

  Keep the existing `AsyncLoweringUnavailable` expectations for payload
  Future, Stream, resource, aggregate await, imported async, and async
  function declaration fixtures. Add the four Task 2 fixtures to the normal
  compile-error matrix and assert the diagnostic name, not a free-form text
  message.

- [x] **Step 2: Update diagnostics and specification.**

  Document that the exact colorless three-Future shape is admitted, while the
  generic fallback remains `AsyncLoweringUnavailable`. State that cancel does
  not roll back external effects and that terminal cleanup is exactly once.
  Do not document the vertical slice as complete WIT async or full P3.

- [x] **Step 3: Run focused and full tests.**

  ```bash
  cd src
  zig test build/codegen_generic_async_plan.zig
  zig test build/codegen_generic_async_frame.zig
  zig test build/codegen_emit_generic_async.zig
  zig test build/codegen_pipeline.zig
  cd ..
  bash examples/p3-runtime/test_do_generic_async_lowering.sh
  ./src/build/test/run_tests.sh
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  ```

  Expected: the admitted fixture passes, every non-admitted fixture retains its
  guard, and ordinary/Wasm/release matrices remain green.

- [x] **Step 4: Record the phase boundary.**

  Update the blocker docs with the exact admitted shape, frame offsets,
  pending/ready/cancel markers, pinned tool versions, and the remaining
  non-goals: Result payloads, Stream scheduling, resources, public ownership
  syntax, and arbitrary async function lowering.

- [x] **Step 5: Commit the phase closeout.**

  ```bash
  git add src/build/test/run_tests.sh src/build/diag.zig doc/async-design.md \
    doc/spec_rules.md doc/host_abi_blockers.md doc/pending_blocked.md \
    docs/superpowers/plans/2026-08-05-generic-async-lowering.md
  git commit -m "Close generic async lowering vertical slice"
  ```

## Verification Matrix

| Gate | Command | Required result |
| --- | --- | --- |
| Runtime baseline | `examples/p3-runtime/test_task8_step3_baseline.sh` | Existing admitted gates are reproduced and classified |
| Admission | `cd src && zig test build/codegen_generic_async_plan.zig` | Exact shape accepted; other shapes rejected |
| Frame | `cd src && zig test build/codegen_generic_async_frame.zig` | Illegal transitions rejected; cleanup once |
| Emitter | `cd src && zig test build/codegen_emit_generic_async.zig` | Stable state/frame/cancel markers |
| WAT | `wasm-tools parse /tmp/generic-async-single.wat` | Valid binary |
| Runtime | `bash examples/p3-runtime/test_do_generic_async_lowering.sh` | Pending/ready/cancel all pass |
| Regression | `./src/build/test/run_tests.sh` | 0 failures |
| Wasm regression | `RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh` | 0 failures |
| Release | `./src/build/test/run_release_smoke.sh` | Pass |

The phase is complete only when every required result above is observed and
the remaining capability limits are recorded. Passing the generic gate does
not claim full WIT async, full WASI, Component GC, or public ownership syntax.
