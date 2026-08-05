# Next Phase: Release Candidate, G6.2 Probe, and D2 Maintenance Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the current v1 compiler baseline green, maintain the admitted D2 real-host matrix, and advance G6.2 only through a new independently evidenced bounded shape.

**Architecture:** The phase has two unconditional tracks and one gated track. Release-candidate maintenance and existing D2 smoke tests can proceed without changing language semantics. A new G6.2 shape first requires a canonical WIT/WAT probe, ownership/cleanup rules, and negative boundaries; only then may its compiler lowering be implemented. If no candidate satisfies the gate, record a no-go and leave the compiler unchanged.

**Tech Stack:** Zig 0.16.0, Do compiler, WAT/WIT, `wasm-tools` 1.254.0, Rust 1.97.1, Wasmtime 47.0.2, Bash regression harness.

## Global Constraints

- Preserve the dirty worktree; do not reset, clean, stage, commit, or push.
- Ordinary public Do result APIs remain `T | E` or `nil | E`; `Result<T, E>` remains private to registered WIT/Component probes.
- Do not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax.
- Do not widen generic async lowering, borrowed/list/variant lowering, producer leases, or the existing nested-resource depth without a separate design and gate.
- D2 uses deterministic local resources only; no external-network HTTP test is permitted.
- Cancellation observes task/resource cleanup and never generates rollback or compensation logic.
- Every claimed completion must include positive behavior, negative boundaries, Component validation, and exact cleanup evidence where resources are involved.

## Plan Map

| Order | Task | Deliverable |
| --- | --- | --- |
| 1 | Release-candidate baseline audit | Fresh regression counts and corrected documentation, if drift exists |
| 2 | G6.2 next-shape decision and pinned probe | One design/probe result, or an explicit no-go with recovery conditions |
| 3 | D2 real-host matrix maintenance | Revalidated TCP/UDP and existing local-resource smoke gates |
| 4 | Conditional G6.2 implementation | A single bounded lowering slice only after Task 2 is green and approved |
| 5 | Phase closeout | Full matrix, roadmap update, and residual-risk record |

### Task 1: Establish the release-candidate baseline

**Files:**
- Inspect/modify: `doc/start_here.md`
- Inspect/modify: `doc/roadmap_status.md`
- Inspect/modify: `doc/master_plan.md`
- Inspect/modify: `doc/pending_blocked.md`
- Inspect/modify: `CHANGELOG.md`
- Inspect: `examples/p3-runtime/d2-real-host-matrix.md`

**Interfaces:**
- Consumes the current compiler, fixture, and real-host gates.
- Produces one reproducible baseline; documentation changes are limited to facts observed in this task.

- [x] **Step 1: Run the baseline commands.**

  ```bash
  cd src && zig test main.zig
  cd ..
  TMPDIR="$PWD/.tmp/do-tmp/next-phase-default" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/next-phase-zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/next-phase-zig-gcache" \
    ./src/build/test/run_tests.sh
  TMPDIR="$PWD/.tmp/do-tmp/next-phase-wasm" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/next-phase-zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/next-phase-zig-gcache" \
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  ```

  Expected: the current documented `243/243`, `pass=1070 fail=0 skip=3`, WASM `pass=1072 fail=0 skip=3`, and release smoke result remain green, or the exact changed count is recorded as a finding.

- [x] **Step 2: Check for documentation drift.**

  ```bash
  rg -n "pass=|zig test|G6\.2|G6\.3|D2|skip=|variant-resource-stream" \
    doc/start_here.md doc/roadmap_status.md doc/master_plan.md \
    doc/pending_blocked.md CHANGELOG.md examples/p3-runtime/d2-real-host-matrix.md
  git diff --check
  ```

  Update only stale counts, statuses, or links. Do not convert a pending or controlled probe into a completed runtime claim.

- [x] **Step 3: Record the baseline checkpoint.**

  Add one dated entry to `CHANGELOG.md` only when the observed result differs from the current entry or when a new gate is being recorded. Keep the three remaining skips and all G6.2 residual boundaries explicit.

### Task 2: Select and probe one new G6.2 shape

**Files:**
- Create only on a green candidate gate: `docs/superpowers/specs/2026-08-05-g6-2-next-shape-design.md`
- Create only on a green candidate gate: `examples/p3-runtime/wit/g6-2-next-shape.wit`
- Create only on a green candidate gate: `examples/p3-runtime/g6-2-next-shape.core.wat`
- Create only on a green candidate gate: `src/build/test/compile_ok/415_g6_2_next_shape.do`
- Create only on a green candidate gate: `src/build/test/compile_err/415_g6_2_next_shape_unknown.do`
- Create only on a green candidate gate: `src/build/test/compile_err/415_g6_2_next_shape_unknown.expect`
- Create only on a green candidate gate: `src/build/test/compile_err/415_g6_2_next_shape_bad_arity.do`
- Create only on a green candidate gate: `src/build/test/compile_err/415_g6_2_next_shape_bad_arity.expect`
- Create only on a green candidate gate: `src/build/test/compile_err/415_g6_2_next_shape_duplicate_release.do`
- Create only on a green candidate gate: `src/build/test/compile_err/415_g6_2_next_shape_duplicate_release.expect`
- Create only on a green candidate gate: `examples/p3-runtime/test_g6_2_next_shape_probe.sh`
- Create only on a green candidate gate: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_next_shape.rs`
- Modify: `doc/pending_blocked.md` only after the probe result is known

For the current no-go branch, reuse `examples/p3-runtime/test_do_g6_general_boundary_rejection.sh`, `examples/p3-runtime/test_do_borrowed_resource_rejection.sh`, and `src/build/p3_async_manifest.zig`; do not create the candidate files above.

**Interfaces:**
- Consumes the registered descriptor conventions, existing `Result` source policy, and cleanup invariants.
- Produces either a fully specified private shape or a no-go record. It does not modify the compiler registry or emitter by itself.

- [x] **Step 1: Evaluate candidates against a fixed gate.**

  Consider exactly one candidate at a time from the remaining bounded extensions: a sixth helper-forwarding hop, one additional owned-resource nesting path, or another private descriptor shape supported by a canonical WIT definition. Reject any candidate that requires public ownership syntax, borrowed fields, arbitrary list/variant lowering, a scheduler redesign, or an unpinned tool behavior.

  The design must state the selected shape's descriptor name, function signature, result tags, frame offsets, alignment, payload ownership, drop order, pending/ready/error behavior, and the unsupported neighboring shapes.

  Result: the sixth forwarding hop, arbitrary producer, and borrowed stream
  candidates all remain rejected by existing pinned boundary gates; no
  candidate reached the green-shape branch.

- [x] **Step 2: Apply the canonical WIT/WAT probe gate.**

  Assemble and validate the probe with the pinned tools:

  ```bash
  bash examples/p3-runtime/test_g6_2_next_shape_probe.sh --assemble
  wasm-tools validate examples/p3-runtime/g6-2-next-shape.component.wasm
  ```

  Green-candidate path: the probe script must assemble `g6-2-next-shape.core.wat` with
  `examples/p3-runtime/wit/g6-2-next-shape.wit`, producing the fixed
  `g6-2-next-shape.component.wasm`. It must demonstrate the exact canonical
  tag/payload layout and must fail for the rejected neighboring shape rather
  than silently coercing it. Current no-go path: the existing
  `test_do_g6_general_boundary_rejection.sh` and
  `test_do_borrowed_resource_rejection.sh` already provide the pinned
  rejection evidence, so no new WIT/WAT files were created.

- [x] **Step 3: Apply the positive/negative fixture gate.**

  The positive fixture must use only the selected private descriptor and must compile to the expected import/result markers. Negative fixtures must cover at least an unknown descriptor, malformed result tag or arity, and duplicate or missing resource release when the shape owns a resource.

  ```bash
  ./bin/do build src/build/test/compile_ok/415_g6_2_next_shape.do -o /tmp/g6-2-next-shape.wat
  ./bin/do build src/build/test/compile_err/415_g6_2_next_shape_unknown.do -o /tmp/g6-2-next-shape-unknown.wat
  ./bin/do build src/build/test/compile_err/415_g6_2_next_shape_bad_arity.do -o /tmp/g6-2-next-shape-arity.wat
  ./bin/do build src/build/test/compile_err/415_g6_2_next_shape_duplicate_release.do -o /tmp/g6-2-next-shape-release.wat
  ```

  Green-candidate path expected: the positive fixture reaches the selected
  lowering boundary and every negative fixture reports the intended
  diagnostic. Current no-go path: existing sixth-forwarding and arbitrary-
  producer fixtures remain rejected, so no new positive fixture was added.

- [x] **Step 4: Apply the Rust/Wasmtime cleanup gate.**

  Green-candidate path: cover pending, immediate-ready, completion-error, and
  early-drop modes supported by the selected shape. Current no-go path: no
  runtime matrix was started because no shape passed the pinned admission
  gate; the existing runtime gates remain green.

- [x] **Step 5: Stop at the gate when evidence is insufficient.**

  The pinned boundary gates rejected the remaining candidates.
  `doc/pending_blocked.md` records the commands, rejection, and recovery
  condition. No registry entry was added and Task 4 was not started.

### Task 3: Maintain the D2 real-host matrix

**Files:**
- Inspect/modify: `examples/p3-runtime/test_do_wasi_sockets_create_bind_drop.sh`
- Inspect/modify: `examples/p3-runtime/test_rust_wasi_sockets_real.sh`
- Inspect/modify: existing local filesystem and CLI smoke scripts referenced by `examples/p3-runtime/d2-real-host-matrix.md`
- Modify: `examples/p3-runtime/d2-real-host-matrix.md` only with observed results
- Modify: `doc/pending_blocked.md` only if a gate regresses or a new residual is confirmed

**Interfaces:**
- Consumes compiler-generated Components already admitted by the current registry.
- Produces deterministic local-host evidence without changing the language or adding network access.

- [x] **Step 1: Run the socket real-host matrix.**

  ```bash
  bash examples/p3-runtime/test_do_wasi_sockets_create_bind_drop.sh
  bash examples/p3-runtime/test_rust_wasi_sockets_real.sh
  ```

  Require TCP and UDP success, forced create failure, forced bind failure, and empty resource tables after each run.

- [x] **Step 2: Re-run the admitted local-resource smoke tests.**

  ```bash
  bash examples/p3-runtime/test_rust_wasi_filesystem_real.sh
  bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory_real.sh
  bash examples/p3-runtime/test_rust_cli_stream_stdin_real.sh
  ```

  Require the existing temporary-file, sorted-directory, and local-pipe assertions to pass. Do not add `listen/connect/accept/send/receive`, general filesystem async, or external HTTP in this task.

- [x] **Step 3: Check Rust and shell hygiene.**

  ```bash
  cargo fmt --all --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml -- --check
  CC="$PWD/examples/p3-runtime/rust-host-runner/zig-cc.sh" \
  CXX="$PWD/examples/p3-runtime/rust-host-runner/zig-cc.sh" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/examples/p3-runtime/rust-host-runner/zig-cc.sh" \
  cargo check --locked --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml
  bash -n examples/p3-runtime/test_do_wasi_sockets_create_bind_drop.sh
  bash -n examples/p3-runtime/test_rust_wasi_sockets_real.sh
  git diff --check
  ```

### Task 4: Implement the selected G6.2 shape only after the gate is green

**Files:**
- Modify: `src/build/codegen_wasi_registry.zig`
- Modify: the one component emitter selected by the design: `src/build/codegen_component_async.zig`, `src/build/codegen_component_resource_async.zig`, `src/build/codegen_component_stream_writer.zig`, or `src/build/codegen_component_variant_resource_stream.zig`
- Modify: `src/build/test/compile_ok/415_g6_2_next_shape.do`
- Modify: `src/build/test/compile_err/415_g6_2_next_shape_unknown.do`
- Modify: `src/build/test/compile_err/415_g6_2_next_shape_unknown.expect`
- Modify: `examples/p3-runtime/test_g6_2_next_shape_probe.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_next_shape.rs`
- Modify: `doc/host_abi_blockers.md` with the measured ABI and cleanup proof

**Interfaces:**
- Consumes the approved descriptor, pinned layout, and negative boundaries from Task 2.
- Produces one bounded compiler lowering with no changes to public type syntax or unrelated async paths.

- [x] **Step 1: Add the failing emitter assertion.**

  Skipped by the Task 2 no-go gate; no emitter assertion was added.

- [x] **Step 2: Add the minimal registry and lowering branch.**

  Skipped by the Task 2 no-go gate; no descriptor or lowering branch was registered.

- [x] **Step 3: Run focused green checks.**

  ```bash
  cd src && zig test main.zig
  cd ..
  ./bin/do build src/build/test/compile_ok/415_g6_2_next_shape.do -o /tmp/g6-2-next-shape.wat
  bash examples/p3-runtime/test_g6_2_next_shape_probe.sh --runtime
  ```

  Skipped by the Task 2 no-go gate; existing G6.2 negative boundaries and
  the full regression matrix were rerun instead.

### Task 5: Close the phase with full verification and route updates

**Files:**
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/master_plan.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes all green results from Tasks 1-4, or the explicit no-go result from Task 2.
- Produces the next checked-in handoff state with no overclaiming.

- [x] **Step 1: Run the complete acceptance matrix.**

  ```bash
  cd src && zig test main.zig
  cd ..
  ./src/build/test/run_tests.sh
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  git diff --check
  ```

- [x] **Step 2: Update status using only observed evidence.**

  If Task 2 produced a no-go, keep G6.2 blocked and record the exact recovery condition. If Task 4 passed, record only the selected private descriptor and its tested matrix; leave general producer leases, borrowed/list/variant lowering, wider nesting/forwarding, full filesystem async, and public ownership syntax pending or deferred.

- [x] **Step 3: Handoff.**

  The next execution turn starts at the first unchecked task in this file. No commit, push, or worktree cleanup is part of this phase plan.

## Exit Criteria

The phase is complete when the release baseline is reproducible, the D2 admitted real-host matrix is green, and G6.2 has either one new bounded shape with pinned positive/negative/runtime evidence or an explicit no-go record. A green probe alone is not a compiler feature; registry and emitter changes require the separate Task 4 gate.
