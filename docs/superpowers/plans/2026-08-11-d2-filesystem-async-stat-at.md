# D2 descriptor.stat-at Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a private opt-in `descriptor.stat-at` Component async slice with pinned ABI, exact Do source admission, generated Component validation, and Rust/Wasmtime cleanup coverage.

**Architecture:** Keep `descriptor.stat-at` as a separate registry lowering shape, sema signature predicate, planner/emitter module, and fixed WAT/WIT templates. Reuse only the already measured `descriptor.stat` record layout and `metadata-hash-at` path ownership pattern; do not widen either existing target.

**Tech Stack:** Zig compiler and unit tests, Do compile fixtures, WIT/Core WAT, `wasm-tools 1.255.0`, Rust 1.97.1, Wasmtime 47.0.2, and the existing `src/build/test/run_tests.sh` harness.

## Global Constraints

- Pin `wasm-tools 1.255.0 (76e20611d 2026-07-30)` and SHA-256 `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
- Pin upstream filesystem WIT SHA-256 `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`.
- Admit only the exact `(Dir, u32, text) -> DescriptorStat | StatError` source shape with one direct `@await` and a synchronous empty `start`.
- Keep the target opt-in under `--p3-async-component`; the default compiler path remains fail-closed.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, lifetime, or generic filesystem async lowering.
- Cancellation is cleanup-only; Store-disposal early-drop is not Component task cancellation.

---

### Task 1: Pin the stat-at ABI probe

**Files:**
- Create: `examples/p3-runtime/wit/wasi-filesystem-stat-at.wit`
- Create: `examples/p3-runtime/wit/wasi-filesystem-stat-at-cancel.wit`
- Create: `examples/p3-runtime/test_d2_wasi_filesystem_stat_at_abi.sh`
- Create: `examples/p3-runtime/wasi-filesystem-stat-at.core.wat`
- Create: `examples/p3-runtime/wasi-filesystem-stat-at-cancel.core.wat`

**Interfaces:**
- Consumes the pinned upstream `filesystem/types.wit` and current `wasm-tools`.
- Produces the measured five-i32 method import, thirteen-value task-return,
  canonical record result area, path frame offsets, WIT mirror hashes, and
  validated regular/cancel Core templates.

- [ ] **Step 1: Write the failing ABI assertion**

  Start the WIT mirrors from the exact `descriptor-stat` definitions in
  `wasi-filesystem-stat.wit`, change the resource method and probe world to
  `stat-at`, and make the ABI script require the five-i32 import, the thirteen
  task-return values, `string-encoding=utf8 async`, and only the `stat-at`
  method.

- [ ] **Step 2: Run the ABI probe and verify the expected failure**

  Run `bash examples/p3-runtime/test_d2_wasi_filesystem_stat_at_abi.sh`.
  Expected: failure because the checked-in Core templates are not present or
  do not yet contain the measured `stat-at` markers.

- [ ] **Step 3: Write the minimal measured Core templates**

  Use the current `wasm-tools component embed -t` output to set the exact
  method/task-return signatures. Copy the stat record frame operations and add
  descriptor, path-flags, path pointer, and path length fields before the
  result area. Keep the result-area pointer and all cleanup operations explicit.

- [ ] **Step 4: Run the ABI probe to verify it passes**

  Run `bash examples/p3-runtime/test_d2_wasi_filesystem_stat_at_abi.sh`.
  Expected: both Core modules parse/validate, Component assembly succeeds, and
  the printed Component/WIT contains exactly one `descriptor.stat-at` method.

- [ ] **Step 5: Commit the probe boundary**

  ```bash
  git add examples/p3-runtime/wit/wasi-filesystem-stat-at.wit \
    examples/p3-runtime/wit/wasi-filesystem-stat-at-cancel.wit \
    examples/p3-runtime/test_d2_wasi_filesystem_stat_at_abi.sh \
    examples/p3-runtime/wasi-filesystem-stat-at.core.wat \
    examples/p3-runtime/wasi-filesystem-stat-at-cancel.core.wat
  git commit -m "Pin descriptor.stat-at async ABI"
  ```

### Task 2: Add registry and sema admission tests

**Files:**
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/sema_imports.zig`
- Create: `src/build/test/compile_ok/530_wasi_filesystem_stat_at_component.do`
- Create: `src/build/test/compile_ok/530_wasi_filesystem_stat_at_component.expect`
- Create: `src/build/test/compile_err/531_wasi_filesystem_stat_at_unregistered.do`
- Create: `src/build/test/compile_err/531_wasi_filesystem_stat_at_unregistered.expect`
- Create: `src/build/test/compile_err/532_wasi_filesystem_stat_at_wrong_flags.do`
- Create: `src/build/test/compile_err/532_wasi_filesystem_stat_at_wrong_flags.expect`
- Create: `src/build/test/compile_err/533_wasi_filesystem_stat_at_wrong_path.do`
- Create: `src/build/test/compile_err/533_wasi_filesystem_stat_at_wrong_path.expect`
- Create: `src/build/test/compile_err/534_wasi_filesystem_stat_at_wrong_result.do`
- Create: `src/build/test/compile_err/534_wasi_filesystem_stat_at_wrong_result.expect`
- Create: `src/build/test/compile_err/535_wasi_filesystem_stat_at_second_await.do`
- Create: `src/build/test/compile_err/535_wasi_filesystem_stat_at_second_await.expect`
- Create: `src/build/test/compile_err/536_wasi_filesystem_stat_at_branch.do`
- Create: `src/build/test/compile_err/536_wasi_filesystem_stat_at_branch.expect`
- Create: `src/build/test/compile_err/537_wasi_filesystem_stat_at_loop.do`
- Create: `src/build/test/compile_err/537_wasi_filesystem_stat_at_loop.expect`
- Create: `src/build/test/compile_err/538_wasi_filesystem_stat_at_extra_host.do`
- Create: `src/build/test/compile_err/538_wasi_filesystem_stat_at_extra_host.expect`
- Create: `src/build/test/compile_err/539_wasi_filesystem_stat_at_async_root.do`
- Create: `src/build/test/compile_err/539_wasi_filesystem_stat_at_async_root.expect`

**Interfaces:**
- Consumes the ABI registry shape from Task 1 and existing stat/hash-at source
  validation helpers.
- Produces a `filesystem_stat_at` lowering shape and fail-closed sema admission
  for the exact positive fixture.

- [ ] **Step 1: Add the positive and negative source fixtures**

  Add fixture `530` with the exact source contract from the design. Copy the
  topology negatives from the neighboring method gates and change only the
  `stat-at` signature, path, or topology under test.

- [ ] **Step 2: Run targeted sema tests and verify RED**

  Run `cd src && zig test build/sema_imports.zig` and compile fixtures `530`-
  `539` through the harness. Expected: the positive signature is not admitted
  and the new target-specific negative expectations cannot all pass because the
  registry shape and matcher are absent.

- [ ] **Step 3: Add the registry descriptor and lowering shape**

  Register `descriptor.stat-at` with `params=["descriptor","path-flags","string"]`,
  result `Result<descriptor-stat,error-code>`, five core params, the stat
  thirteen-value completion, and a `record_layout` copied byte-for-byte from
  `descriptor.stat`. Add `FilesystemStatAtShape` and classify only this exact
  locator/member/effect/result/record contract.

- [ ] **Step 4: Add the sema signature predicate and unit tests**

  Accept `(Dir, u32, text) -> DescriptorStat | StatError` only, preserving the
  existing `Result<T,E>` compatibility boundary. Add unit tests for the positive
  signature and a `u32` to `text` path drift rejection.

- [ ] **Step 5: Run targeted sema tests and verify GREEN**

  Run `cd src && zig test build/sema_imports.zig` and the focused compile fixture
  commands. Expected: `530` is admitted only with the opt-in target and
  `531`-`539` reject before WAT with their expected diagnostics.

### Task 3: Add the stat-at planner, emitter, and dispatcher

**Files:**
- Create: `src/build/codegen_component_wasi_filesystem_stat_at.zig`
- Create: `src/build/wasi_filesystem_stat_at_component_template.wat`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/sema_error.zig` or existing diagnostic mapping only if a
  new target-specific error is required

**Interfaces:**
- Consumes `FilesystemStatAtShape`, the positive fixture, and Core/WIT mirrors.
- Produces `Target.wasi_filesystem_stat_at`, `StatAtPlan.analyze`, and WIT/Core
  output for `--p3-async-component`.

- [ ] **Step 1: Add planner/emitter unit tests before implementation**

  Add tests that assert fixture `530` captures host/root/path/pending names,
  rejects second-await/branch/loop/extra-host/async-root drift, and emits the
  `stat-at` WIT plus exact template markers.

- [ ] **Step 2: Run the focused Zig test and verify RED**

  Run `cd src && zig test build/codegen_component_wasi_filesystem_stat_at.zig`.
  Expected: the module does not exist yet, so the command fails for the
  intended missing-module reason.

- [ ] **Step 3: Implement the minimal method-specific planner and template**

  Keep the source matcher linear and fail-closed. Use the measured five-i32
  method import, store the UTF-8 path in the frame until completion, decode the
  canonical stat record/error area, forward all thirteen completion values,
  and drop subtask, descriptor, waitable, and context exactly once.

- [ ] **Step 4: Wire target classification and WIT/WAT dispatch**

  Add the import, `Target` enum entry, target classification branch, descriptor
  switch, and `emit_component_wit`/`emit_component_wat` branches in
  `codegen_component_async.zig`. Keep target isolation so existing private
  methods cannot co-occur with `stat-at` unless the dispatcher explicitly
  admits the same single target contract.

- [ ] **Step 5: Run focused Zig tests and compile fixtures**

  Run the new module test, `cd src && zig test build/codegen_component_async.zig`,
  and the compile fixture subset. Expected: planner/emitter tests and fixture
  `530` pass; `531`-`539` remain fail-closed.

### Task 4: Add generated Component and Rust/Wasmtime runtime gates

**Files:**
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_stat_at.sh`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_stat_at.rs`
- Create: `examples/p3-runtime/wit/wasi-filesystem-stat-at.wit` generated/runtime
  mirrors if Task 1 names differ
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` only if a new bin
  target is not auto-discovered

**Interfaces:**
- Consumes the Task 1 Core/WIT contract and Task 3 generated fixture output.
- Produces ready, pending, error, cancel, Store-disposal early-drop, and repeat
  observations with owned UTF-8 path copies and exactly-once cleanup.

- [ ] **Step 1: Write the Rust runner assertions**

  Adapt the existing stat runner's record decoder and the metadata-hash-at
  runner's owned path/pending wake logic. Require a non-ASCII relative path,
  `Err(no-entry)` for a missing path, two sequential paths, and the documented
  early-drop boundary.

- [ ] **Step 2: Run the runtime script and verify RED**

  Run `bash examples/p3-runtime/test_rust_wasi_filesystem_stat_at.sh`.
  Expected: failure because the runner, component fixture, or generated target
  is not present yet.

- [ ] **Step 3: Implement the host callback and matrix**

  Copy the descriptor-stat component types, add `stat-at(path-flags, path)`,
  clone the path into an owned `String` before constructing the future, and
  report host calls, polls, wakes, completions, future drops, pending drops,
  descriptor drops, decoded options, and `table-empty` exactly as asserted.

- [ ] **Step 4: Run the ABI, compiler, and runtime gates**

  Run the ABI script, the compiler/runtime script, and the generated Component
  matrix. Expected: regular/cancel Components validate with the exact method set;
  ready/pending/error/cancel/early-drop/repeat all pass.

### Task 5: Update status and release evidence

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/master_plan.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`

- [ ] **Step 1: Add the method-specific evidence and boundary**

  Record the measured hashes, template hash, fixture range, runtime rows, and
  explicit statement that generic filesystem async, external HTTP, and public
  ownership syntax remain blocked.

- [ ] **Step 2: Run the complete verification path**

  Run `./src/build/test/run_tests.sh`,
  `RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh`,
  `cd src && zig test main.zig`, `cd src && zig build -Doptimize=ReleaseSmall`,
  both stat-at ABI/runtime scripts, and `git diff --check`.

- [ ] **Step 3: Commit the complete promotion**

  ```bash
  git add src/build examples/p3-runtime docs/superpowers doc
  git commit -m "Promote descriptor.stat-at async filesystem slice"
  ```

