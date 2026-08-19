# G6.2 Payload Error Lowering Next-Phase Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to execute this plan task by task. Do not skip a gate.

**Goal:** Move the verified payload-error ABI probe into descriptor-driven Do compiler lowering for two exact `wasi:http` error shapes, while retaining explicit rejection for every unproven payload shape.

**Status:** The bounded `InternalError` and `DNS-error` lowering is complete and
verified. Payload cancellation interaction remains outside this plan's green
boundary and is tracked as a separate follow-up.

**Architecture:** `p3_async_manifest.zig` remains the ABI source of truth. It validates an exact nested payload descriptor, `codegen_component_async_plan.zig` carries that descriptor into the HTTP plan, and `codegen_component_wasi_http.zig` emits only the descriptor-backed branches. Each admitted branch must pass compiler WAT, Component assembly, Rust/Wasmtime value, cancellation, and cleanup gates before the next branch is enabled.

**Tech Stack:** Zig compiler and unit tests, Do fixtures, WAT/WIT, pinned `wasm-tools 1.254.0`, Wasmtime `47.0.2`, Rust 2024 runner, Bash gates.

## Global Constraints

- The canonical task-return ABI observed by the probe is authoritative; do not infer a payload layout from a host-lowered mismatch.
- Keep the current explicit `unreachable` boundary for all payload-bearing error variants until their exact descriptor and runtime matrix are green.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Do not add general async-call lowering, arbitrary producer expressions, scheduler work, or real D2 host integration.
- Preserve cancellation's existing no-rollback semantics and exactly-once cleanup.
- Preserve all unrelated dirty worktree changes. Do not clean, reset, or commit unrelated files.
- A green hand-authored WAT probe is not compiler support; compiler support requires all gates below.

## Starting Evidence

- Pinned assembly and Rust runner checks are already green for the probe's control and canonical payload observations.
- The host-lowered candidate still maps `InternalError(Some("x"))` to `InternalError(None)`, so the compiler must not reuse that candidate.
- The existing HTTP emitter uses an eight-word task-return completion signature and traps on unproven payload tags.
- No user design decision is required for this phase; the admitted scope is limited to the two payload shapes proven by the pinned probe.

### Task 1: Reproduce and freeze the ABI gate

**Files:**
- Verify: `examples/p3-runtime/test_http_payload_error_abi.sh`
- Verify: `examples/p3-runtime/http-payload-error-canonical.wat`
- Verify: `examples/p3-runtime/http-payload-error-host-lowered.wat`
- Verify: `examples/p3-runtime/rust-host-runner/src/bin/http_payload_error_abi.rs`

**Deliverable:** A repeatable baseline that distinguishes canonical success from the host-lowered mismatch before compiler edits begin.

- [x] Run `WASM_TOOLS=wasm-tools bash examples/p3-runtime/test_http_payload_error_abi.sh --assemble-only`.
- [x] Run the default probe and record the exact `event`, discriminant, payload offsets, and `table-empty=true` observations.
- [x] Confirm the script reports the known host-lowered `Some` to `None` mismatch rather than normalizing it to green.
- [x] Run `cargo check --locked`, `rustfmt --check`, `bash -n`, and `git diff --check` for the probe files.
- [x] No stop condition was triggered: control and canonical cases remain green, the mismatch remains blocked, and all resource tables are empty.

### Task 2: Add descriptor-first nested payload metadata

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Test: `src/build/p3_async_manifest.zig`
- Modify: `src/build/codegen_component_async_plan.zig`
- Test: `src/build/codegen_component_async_plan.zig`

**Interfaces:**
- Consumes: the exact canonical discriminants, offsets, byte sizes, and completion words from Task 1.
- Produces: a validated `ErrorVariantPayload` attached to the HTTP send descriptor and carried by the async plan.

- [x] Add `ErrorVariantFieldKind` with only `optional_string` and `optional_u16`.
- [x] Add `ErrorVariantField` with `name`, `kind`, `core_words`, and `offset`.
- [x] Add `ErrorVariantPayload` with `variant`, `discriminant`, `byte_size`, and ordered `fields`.
- [x] Parse the descriptor from the existing canonical JSON shape without changing scalar `ResultPayload` behavior.
- [x] Reject missing descriptors, unknown variants, duplicate field names, unsupported field kinds, empty `core_words`, zero-sized records, overlapping fields, wrong offsets, and completion-word mismatches.
- [x] Add accepted `InternalError(option<string>)` and `DNS-error(rcode: option<string>, info-code: option<u16>)` fixtures.
- [x] Add rejected fixtures for missing metadata, wrong offset, reordered DNS fields, and host-lowered `None` substitution.
- [x] Thread the validated descriptor through the HTTP async plan without widening unrelated async plans.
- [x] Run `cd src && zig test build/p3_async_manifest.zig` and `cd src && zig test build/codegen_component_async_plan.zig` (`66/66` and `140/140`).

### Task 3: Admit `internal-error(option<string>)`

**Files:**
- Modify: `src/build/codegen_component_wasi_http.zig`
- Test: `src/build/codegen_component_wasi_http.zig`
- Create or modify: `examples/p3-runtime/test_do_http_payload_error_lowering.sh`
- Use: `examples/p3-runtime/test_http_payload_error_abi.sh` (combined Rust/Wasmtime matrix)
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/http_payload_error_abi.rs`

**Interfaces:**
- Consumes: the descriptor and plan metadata from Task 2.
- Produces: compiler-generated canonical task-return words preserving both `None` and `Some("x")`.

- [x] Add a red emitter assertion that requires the `internal-error` branch to contain descriptor-backed optional-string stores and no `unreachable`.
- [x] Replace only the `InternalError` payload guard; retain traps for every other payload-bearing error tag.
- [x] Use the exact canonical optional-string discriminant, offset, and string data representation from Task 1.
- [x] Route both pending and ready completions through the existing context clear, canonical-buffer release, and frame-free helpers exactly once.
- [x] Generate WAT from `examples/p3-runtime/http-service.do`, parse it, embed the pinned WIT package, create and validate the Component.
- [x] Assert the generated WAT no longer traps for `InternalError` but still traps for every unadmitted tag.
- [x] Extend the Rust/Wasmtime matrix with `InternalError(None)` and `InternalError(Some("x"))`, success response creation/drop counts, and `table-empty=true`; payload cancellation remains a separate boundary.
- [x] Run the focused Zig test, Do lowering gate, Rust runtime gate, and `git diff --check`.
- [x] InternalError exact-value, pending/ready, cleanup, and explicit rejection gates passed, so DNS lowering proceeded.

### Task 4: Admit `DNS-error(DNS-error-payload)`

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/codegen_component_async_plan.zig`
- Modify: `src/build/codegen_component_wasi_http.zig`
- Test: `src/build/p3_async_manifest.zig`
- Test: `src/build/codegen_component_wasi_http.zig`
- Modify: `examples/p3-runtime/test_do_http_payload_error_lowering.sh`
- Use: `examples/p3-runtime/test_http_payload_error_abi.sh` (combined Rust/Wasmtime matrix)

**Interfaces:**
- Consumes: the optional-string lowering and exact DNS record layout from Tasks 2-3.
- Produces: exact `rcode` and `info-code` payload lowering, with all other payload tags still rejected.

- [x] Validate DNS field order, `rcode` optional-string representation, `info-code` byte discriminant loaded with `i32.load8_u`, `u16` loaded with `i32.load16_u`, offsets, and record byte size.
- [x] Add red tests for reordered fields, unaligned offsets, wrong byte size, and missing optional fields.
- [x] Emit the DNS branch through the same terminal cleanup helper used by `InternalError`.
- [x] Test `Some("EAI")/Some(7)` and `None/None` through pending and ready completion paths.
- [x] Assert no response is created for error results, exactly-once drops, and `table-empty=true`; payload cancellation interaction remains outside this gate.
- [x] Keep unsupported payload tags as explicit `unreachable` and assert their guards remain in generated WAT.
- [x] Run both focused Zig tests and both Component/Rust gates.

### Task 5: Release gate and evidence synchronization

**Files:**
- Modify only after green verification: `doc/host_abi_blockers.md`
- Modify only after green verification: `doc/roadmap_status.md`
- Modify only after green verification: `doc/start_here.md`
- Modify only after green verification: `doc/wit/wasi_p3_lowering.md`
- Modify only after green verification: `CHANGELOG.md`

**Deliverable:** Documentation that names exactly what is admitted and what remains blocked.

- [x] Record the probe result, pinned versions, exact admitted variants, discriminants, offsets, and completion words.
- [x] Record remaining unsupported payload variants and retain the explicit trap boundary.
- [x] Keep public ownership/reference syntax, general producer leases, arbitrary async calls, D2 host integration, and payload cancellation interaction listed as deferred or pending.
- [x] Run the focused suite first:

  ```bash
  cd src && zig test main.zig
  cd src && zig test build/p3_async_manifest.zig
  cd src && zig test build/codegen_component_async_plan.zig
  cd src && zig test build/codegen_component_wasi_http.zig
  bash examples/p3-runtime/test_http_payload_error_abi.sh
  bash examples/p3-runtime/test_do_http_payload_error_lowering.sh
  bash examples/p3-runtime/test_http_payload_error_service_world.sh
  ```

- [x] Run the repository matrix only after focused gates pass:

  ```bash
  ./src/build/test/run_tests.sh
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  cd src && zig build -Doptimize=ReleaseSmall
  cargo check --locked --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml
  git diff --check
  ```

- [x] Report counts from fresh command output; do not copy historical counts if the fixture set changed: default `pass=1068 fail=0 skip=3`, WASM `pass=1070 fail=0 skip=3`, emitter `189/189`, manifest `66/66`, async plan `140/140`.

## Stop Conditions

- Any canonical payload value changes, becomes `None`, traps, or leaks a resource.
- Any unsupported payload tag loses its explicit rejection.
- The descriptor does not match the pinned probe exactly.
- A full regression failure is unrelated to this phase; record it separately and do not weaken the new gates.

## Completion Audit

- [x] Canonical probe baseline is reproducible and its host-lowered mismatch remains explicit.
- [x] Manifest metadata is validated and threaded into the HTTP plan.
- [x] `InternalError(option<string>)` passes compiler, Component, and Rust/Wasmtime gates.
- [x] `DNS-error(DNS-error-payload)` passes compiler, Component, and Rust/Wasmtime gates.
- [x] Pending, ready, error, cleanup, and empty-resource-table behavior are covered; payload cancellation interaction is explicitly not yet covered.
- [x] Documentation states the exact supported boundary and residual blockers.

## Residual Boundary

- Payload cancellation interaction is not admitted by the current HTTP emitter;
  the separate private no-payload resource cancellation slice remains the only
  cancellation lowering gate.
- General/unregistered payload variants, arbitrary HTTP body/trailer shapes,
  public ownership/reference syntax, and general async composition remain
  explicitly rejected or deferred.
