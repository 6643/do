# Rust Runner Build Cache Reduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reclaim the runner-local 130GB Cargo target cache and prevent debug
information and incremental compilation from recreating that avoidable usage.

**Architecture:** Keep the target path unchanged so scripts that execute
`target/debug/...` continue to work. Configure only this Cargo package's dev
profile, clean only the target resolved from its manifest, then cold-rebuild
the existing private Component ABI gate as the functional proof.

**Tech Stack:** Cargo/Rust `1.97.1`, Wasmtime `47.0.2`, Bash, and the existing
`examples/p3-runtime` Component gate.

## Global Constraints

- The deletion target is exactly
  `examples/p3-runtime/rust-host-runner/target`, as resolved from this
  manifest's `cargo metadata` output.
- Do not delete `~/.cargo`, any sibling project target, source fixture, WIT
  file, Component artifact, or existing test script.
- Add only `[profile.dev] debug = 0` and `incremental = false` to the runner's
  Cargo manifest; do not alter package dependencies or release profile.
- Preserve `target/debug` as the output path because existing tests invoke it
  directly.
- The worktree is dirty. Do not reset, clean, revert, stage, commit, push, or
  modify unrelated changes.
- A cold rebuild is expected after the targeted Cargo clean. Failure of the
  runtime gate stops the work; do not widen the cleanup target.

## File Structure

| File | Responsibility |
| --- | --- |
| `examples/p3-runtime/rust-host-runner/Cargo.toml` | Package-local dev-profile storage policy. |
| `docs/superpowers/specs/2026-08-05-rust-runner-build-cache-design.md` | Records exact before/after measurements and verification result. |
| `docs/superpowers/plans/2026-08-05-rust-runner-build-cache-reduction.md` | Tracks this bounded cleanup and validation sequence. |

---

### Task 1: Verify The Exact Deletion Boundary And Configure The Dev Profile

**Files:**
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Uses: `examples/p3-runtime/rust-host-runner/target`

**Interfaces:**
- Consumes Cargo metadata for the runner manifest.
- Produces the same `target/debug` output path with native debug information
  and incremental compilation disabled.

- [x] **Step 1: Capture and assert the runner-local target directory.**

  Run:

  ```bash
  runner_manifest="$PWD/examples/p3-runtime/rust-host-runner/Cargo.toml"
  runner_target=$(cargo metadata --manifest-path "$runner_manifest" --no-deps --format-version 1 | sed -n 's/.*"target_directory":"\([^"]*\)".*/\1/p')
  test "$runner_target" = "$PWD/examples/p3-runtime/rust-host-runner/target"
  du -sb "$runner_target"
  ```

  Expected: the assertion succeeds and the byte count is recorded before any
  deletion. Stop if Cargo resolves another directory.

- [x] **Step 2: Add the minimal profile policy.**

  Append this exact stanza to the runner manifest, after all `[[bin]]` entries:

  ```toml
  [profile.dev]
  debug = 0
  incremental = false
  ```

  Do not add `CARGO_TARGET_DIR`, `strip`, release settings, dependencies, or
  feature changes.

- [x] **Step 3: Verify manifest validity before cleanup.**

  Run:

  ```bash
  cargo metadata --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml --no-deps --format-version 1 >/dev/null
  ```

  Expected: exit `0`; the manifest still resolves the same runner-local target
  path.

### Task 2: Clean Only The Runner Cache And Prove A Cold Rebuild

**Files:**
- Generated/deleted only: `examples/p3-runtime/rust-host-runner/target/**`
- Test: `examples/p3-runtime/test_variant_resource_stream_abi.sh`

**Interfaces:**
- Consumes the confirmed target path and package-local dev profile from Task 1.
- Produces freshly rebuilt `target/debug/do-p3-variant-resource-stream-abi`
  with no incremental compilation files.

- [x] **Step 1: Dry-run the exact Cargo clean command.**

  Run:

  ```bash
  cargo clean --dry-run --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml
  ```

  Expected: Cargo lists removals only under the runner-local target directory.
  Stop if it identifies another path.

- [x] **Step 2: Execute the confirmed targeted clean.**

  Run:

  ```bash
  cargo clean --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml
  ```

  Expected: Cargo reports removed artifacts; `du -sb` on the prior target path
  is substantially lower than the Task 1 byte count before rebuild.

- [x] **Step 3: Run the cold Component/Rust rebuild gate.**

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" \
    bash examples/p3-runtime/test_variant_resource_stream_abi.sh
  ```

  Expected: Cargo rebuilds the required runner, then all eight Component modes
  pass. The command proves `target/debug` remains usable by existing scripts.

- [x] **Step 4: Verify the storage policy after rebuild.**

  Run:

  ```bash
  test "$(find examples/p3-runtime/rust-host-runner/target/debug/incremental -type f | wc -l)" = 0
  if readelf -S examples/p3-runtime/rust-host-runner/target/debug/do-p3-variant-resource-stream-abi | rg -q '[.]debug_'; then
    exit 1
  fi
  du -sb examples/p3-runtime/rust-host-runner/target
  ```

  Expected: Cargo may retain an empty `incremental` directory, but it contains
  zero files; the rebuilt runner has no native debug sections; and the
  after-rebuild byte count is lower than Task 1's pre-clean count.

### Task 3: Record The Measured Result

**Files:**
- Modify: `docs/superpowers/specs/2026-08-05-rust-runner-build-cache-design.md`
- Modify: `docs/superpowers/plans/2026-08-05-rust-runner-build-cache-reduction.md`

**Interfaces:**
- Consumes the two measured byte counts, dry-run target, Cargo clean output,
  and cold-gate result.
- Produces an auditable record that this is a runner-only cache policy, not a
  compiler or ABI change.

- [x] **Step 1: Update the design spec with measured facts only.**

  Change its status to verified and record: pre-clean bytes, post-clean bytes,
  post-rebuild bytes, zero incremental compilation files, absence of native
  debug sections in the rebuilt runner, and the green gate command.
  State that the target path remains unchanged and no external directory was
  deleted.

- [x] **Step 2: Check formatting and the targeted diff.**

  Run:

  ```bash
  rg -n '[[:blank:]]+$' examples/p3-runtime/rust-host-runner/Cargo.toml docs/superpowers/specs/2026-08-05-rust-runner-build-cache-design.md docs/superpowers/plans/2026-08-05-rust-runner-build-cache-reduction.md
  git diff --check
  git status --short -- examples/p3-runtime/rust-host-runner/Cargo.toml docs/superpowers/specs/2026-08-05-rust-runner-build-cache-design.md docs/superpowers/plans/2026-08-05-rust-runner-build-cache-reduction.md
  ```

  Expected: no whitespace errors; status shows only the intended manifest and
  documentation paths from this task, alongside any pre-existing user changes.
