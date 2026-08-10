# D2 `descriptor.metadata-hash-at` Async Filesystem ABI Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Goal:** Preserve a pinned, independently verifiable ABI probe for the WASI `descriptor.metadata-hash-at` async method without changing compiler admission.

**Architecture:** Mirror only the required filesystem WIT types, observe the current Component async lowering with dummy embedding, and pair that evidence with hand-authored Core WAT templates. A single Bash gate pins tool/source/mirror hashes, validates Core modules, assembles regular and cancellation Components, and checks generated WIT/WAT markers.

**Tech Stack:** WIT, Core WebAssembly Text, `wasm-tools 1.255.0`, Bash, SHA-256, existing P3 runtime probe layout.

## Global Constraints

- Pin `wasi:filesystem@0.3.0-rc-2025-09-16` and upstream WIT SHA-256 `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`.
- Require `wasm-tools 1.255.0 (76e20611d 2026-07-30)` with SHA-256 `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
- Use Component features `cm-async,cm-more-async-builtins`.
- Do not modify compiler registry, sema, planner, codegen, public ownership syntax, or generic filesystem async lowering.
- Cancellation is cleanup-only; do not claim host rollback.

---

### Task 1: Add exact regular and cancellation WIT mirrors

**Files:**
- Create: `examples/p3-runtime/wit/wasi-filesystem-metadata-hash-at.wit`
- Create: `examples/p3-runtime/wit/wasi-filesystem-metadata-hash-at-cancel.wit`
- Read-only source: `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit:132-138,602-634`

**Interfaces:**
- Consumes: pinned `path-flags`, `metadata-hash-value`, `error-code`, and `descriptor.metadata-hash-at` definitions.
- Produces: worlds `metadata-hash-at-probe` and `metadata-hash-at-cancel-probe`, each exporting `probe`; the cancel world additionally exports `cancel`.

- [x] **Step 1: Copy the pinned type order.**

  Keep `flags path-flags { symlink-follow }`, the two `u64` record fields in
  `lower`/`upper` order, and the complete upstream error-code order.

- [x] **Step 2: Declare the method and root operation.**

  Use `path-flags: path-flags` and `path: string` in both the resource method
  and `run`. Do not use `flags` as a parameter name because WIT treats it as a
  keyword.

- [x] **Step 3: Parse both worlds with the pinned tool.**

  Create a temporary package directory, copy each WIT file into its matching
  world directory, and run:

  ```bash
  tmp_dir=$(mktemp -d /tmp/do-d2-filesystem-metadata-hash-at-plan.XXXXXX)
  mkdir -p "$tmp_dir/regular" "$tmp_dir/cancel"
  cp examples/p3-runtime/wit/wasi-filesystem-metadata-hash-at.wit "$tmp_dir/regular/"
  cp examples/p3-runtime/wit/wasi-filesystem-metadata-hash-at-cancel.wit "$tmp_dir/cancel/"
  wasm-tools component embed "$tmp_dir/regular" --world metadata-hash-at-probe \
    --dummy-names legacy --async-callback \
    --features cm-async,cm-more-async-builtins -t >"$tmp_dir/regular.wat"
  wasm-tools component embed "$tmp_dir/cancel" --world metadata-hash-at-cancel-probe \
    --dummy-names legacy --async-callback \
    --features cm-async,cm-more-async-builtins -t >"$tmp_dir/cancel.wat"
  ```

  Expected: both WIT inputs parse and produce one
  `[async-lower][method]descriptor.metadata-hash-at` import.

### Task 2: Measure the current dummy Core ABI

**Files:**
- Create: `examples/p3-runtime/test_d2_wasi_filesystem_metadata_hash_at_abi.sh`
- Inputs: the two WIT mirrors from Task 1

**Interfaces:**
- Consumes: WIT worlds and pinned tool/source hashes.
- Produces: measured method import, resource drop, task-return, and string
  lowering evidence in the probe output.

- [x] **Step 1: Pin identity checks.**

  Require the exact tool version/hash, upstream WIT hash, and the two mirror
  hashes before invoking `component embed`.

- [x] **Step 2: Assert dummy imports and types.**

  Require method type `(i32 i32 i32 i32 i32) -> i32`, descriptor drop,
  `(i32 i64 i64)` task-return, one async method, and the cancel task-return plus
  root subtask-cancel marker in the cancel world.

- [x] **Step 3: Record the measured argument order.**

  Print the canonical order as `descriptor:i32 path-flags:i32 path-ptr:i32
  path-len:i32 result-area:i32`. The generated Component WAT must contain
  `string-encoding=utf8 async`.

### Task 3: Add hand-authored Core ABI templates

**Files:**
- Create: `examples/p3-runtime/wasi-filesystem-metadata-hash-at.core.wat`
- Create: `examples/p3-runtime/wasi-filesystem-metadata-hash-at-cancel.core.wat`

**Interfaces:**
- Consumes: Task 2's five-`i32` import and three-word task-return shape.
- Produces: valid Core modules with explicit frame offsets, result area,
  descriptor drop, pending/ready/error markers, and test-only cancellation.

- [x] **Step 1: Define the regular module signatures.**

  Export the async lift/callback pair for `run`, import the measured method and
  descriptor drop, and use a four-argument `run` function for the owned
  descriptor, flags, path pointer, and path length.

- [x] **Step 2: Define the frame and result area.**

  Use the fixed offsets below and keep `u64` payloads aligned:

  ```text
  0 waitable, 4 descriptor, 8 path-flags, 12 path-ptr,
  16 path-len, 20 status, 24 result-tag, 32 lower,
  40 upper, 48 callback-subtask
  ```

- [x] **Step 3: Define cleanup and cancellation markers.**

  On completion, drop subtask, descriptor, and waitable exactly once before
  task-return. In the cancel template, call `[async-lower][subtask-cancel]`,
  conditionally drop the subtask, and return through `[task-return]cancel`; do
  not synthesize host rollback.

- [x] **Step 4: Parse and validate both modules.**

  Run `wasm-tools parse` followed by
  `wasm-tools validate --features cm-async,cm-more-async-builtins` for each
  WAT file. Expected: both commands succeed.

### Task 4: Assemble and validate regular/cancel Components

**Files:**
- Modify: `examples/p3-runtime/test_d2_wasi_filesystem_metadata_hash_at_abi.sh`

**Interfaces:**
- Consumes: Task 1 WIT mirrors and Task 3 Core templates.
- Produces: validated Component artifacts and generated Component WIT/WAT
  matching the measured method and input/result shape.

- [x] **Step 1: Embed each Core module into its WIT world.**

  Run `component embed`, `component new --skip-validation`, `validate`,
  `print`, and `component wit` for regular and cancel worlds.

- [x] **Step 2: Assert Component markers.**

  Require the method, descriptor drop, task-return, UTF-8 async string
  lowering, `path-flags` WIT declaration, and exact `run` signature. Require
  task-return cancel and subtask-cancel markers only in the cancel world.

- [x] **Step 3: Reject accidental neighboring methods.**

  Fail if generated Component WAT contains `descriptor.metadata-hash`, `stat`,
  `stat-at`, `get-type`, `get-flags`, `sync`, or `sync-data` imports.

### Task 5: Document the boundary and delivery evidence

**Files:**
- Create: `docs/superpowers/specs/2026-08-10-d2-filesystem-async-metadata-hash-at-design.md`
- Create: `docs/superpowers/plans/2026-08-10-d2-filesystem-async-metadata-hash-at.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`

**Interfaces:**
- Consumes: successful output from Tasks 1-4.
- Produces: an auditable record that ABI capability is measured while compiler
  admission remains blocked.

- [x] **Step 1: Record measured evidence.**

  Add the exact hashes, five-`i32` method order, `string-encoding=utf8 async`,
  three-word task-return, result-area offsets, and drop/cancel markers to the
  design and blocker records.

- [x] **Step 2: Preserve the no-admission boundary.**

  State that no compiler code, positive/negative Do fixture, or Rust/Wasmtime
  business-I/O claim is included. Keep the generic filesystem row and public
  ownership syntax blocked.

- [x] **Step 3: Run the focused acceptance command.**

  Run `bash examples/p3-runtime/test_d2_wasi_filesystem_metadata_hash_at_abi.sh`
  and retain its complete output in the delivery record. Expected: exit 0 and
  the measured ABI summary printed by the script.

- [x] **Step 4: Review the diff and commit the probe slice.**

  Review `git diff --check`, the five new probe artifacts, and the two blocker
  document updates. Commit only this bounded evidence slice; do not include
  compiler admission or unrelated worktree changes.

## Self-Review Checklist

- All WIT identifiers and parameter names are valid under the pinned tool.
- The regular and cancel worlds contain exactly one filesystem async method.
- The Core method type and task-return type match the dummy embed output.
- The result-area offsets keep both `u64` words aligned and are asserted by the
  script.
- The generated Component WIT keeps `path-flags` and UTF-8 string lowering.
- The plan has no compiler implementation step and no rollback claim.
