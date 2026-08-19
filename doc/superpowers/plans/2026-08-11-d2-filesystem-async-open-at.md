# D2 `descriptor.open-at` Async Filesystem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a private opt-in `descriptor.open-at` Component async slice with a pinned ABI, exact Do source admission, and Rust/Wasmtime ownership and cleanup coverage.

**Architecture:** Keep `descriptor.open-at` as a separate registry lowering shape, planner/emitter module, and fixed WAT/WIT templates. Reuse only measured path-string lowering and resource cleanup patterns; do not widen `stat-at`, `metadata-hash-at`, or generic async lowering.

**Tech Stack:** Zig compiler and unit tests, Do compile fixtures, WIT/Core WAT, `wasm-tools 1.255.0`, Rust 1.97.1, Wasmtime 47.0.2, and `src/build/test/run_tests.sh`.

## Global Constraints

- Pin `wasm-tools 1.255.0 (76e20611d 2026-07-30)` and SHA-256 `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
- Pin upstream filesystem WIT SHA-256 `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`.
- Admit only `(Dir, u32, text, u32, u32) -> File | OpenError`, one direct await, linear body, and synchronous empty `start`.
- Keep the target opt-in under `--p3-async-component`; default compilation remains fail-closed.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointers, references, lifetimes, or generic filesystem async lowering.
- Cancellation is cleanup-only; an issued host open is never rolled back.

---

### Task 1: Add and measure the pinned ABI probe

**Files:**
- Create: `examples/p3-runtime/wit/wasi-filesystem-open-at.wit`
- Create: `examples/p3-runtime/wit/wasi-filesystem-open-at-cancel.wit`
- Create: `examples/p3-runtime/test_d2_wasi_filesystem_open_at_abi.sh`
- Create: `examples/p3-runtime/wasi-filesystem-open-at.core.wat`
- Create: `examples/p3-runtime/wasi-filesystem-open-at-cancel.core.wat`

**Interfaces:**
- Consumes the pinned filesystem WIT and current `wasm-tools`.
- Produces the measured indirect two-argument method, two-word task-return, result-area layout, and validated regular/cancel Core templates.

- [ ] **Step 1: Write the WIT mirrors and failing ABI assertions.**

  Mirror the complete `path-flags`, `open-flags`, `descriptor-flags`, and
  `error-code` definitions needed by `types.descriptor.open-at`. Define the
  resource method as `async`, expose `run` as an async own-descriptor result,
  and add a cancel-only `cancel: async func()` export. The script must check
  the pinned tool/source hashes, required method text, and required Core marker
  files. It must fail if either hand-authored Core file is missing.

- [ ] **Step 2: Run the ABI probe and verify the expected red state.**

  Run:

  ```bash
  bash examples/p3-runtime/test_d2_wasi_filesystem_open_at_abi.sh
  ```

  Expected: failure caused by absent/incomplete open-at Core markers, not by a
  malformed WIT or a tool/version mismatch.

- [ ] **Step 3: Record the current tool's dummy ABI.**

  Use `component embed --dummy-names legacy --async-callback -t` and require the
  two-`i32` indirect `[async-lower][method]descriptor.open-at` import, the two-word
  `[task-return]run` callback, `[resource-drop]descriptor`, and the cancel-only
  `[subtask-cancel]` import. Write the measured result-area tag, owned handle,
  error discriminant, and frame offsets into both Core templates and the ABI
  script.

- [ ] **Step 4: Validate and assemble both probes.**

  Parse and validate the regular and cancel Core WAT with
  `cm-async,cm-more-async-builtins`, embed each against its matching world,
  create a Component, validate it, and assert that the printed Component has
  exactly one `descriptor.open-at` method and no unrelated filesystem method.

- [ ] **Step 5: Run the ABI gate and commit the independent probe.**

  Re-run the script and commit only the five probe files:

  ```bash
  git add examples/p3-runtime/wit/wasi-filesystem-open-at.wit \
    examples/p3-runtime/wit/wasi-filesystem-open-at-cancel.wit \
    examples/p3-runtime/test_d2_wasi_filesystem_open_at_abi.sh \
    examples/p3-runtime/wasi-filesystem-open-at.core.wat \
    examples/p3-runtime/wasi-filesystem-open-at-cancel.core.wat
  git commit -m "Pin descriptor.open-at async ABI"
  ```

### Task 2: Add manifest, planner, and admission tests before production lowering

**Files:**
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/sema_imports.zig`
- Modify: `src/build/codegen_component_async.zig`
- Create: `src/build/test/compile_ok/540_wasi_filesystem_open_at_component.do`
- Create: `src/build/test/compile_ok/540_wasi_filesystem_open_at_component.expect`
- Create: `src/build/test/compile_err/541` through `549` open-at negative fixtures and matching `.expect` files

**Interfaces:**
- Consumes the measured registry ABI row from Task 1.
- Produces a method-specific `Target.wasi_filesystem_open_at` and a planner
  contract that rejects all unregistered or non-linear source shapes.

- [ ] **Step 1: Add the compile fixture and focused unit test first.**

  Add the exact Do shape from the spec with `# build-arg:
  --p3-async-component` and WAT expectations for the open-at import, resource
  drop, task-return, and generated Component metadata. Add a unit test in
  `codegen_component_async.zig` that embeds the fixture and expects the new
  target. Before adding the target/registry row, run the focused Zig test and
  observe `UnsupportedP3AsyncComponent`.

- [ ] **Step 2: Add negative fixtures and verify they fail for the right reason.**

  Cover: unregistered member, wrong path/open/descriptor flag types, wrong
  result resource, borrowed result, second await, branch, loop, extra host,
  and async root. Run the corresponding compile cases before implementation;
  the positive fixture must remain red while the negative cases continue to
  reject.

- [ ] **Step 3: Add the manifest row and pure shape validation.**

  Add a `filesystem-open-at` row whose canonical method import is
  `[async-lower][method]descriptor.open-at`, whose method has two indirect
  `i32` parameters (`params_ptr` and `result_ptr`) plus an `i32` readiness
  result, and whose completion is the measured two-word `task-return`. Add
  `FilesystemOpenAtShape`, a validator
  for locator/member/version, `(Dir,u32,text,u32,u32)` source types, resource
  result ownership, and the measured canonical fields. Add manifest tests for
  the exact row and ABI drift.

- [ ] **Step 4: Wire sema and target routing without a generic fallback.**

  Extend the known private async filesystem member table and route only a
  `host_async_func` binding that passes `FilesystemOpenAtPlan.analyze` to the
  new target. Keep `host_func`, wrong member, and wrong version on the existing
  `UnsupportedP3AsyncComponent` path.

- [ ] **Step 5: Run the focused red/green boundary.**

  Run:

  ```bash
  cd src && zig test build/p3_async_manifest.zig
  cd src && zig test build/codegen_component_async.zig --test-filter 'open-at'
  ```

  Expected at the end of this task: manifest and target classification pass,
  while emission still fails with the method-specific unsupported error until
  Task 3 supplies the emitter.

### Task 3: Implement the fixed compiler WIT/Core emitter

**Files:**
- Create: `src/build/codegen_component_wasi_filesystem_open_at.zig`
- Create: `src/build/wasi_filesystem_open_at_component_template.wat`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/sema_imports.zig` only if the exact known signature needs the shared diagnostic path
- Modify: `src/build/test/compile_ok/540...expect` and negative expectations as diagnostics stabilize

**Interfaces:**
- Consumes `FilesystemOpenAtShape` and the names returned by its planner.
- Produces validated fixed WIT/Core output with one path copy, one direct await,
  exactly-once parent/child cleanup, and no public ownership syntax.

- [ ] **Step 1: Write planner tests for source topology and ownership.**

  Test that the planner accepts only one direct `@await`, no branch/loop/defer,
  an ordinary synchronous root, one exact host binding, distinct `Dir` and
  `File` resource shells, and `File | OpenError`. Test every negative fixture
  through `target_for_tokens`.

- [ ] **Step 2: Implement the minimal fixed planner/emitter.**

  Mirror the `stat-at` planner structure. Scan the host declaration and exact
  signature, validate the two resource declarations and error union, find the
  fixed `run` flow, and return only names needed by the template. Emit the
  measured template after checking the registry canonical import.

- [ ] **Step 3: Implement result-area and cleanup lowering.**

  In the fixed WAT, retain the copied path pointer/length and four flag words
  in the frame, populate the canonical indirect parameter block, call the
  two-argument method import, join the one subtask,
  read the canonical result tag before cleanup, forward either the child
  descriptor or error code through the two-word task-return, drop the parent
  exactly once, and release waitable/subtask/frame storage on ready, error,
  pending, and cancel paths. Never fabricate a child handle on `Err`.

- [ ] **Step 4: Emit the exact Component WIT.**

  Generate `open-at: async func(path-flags: path-flags, path: string,
  open-flags: open-flags, descriptor-flags: descriptor-flags) ->
  result<own<descriptor>, error-code>` and an async `run` with an owned
  descriptor parameter and the same result. Keep the cancel world separate and
  test-only.

- [ ] **Step 5: Run focused compiler tests and ABI validation.**

  Run the ABI script, the focused Zig tests, and the compile fixture harness.
  Expected: positive WAT contains exactly one open-at method import and the
  negative fixtures remain rejected before WAT.

### Task 4: Add the Rust/Wasmtime ownership and cancellation oracle

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_open_at.rs`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_open_at.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`

**Interfaces:**
- Consumes the regular/cancel WIT and Core probe worlds plus generated Do
  Component output.
- Produces counter-checked ready, pending, error, cancel, early-drop, and
  repeat results.

- [ ] **Step 1: Implement copied-path host state and resource table.**

  Register `[method]descriptor.open-at` with `func_wrap_concurrent`. Copy the
  incoming `String` and all flags into the future before returning it. Accept
  only the configured directory handle, create a child file handle on success,
  return `no-entry` for the missing path, and count host calls, path copies,
  polls, wakes, completions, future drops, pending future drops, and descriptor
  drops.

- [ ] **Step 2: Implement mode assertions.**

  `ready` opens a known file; `pending` uses a non-ASCII path and one wake;
  `error` opens a missing path; `cancel` exercises the test-only subtask
  cancel; `early-drop` disposes the Store; `repeat` opens two files. Assert
  that the parent is dropped once in every live-Store mode and that a child is
  returned/dropped only on successful opens.

- [ ] **Step 3: Add the runtime gate script.**

  Pin tool/source hashes, compile the generated fixture, parse/embed/validate
  regular and cancel Components, run `rustfmt --edition 2024 --check`, and run
  all modes with the existing Zig linker environment. Match complete counter
  lines, including `table-empty=true` for live stores and
  `table-empty=not-applicable` for Store disposal.

- [ ] **Step 4: Run the runtime gate and retain failures.**

  Run `bash examples/p3-runtime/test_rust_wasi_filesystem_open_at.sh`. A
  failure in path ownership, task-return decoding, or cleanup blocks compiler
  promotion; do not weaken the assertions.

### Task 5: Documentation, full verification, and delivery

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/master_plan.md` only for the exact completed slice

- [ ] **Step 1: Update status from command-backed evidence.**

  Record the pinned ABI, compiler target, runtime matrix, and any residual
  limitations. Keep general filesystem async and public ownership syntax
  listed as pending.

- [ ] **Step 2: Run all required verification.**

  ```bash
  bash examples/p3-runtime/test_d2_wasi_filesystem_open_at_abi.sh
  bash examples/p3-runtime/test_rust_wasi_filesystem_open_at.sh
  ./src/build/test/run_tests.sh
  cd src && zig test main.zig
  cd src && zig build -Doptimize=ReleaseSmall
  ```

  Record pass/fail/skip counts and leave failed commands visible if any gate is
  not green.

- [ ] **Step 3: Commit the completed slice.**

  Stage only the open-at implementation, tests, probe, and status documents.
  Use the concise subject `Promote private descriptor.open-at async slice`.
  Do not push without an explicit user `push`/`all push main` instruction.

## Plan Self-Review

- Every design requirement maps to Tasks 1-5.
- No `TODO`, `TBD`, or compatibility fallback is used as an implementation
  step.
- The result is always represented in Do as `File | OpenError`; WIT ownership
  appears only in generated/probe Component interfaces.
- The ABI measurement is a prerequisite for registry admission, and runtime
  cleanup is a prerequisite for compiler promotion.
