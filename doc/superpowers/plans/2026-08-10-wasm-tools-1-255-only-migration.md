# wasm-tools 1.255.0 Only Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use inline execution for this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `wasm-tools 1.255.0 (76e20611d 2026-07-30)` the only active Component/async toolchain while preserving historical 1.254.0 evidence and the unrelated dirty `descriptor.stat` probe.

**Architecture:** Active gates use the installed current binary and direct `component embed/new/validate`, or the current tool's `--async-callback --dummy-names legacy` metadata probe where the async naming scheme still requires it. The old 1.254.0 compatibility assembler and version selector are removed from executable paths; historical plans and dated baselines remain evidence records.

**Tech Stack:** `wasm-tools 1.255.0`, Zig 0.16.0, Do compiler, WAT/WIT Component gates, Rust/Wasmtime 47.0.2, Bash regression harness.

## Global Constraints

- Required active tool identity is `wasm-tools 1.255.0 (76e20611d 2026-07-30)` with SHA-256 `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
- Do not alter or revert the existing `descriptor.stat` probe files in the dirty worktree.
- Keep `--dummy-names legacy` only as the current wasm-tools async name-mangling mode; it does not authorize a 1.254.0 binary.
- Do not rewrite historical dated plans or baselines that record the tool version used at that time.
- Every active gate must fail closed on a missing, wrong-version, or wrong-hash tool.

---

### Task 1: Add the current-only regression guard

**Files:**
- Create: `examples/p3-runtime/test_wasm_tools_current_only.sh`
- Test: all active `examples/p3-runtime/*.sh` and `src/build/test/*.sh` references

- [x] **Step 1: Write the red guard.**

  Assert the installed binary version and hash, then reject active scripts that
  contain `1.254.0`, `legacy_wasm_tools`, `LEGACY_WASM_TOOLS`, or the removed
  `assemble_wasmtime_p3_legacy.sh` path. Historical `doc/` and dated baseline
  files are outside this executable-path scan.

- [x] **Step 2: Run the guard and record the expected failure.**

  Run `bash examples/p3-runtime/test_wasm_tools_current_only.sh`.
  It must fail before migration and list the remaining active legacy paths.

### Task 2: Migrate active async/component gates

**Files:**
- Modify: `examples/p3-runtime/test_async_call_arg_probe.sh`
- Modify: `examples/p3-runtime/test_async_call_scalar_argument_probe.sh`
- Modify: `examples/p3-runtime/test_async_call_component_probe.sh`
- Modify: `examples/p3-runtime/test_do_async_call_component.sh`
- Modify: `examples/p3-runtime/test_do_async_call_scalar_argument.sh`
- Modify: `examples/p3-runtime/test_do_async_host_scalar_argument.sh`
- Modify: `examples/p3-runtime/test_do_future_owned_component.sh`
- Modify: any other active shell gate found by Task 1
- Delete: `examples/p3-runtime/assemble_wasmtime_p3_legacy.sh`

- [x] **Step 1: Remove version selectors and legacy binary variables.**

  Each gate uses `WASM_TOOLS` or `command -v wasm-tools`, checks only the
  1.255.0 identity, and uses direct current `component embed/new/validate` or
  current `--async-callback --dummy-names legacy` custom metadata generation.

- [x] **Step 2: Replace compatibility-wrapper calls.**

  Build the core module with the existing Do command, run current
  `component embed`, then `component new --skip-validation` and `validate`.
  Preserve all existing marker, WIT hash, cleanup, and negative assertions.

- [x] **Step 3: Run focused gates.**

  Run the current-only probe, scalar async-call, host scalar, owned-future,
  generic async, and neighboring D2 gates. Expected result: no gate invokes a
  1.254.0 executable.

### Task 3: Synchronize current status and verify the migration

**Files:**
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/master_plan.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `CHANGELOG.md`

- [x] **Step 1: Record the single active toolchain.**

  State the 1.255.0 version/hash and remove claims that active gates require a
  legacy 1.254.0 route. Keep dated historical evidence unchanged.

- [x] **Step 2: Run the full verification matrix.**

  Run `bash examples/p3-runtime/test_wasm_tools_current_only.sh`,
  `./src/build/test/run_tests.sh`, `RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh`,
  the relevant Rust/Wasmtime gates, `cd src && zig test build/codegen_api.zig`,
  `./src/build/test/run_release_smoke.sh`, and `git diff --check`.

  Fresh evidence on 2026-08-10: default regression `pass=1177 fail=0 skip=3`,
  WASM regression `pass=1179 fail=0 skip=3` with wasm smoke `6/6`,
  `zig test build/codegen_api.zig` `95/95`, ReleaseSmall smoke passed, all
  focused current-only Component/D2 gates passed, and `git diff --check` was
  clean.

- [x] **Step 3: Close the migration checkpoint.**

  Confirm `rg` finds no 1.254.0 executable-path reference, inspect the diff,
  and commit only the migration files plus the plan. Do not stage the existing
  `descriptor.stat` probe until its separate promotion plan is resumed.

  Checkpoint commit: `Make wasm-tools 1.255.0 the active toolchain`.
