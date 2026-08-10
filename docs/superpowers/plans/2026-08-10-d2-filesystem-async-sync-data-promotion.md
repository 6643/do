# D2 `descriptor.sync-data` Private Promotion Implementation Plan

> Execute this plan task-by-task. Every task ends with a focused verification
> gate. Do not widen the compiler from a failed probe or from a neighboring
> descriptor's layout.

**Goal:** Prove and privately promote the exact `descriptor.sync-data` async
filesystem shape from pinned WIT through compiler-generated Component and
Rust/Wasmtime cleanup evidence.

**Design:** `docs/superpowers/specs/2026-08-10-d2-filesystem-async-sync-data-design.md`

## Global Constraints

- Use only `wasm-tools 1.255.0`, Rust `1.97.1`, Wasmtime `47.0.2`, and Zig `0.16.0`.
- Keep public Do results as `T | E` / `nil | E`; `Result<T,E>` remains private WIT/Component metadata.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, lifetime, or generic async syntax.
- Keep the target behind existing `--p3-async-component`; do not change default dispatch.
- Treat host cancellation as cleanup only; never fabricate rollback of `sync-data`.
- Stop before registry/codegen edits if the ABI probe rejects the pinned shape.

## File Map

Probe and runtime:

- Create `examples/p3-runtime/wit/wasi-filesystem-sync-data.wit`.
- Create `examples/p3-runtime/wit/wasi-filesystem-sync-data-cancel.wit`.
- Create `examples/p3-runtime/wasi-filesystem-sync-data.core.wat`.
- Create `examples/p3-runtime/wasi-filesystem-sync-data-cancel.core.wat`.
- Create `examples/p3-runtime/test_d2_wasi_filesystem_sync_data_abi.sh`.
- Create `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_sync_data.rs`.
- Create `examples/p3-runtime/test_rust_wasi_filesystem_sync_data.sh`.
- Modify only the runner Cargo binary list if the existing feature set needs it.

Compiler:

- Modify `src/build/p3_async_registry.json` and `src/build/p3_async_manifest.zig`.
- Modify `src/build/sema_imports.zig`.
- Create `src/build/codegen_component_wasi_filesystem_sync_data.zig` and
  `src/build/wasi_filesystem_sync_data_component_template.wat`.
- Modify `src/build/codegen_component_async.zig`.
- Create positive fixture `src/build/test/compile_ok/511_wasi_filesystem_sync_data_component.do`.
- Create negative fixtures/expectations `512`-`515` for unregistered member,
  wrong result, second await, and async root.

Status after all gates:

- Update `doc/host_abi_blockers.md`, `doc/pending_blocked.md`,
  `doc/start_here.md`, `doc/roadmap_status.md`, `doc/master_plan.md`, and
  `CHANGELOG.md` only with command-backed results.

## Tasks

### Task 1: Freeze source identity and baseline

- [x] Verify the `sync-data` source declaration and current tool/hash.
- [x] Run the existing sync/stat ABI, Rust, Zig, compiler, WASM, ReleaseSmall,
  and documentation baselines. Preserve any failure as a blocker.
- [x] Commit the spec and this plan after a consistency/scope review.

Commands:

```bash
rg -n -A4 -B4 'sync-data: async func' src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit
sha256sum src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit
./src/build/test/run_tests.sh
```

### Task 2: Measure the independent WIT/Core ABI

- [x] Author the smallest complete regular and cancel WIT worlds with the
  pinned error-code order and only `descriptor.sync-data`.
- [x] Assemble/embed/validate with current `wasm-tools`; record the exact
  import, completion words, Result tag/payload, and drop names.
- [x] Write regular/cancel Core WAT templates from measured names and assert
  marker order and hashes in `test_d2_wasi_filesystem_sync_data_abi.sh`.
- [x] Confirm the measured flat shape matches the promotion contract; the
  no-go condition was not triggered: `(i32,i32)->i32`, `(i32,i32)` task return,
  tag `i32`, Ok `[]`, Err `[i32]`.

Gate:

```bash
bash examples/p3-runtime/test_d2_wasi_filesystem_sync_data_abi.sh
```

### Task 3: Build the hand-authored Rust/Wasmtime oracle

- [x] Add ready, pending, error, explicit cancel, Store-disposal early-drop,
  and repeat modes; count calls, polls, wakes, completions, Future drops,
  descriptor drops, and `ResourceTable` state.
- [x] Assert exactly-once cleanup for live-Store rows and explicitly label
  Store disposal as `table-empty=not-applicable`.
- [x] Run rustfmt and the runtime gate before compiler changes.

Gate:

```bash
bash examples/p3-runtime/test_rust_wasi_filesystem_sync_data.sh
```

### Task 4: Write compiler fixtures and failing planner tests first

- [x] Add the exact positive source fixture `511`.
- [x] Add negative fixtures `512`-`515` for unregistered/wrong-result,
  second-await, and async-root drift with exact expected diagnostics.
- [x] Add manifest and target-classification tests that fail because the new
  shape and emitter do not yet exist.
- [x] Run focused tests and confirm the failure is the missing capability, not
  a fixture typo.

### Task 5: Add descriptor-backed registry and planner/emitter

- [x] Add a separate `filesystem-sync-data` shape with the measured canonical
  facts and strict WIT locator/member/hash checks.
- [x] Implement a source planner matching exactly one `@host_async_func`, one
  `Dir` receiver, one `Future<nil | SyncDataError>`, one await, and ordinary
  root/start functions.
- [x] Add a private emitter and WAT template with the fixed frame and cleanup
  order; reject every negative fixture before WAT.
- [x] Add the new target to `codegen_component_async.zig` without changing
  existing target behavior.
- [x] Run manifest, planner, codegen, and fixture tests until green.

### Task 6: Assemble generated Component and compare runtime behavior

- [x] Compile fixture `511` through `--p3-async-component` and emit WIT/WAT.
- [x] Assert generated WIT identity, Core markers, and pinned hashes.
- [x] Embed/new/validate with current `wasm-tools` and run generated ready,
  pending, error, and repeat rows plus the hand-authored cancel rows.
- [x] Compare generated cleanup counters with the Rust oracle.

### Task 7: Full regression, documentation, delivery

- [x] Run focused scripts, `cd src && zig test main.zig`, normal and WASM
  regression, ReleaseSmall smoke, `git diff --check`, and documentation
  consistency checks.
- [x] Update status docs to list only private `descriptor.sync-data` as newly
  closed; retain generic filesystem async and public ownership as pending.
- [x] Commit in bounded units, verify `git status`, fetch/rebase if needed,
  and push `main`.

## Acceptance Checklist

- [x] Pinned source/tool hashes and independent WIT/Core ABI are recorded.
- [x] Rust/Wasmtime ready/pending/error/cancel/early-drop/repeat matrix is green.
- [x] Registry, planner, emitter, positive fixture `511`, and negative fixtures
  `512`-`515` are fail-closed and green.
- [x] Generated Component matches the canonical ABI and runtime cleanup.
- [x] Existing regression and delivery gates remain green.
