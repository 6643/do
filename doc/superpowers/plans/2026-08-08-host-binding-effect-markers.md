# Host Binding Effect Markers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the ambiguous host import spellings with two strict forms: `@host_func` for WIT ordinary `func` and `@host_async_func` for WIT `async func`, with no `@host` compatibility path.

**Architecture:** Keep the runtime and manifest ABI unchanged. The marker is a frontend admission contract; sema validates marker/effect agreement against the pinned WIT or async registry, codegen uses the same marker classification, and the WIT emitter chooses the marker from `function.is_async`. Ordinary WIT `func -> future<T>` remains synchronous at invocation and therefore uses `@host_func`.

**Tech Stack:** Zig compiler, Do fixtures, WIT parser/emitter, shell regression harness.

## Global Constraints

- `@host_func` admits only ordinary WIT `func` bindings.
- `@host_async_func` admits only WIT `async func` bindings and exposes the Do call result as `Future<T>`.
- `@host` and `@host_sync_func` are rejected; no compatibility alias is retained.
- A marker must agree with the pinned registry; source signature text cannot override the effect.
- Runtime/component ABI and cancellation semantics are unchanged.
- Every new positive or negative syntax rule has a regression fixture or unit test.

### Task 1: Add red tests for strict marker/effect separation

**Files:**
- Modify: `src/build/sema_imports.zig` (unit tests near existing host import tests)
- Modify: `src/wit/tests.zig` (WIT emitter expectations)
- Create: `src/build/test/compile_ok/host_func_sync_marker.do`
- Create: `src/build/test/compile_ok/host_async_func_marker.do`
- Create: `src/build/test/compile_err/host_marker_legacy.do`
- Create: `src/build/test/compile_err/host_marker_sync_alias.do`

- [ ] **Step 1: Write the failing tests**

  Assert that `@host_func("env", "add", (i32) -> i32)` is accepted, a pinned async member written with `@host_async_func` is accepted, `@host(...)` and `@host_sync_func(...)` are rejected, and the old async spelling `@host_func(...)` is rejected for an async descriptor. Update the emitter assertion from `send = @host(` to `send = @host_async_func(` for an async WIT function and add a sync function assertion for `@host_func(`.

- [ ] **Step 2: Run the focused tests and verify RED**

  Run `./src/build/test/run_tests.sh` after building the current compiler. Expected failure: the new async marker is not recognized and the old marker/effect combinations are still accepted or rejected for the wrong reason.

### Task 2: Make parser and semantic admission strict

**Files:**
- Modify: `src/build/sema_tokens.zig`
- Modify: `src/build/sema_imports.zig`
- Modify: `src/build/parser.zig`
- Modify: `src/build/import_resolution.zig`

- [ ] **Step 1: Implement the minimal marker set**

  Register only `lib`, `host_func`, and `host_async_func` as modern import assignments. Make ordinary host validation inspect `host_func` only. Make P3 async validation inspect `host_async_func` only and require a registry descriptor whose effect is `async` or an explicitly registered async lowering shape. Remove all `host` and `host_sync_func` branches instead of falling back to a legacy validator.

- [ ] **Step 2: Verify focused sema tests GREEN**

  Run the Zig sema tests and the focused compile fixtures. Confirm marker/effect mismatch diagnostics are deterministic and that a sync `func -> future<T>` path is not classified as `async func`.

### Task 3: Align codegen and component probe recognizers

**Files:**
- Modify: `src/build/codegen_host_imports.zig`
- Modify: `src/build/codegen_wasi_registry.zig`
- Modify: `src/build/codegen_component_async*.zig`
- Modify: `src/build/codegen_component_*stream*.zig`
- Modify: `src/build/codegen_component_wasi_*.zig`
- Modify: `src/build/codegen_component_resource_probe.zig`
- Modify: `src/build/sema_resource_ownership.zig`

- [ ] **Step 1: Replace marker predicates by effect-specific predicates**

  Synchronous host collection recognizes `@host_func`; asynchronous component plans and resource/stream probes recognize `@host_async_func`. Where a detector currently treats `host` and `host_func` as source/sink alternatives, map source to `host_func` and async sink to `host_async_func` explicitly. Do not broaden a detector to accept both markers.

- [ ] **Step 2: Run focused codegen and component tests**

  Run the relevant Zig tests and each affected `test_*shape.sh` gate. Expected result is unchanged WAT/component ABI aside from source marker text.

### Task 4: Migrate WIT generation and checked-in fixtures

**Files:**
- Modify: `src/wit/emit_do.zig`
- Modify: `src/wit/tests.zig`
- Modify: all checked-in `*.do` fixtures and examples containing `@host(` or async `@host_func(`
- Modify: `doc/host-binding-design.md`, `doc/async-design.md`, `doc/spec_rules.md`, `doc/grammar.peg` if host import grammar is listed

- [ ] **Step 1: Emit effect-specific markers**

  Emit `@host_async_func` when `function.is_async` is true; otherwise emit `@host_func`. Preserve `Future<T>` only for ordinary WIT `future<T>` returns and do not add `async` to generated Do function declarations.

- [ ] **Step 2: Migrate fixtures and documentation**

  Convert ordinary imports from `@host` to `@host_func`, convert pinned WIT async imports from `@host` or `@host_func` to `@host_async_func`, and add a short migration rule documenting that no legacy marker is accepted.

- [ ] **Step 3: Run the full regression suite**

  Run `cd src && zig build -Doptimize=ReleaseSmall`, `./src/build/test/run_tests.sh`, all WASM/component smoke gates, and `git diff --check`. Expected result: all existing behavior tests pass with only declaration-marker changes.

### Task 5: Review and commit

- [ ] **Step 1: Inspect the diff for stale marker branches**

  Run `rg -n '@host\\(|@host_func|host_sync_func|host_async_func|tok_eq\\([^\\n]*"host"' src doc examples` and confirm that only intentional negative fixtures or historical prose remain.

- [ ] **Step 2: Commit the completed migration**

  Stage only the marker migration files and commit with `Promote explicit host binding effect markers`.
