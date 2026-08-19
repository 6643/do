# G6.2 Service-World Payload Error Follow-Up Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to execute this plan task by task. Do not skip a gate. Steps use checkbox syntax for tracking.

**Goal:** Resolve the service-world ABI mismatch that currently decodes `InternalError(Some("x"))` as `InternalError(None)`, then admit only the payload-bearing error variants that pass compiler, Component, and Rust/Wasmtime evidence.

**Architecture:** Keep the pinned canonical descriptor as the source of truth until a separate service-world probe proves that the handler task-return path has a different shape. First isolate the difference between the green probe-world path and the failing generated service-world path with hand-authored WAT and structural assertions. Only after that evidence is green should the HTTP emitter be changed; `DNS-error` remains a second, dependent increment.

**Tech Stack:** Zig 0.16 compiler/tests, Do WAT/WIT emitter, pinned `wasm-tools 1.254.0`, Rust 2024, Wasmtime `47.0.2`, Bash regression gates.

## Global Constraints

- Preserve the pinned WIT package at `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16` and Wasmtime/wasm-tools versions.
- Do not infer service-world layout from the already-known host-lowered `Some -> None` candidate.
- Keep unsupported payload-bearing error tags behind explicit `unreachable` guards.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Do not add arbitrary async-call lowering, general producer leases, scheduler work, or D2 host I/O.
- Preserve cancellation's no-rollback semantics and exactly-once cleanup.
- Preserve unrelated dirty worktree changes; do not reset, clean, checkout, commit, or push as part of this plan.
- A hand-authored WAT probe is evidence for the probe shape only; compiler support requires generated WAT, Component validation, and runtime assertions.

## Current Evidence and Stop Point

- `src/build/p3_async_manifest.zig` validates the registered `internal-error` and `DNS-error` descriptors.
- `src/build/codegen_component_async_plan.zig` carries `error_variants` into the HTTP plan.
- `src/build/codegen_component_wasi_http.zig:1648-1709` emits the descriptor-backed `internal-error` branch and retains traps for unadmitted tags.
- `examples/p3-runtime/test_do_http_payload_error_boundary.sh` and the ABI probe pass.
- `examples/p3-runtime/test_do_http_payload_error_lowering.sh` still fails in the generated `service` world:

  ```text
  Error: compiler service returned unexpected ErrorCode::InternalError(None) for internal-error-some
  ```

- The equivalent direct probe-world flat loads are green. No DNS lowering work starts until the service-world `InternalError(Some("x"))` case is green in both `pending` and `ready` delivery modes.

## File Map

| File | Responsibility |
| --- | --- |
| `examples/p3-runtime/http-payload-error-service-world.wat` | Minimal hand-authored handler-world candidate used to isolate task-return and result-buffer shape. |
| `examples/p3-runtime/test_http_payload_error_service_world.sh` | Assemble, validate, and run the service-world ABI candidates; records exact observations instead of normalizing mismatches. |
| `examples/p3-runtime/rust-host-runner/src/bin/http_payload_error_abi.rs` | Add an explicit service-probe mode and retain the generated compiler-service matrix. |
| `examples/p3-runtime/test_do_http_payload_error_lowering.sh` | Generated-WAT, Component, pending/ready, payload-value, cleanup, and table-empty gate. |
| `examples/p3-runtime/test_do_http_payload_error_boundary.sh` | Negative guard that proves every unadmitted error tag still traps. |
| `src/build/codegen_component_wasi_http.zig` | Handler-world task-return emission and any proven service-world correction. |
| `src/build/p3_async_manifest.zig` | Exact payload descriptor validation; only widen it if the service probe proves a distinct shape. |
| `src/build/codegen_component_async_plan.zig` | Carry any explicitly proven service-world descriptor without affecting unrelated async plans. |
| `doc/host_abi_blockers.md`, `doc/pending_blocked.md`, `doc/roadmap_status.md`, `doc/wit/wasi_p3_lowering.md` | Evidence and residual-boundary synchronization after green gates. |

### Task 1: Freeze the failing service-world baseline

**Files:**

- Verify: `examples/p3-runtime/test_http_payload_error_abi.sh`
- Verify: `examples/p3-runtime/test_do_http_payload_error_boundary.sh`
- Verify: `examples/p3-runtime/test_do_http_payload_error_lowering.sh`
- Verify: `examples/p3-runtime/rust-host-runner/src/bin/http_payload_error_abi.rs`

**Interfaces:**

- Consumes the current descriptor-driven generated WAT and the pinned Rust runner.
- Produces a fresh baseline proving probe-world green, service-world `Some -> None` red, and no resource leak.

- [ ] **Step 1: Run the independent probe and negative boundary.**

  ```bash
  TMPDIR="$PWD/.tmp/payload-runtime" bash examples/p3-runtime/test_http_payload_error_abi.sh
  TMPDIR="$PWD/.tmp/payload-runtime" bash examples/p3-runtime/test_do_http_payload_error_boundary.sh
  ```

  Expected: both pass; the ABI script must keep the known host-lowered mismatch explicit.

- [ ] **Step 2: Re-run the generated service gate and capture the red assertion.**

  ```bash
  TMPDIR="$PWD/.tmp/payload-runtime" bash examples/p3-runtime/test_do_http_payload_error_lowering.sh
  ```

  Expected before the fix: `internal-error-none` passes and `internal-error-some` reports `InternalError(None)` in at least one delivery mode. Do not weaken the expected value to `None`.

- [ ] **Step 3: Verify toolchain and source hygiene.**

  ```bash
  cd src && zig test build/p3_async_manifest.zig
  cd src && zig test build/codegen_component_async_plan.zig
  cd src && zig test build/codegen_component_wasi_http.zig
  cargo check --locked --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml
  rustfmt --edition 2024 --check examples/p3-runtime/rust-host-runner/src/bin/http_payload_error_abi.rs
  git diff --check
  ```

  Acceptance: all focused checks pass independently of the known service-world runtime mismatch.

### Task 2: Isolate the handler task-return ABI with a minimal service-world probe

**Files:**

- Create: `examples/p3-runtime/http-payload-error-service-world.wat`
- Create: `examples/p3-runtime/test_http_payload_error_service_world.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/http_payload_error_abi.rs`

**Interfaces:**

- Consumes the pinned `service` world and the existing ResourceTable/request host setup.
- Produces machine-checkable observations for handler-world `InternalError(None)`, `InternalError(Some("x"))`, and the no-payload `DnsTimeout` control.

- [ ] **Step 1: Add a service-probe runner mode.**

  Add a separate command mode, for example:

  ```text
  do-p3-http-payload-error-abi-host-runner <component> service-probe internal-error-some pending
  ```

  It must call the exported `wasi:http/handler.handle`, print the decoded error, request/response counters, and `table-empty`, and return nonzero for a trap, an unexpected value, or a leak. Keep `compiler-service` unchanged so the generated failure remains independently observable.

- [ ] **Step 2: Author the smallest handler-world Core module.**

  Keep only the imports required by the `service` world, the handler task-return import, one request-consuming path, and one completion callback. Use the same canonical optional-string bytes (`tag=1`, pointer word, length word) and test the following candidates as separate script invocations:

  ```text
  InternalError(None)
  InternalError(Some("x"))
  DnsTimeout
  ```

  Do not add compiler-specific frame logic to this probe; the purpose is to determine whether handler task-return uses a different discriminant, buffer base, or callback event contract.

- [ ] **Step 3: Assemble and validate every candidate.**

  ```bash
  WASM_TOOLS=wasm-tools TMPDIR="$PWD/.tmp/payload-runtime" \
    bash examples/p3-runtime/test_http_payload_error_service_world.sh
  ```

  The script must report the exact candidate, discriminant, payload stores, decoded value, and `table-empty=true`. A trap or a changed `Some` value is a blocked result, not a passing control case.

- [ ] **Step 4: Record the ABI decision before touching the emitter.**

  If a hand-authored handler candidate decodes `Some("x")`, record its exact task-return parameter order, result discriminant, canonical buffer offset, and callback event in `doc/host_abi_blockers.md`. If no candidate does, record the pinned toolchain rejection and leave compiler lowering blocked; do not guess a layout.

### Task 3: Compare generated handler code against the proven candidate

**Files:**

- Verify/modify only as evidence requires: `src/build/codegen_component_wasi_http.zig:1570-1615,1648-1709,2210-2423`
- Modify: `examples/p3-runtime/test_do_http_payload_error_lowering.sh`
- Modify: `examples/p3-runtime/test_do_http_payload_error_boundary.sh`

**Interfaces:**

- Consumes the exact service-world candidate from Task 2 and generated `http-service.do` WAT.
- Produces structural assertions that pinpoint the first divergence: import signature, callback event, result-buffer base, discriminant, payload offset, or cleanup ordering.

- [ ] **Step 1: Add structural assertions before runtime assertions.**

  The lowering gate must check the generated handler import and type, the callback's event/index/payload tests, the `$slot-result-ptr` loads, the `InternalError` discriminant, and the single cleanup sequence (`canonical-buffer-release`, `context-set-0`, `frame-free`). Keep the existing assertions that unadmitted tags retain `unreachable`.

- [ ] **Step 2: Compare one generated WAT with the green hand-authored candidate.**

  Use `diff`/targeted `rg` over the exact task-return and result-buffer blocks. Identify the first byte/word that differs; do not patch downstream loads until the task-return contract is known.

- [ ] **Step 3: Apply only the proven correction.**

  If the service world uses the same descriptor, correct the handler template in `codegen_component_wasi_http.zig` and keep the descriptor unchanged. If it uses a distinct shape, add an explicit service-world descriptor field in `p3_async_manifest.zig`, validate it in `codegen_component_async_plan.zig`, and consume that field from the emitter. In either case, reject missing or inconsistent service metadata with the existing `UnsupportedP3AsyncHttpService` path; never silently fall back to probe-world offsets.

- [ ] **Step 4: Run focused compiler tests.**

  ```bash
  cd src && zig test build/codegen_component_wasi_http.zig
  cd src && zig test build/codegen_component_async_plan.zig
  cd src && zig test build/p3_async_manifest.zig
  ```

  Acceptance: structural tests pass and every unsupported payload tag still has an explicit trap.

### Task 4: Close `InternalError(option<string>)` end to end

**Files:**

- Modify: `examples/p3-runtime/test_do_http_payload_error_lowering.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/http_payload_error_abi.rs`
- Modify: `src/build/codegen_component_wasi_http.zig` only if Task 3 identified a correction

**Interfaces:**

- Consumes the proven service-world ABI and descriptor from Tasks 2-3.
- Produces a green compiler Component gate for `InternalError(None)` and `InternalError(Some("x"))` in both `pending` and `ready` delivery modes.

- [ ] **Step 1: Assert both values in both delivery modes.**

  ```bash
  for delivery in pending ready; do
    for case_name in internal-error-none internal-error-some; do
      # invoke the generated compiler-service runner with "$case_name" "$delivery"
      # and require the exact decoded value, request-consumed=1,
      # response-created=0, response-dropped=0, table-empty=true.
    done
  done
  ```

  The checked-in shell gate must contain concrete invocations and `grep -Fq` assertions for both exact values; it must not accept a generic `InternalError(...)` substring.

- [ ] **Step 2: Preserve the negative boundary and cleanup invariant.**

  Run the boundary gate and inspect generated WAT for one cleanup epilogue per terminal path. A response must never be created for either error value, and all request/resource handles must be released exactly once.

- [ ] **Step 3: Run the green gate.**

  ```bash
  TMPDIR="$PWD/.tmp/payload-runtime" bash examples/p3-runtime/test_do_http_payload_error_lowering.sh
  ```

  Acceptance: the script exits zero and prints both exact values for `pending` and `ready`. If it fails, stop DNS work and retain the explicit blocker.

### Task 5: Extend the proven path to `DNS-error` only after Task 4 is green

**Files:**

- Modify/test: `src/build/p3_async_manifest.zig`
- Modify/test: `src/build/codegen_component_async_plan.zig`
- Modify/test: `src/build/codegen_component_wasi_http.zig`
- Modify: `examples/p3-runtime/test_do_http_payload_error_lowering.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/http_payload_error_abi.rs`

**Interfaces:**

- Consumes the service-world optional-string lowering proven by Task 4 and the registered DNS descriptor.
- Produces exact `rcode=Some("EAI")`, `info-code=Some(7)`, and `None/None` decoding with the same pending/ready and cleanup guarantees.

- [ ] **Step 1: Add red validation cases.**

  Require field order `rcode`, `info-code`, offsets `16` and `28`, `rcode` as optional string, `info-code` as optional `u16`, and the registered byte size. Reject reordered fields, wrong offsets, overlapping fields, wrong byte size, and missing optional fields.

- [ ] **Step 2: Emit only descriptor-backed DNS loads.**

  Load the string option discriminant/pointer/length from the validated offsets, load the `u16` option discriminant with `i32.load8_u`, load its value with `i32.load16_u`, emit the exact residual zero tail, and route the result through the same cleanup epilogue as `InternalError`.

- [ ] **Step 3: Run the DNS runtime matrix.**

  Require `DnsError(rcode=Some("EAI"),info-code=Some(7))` and the `None/None` case in pending and ready modes, zero response creation/drop, exactly-once request consumption, and `table-empty=true`. Keep all other payload tags rejected.

### Task 6: Full verification and documentation closeout

**Files:**

- Modify only after all prior gates are green: `doc/host_abi_blockers.md`, `doc/pending_blocked.md`, `doc/roadmap_status.md`, `doc/wit/wasi_p3_lowering.md`, `README.md`, `CHANGELOG.md`

**Interfaces:**

- Consumes fresh focused-gate output from Tasks 1-5.
- Produces an auditable supported boundary and an explicit residual blocker list.

- [ ] **Step 1: Run the focused matrix.**

  ```bash
  cd src && zig test build/p3_async_manifest.zig
  cd src && zig test build/codegen_component_async_plan.zig
  cd src && zig test build/codegen_component_wasi_http.zig
  TMPDIR="$PWD/.tmp/payload-runtime" bash examples/p3-runtime/test_http_payload_error_abi.sh
  TMPDIR="$PWD/.tmp/payload-runtime" bash examples/p3-runtime/test_http_payload_error_service_world.sh
  TMPDIR="$PWD/.tmp/payload-runtime" bash examples/p3-runtime/test_do_http_payload_error_boundary.sh
  TMPDIR="$PWD/.tmp/payload-runtime" bash examples/p3-runtime/test_do_http_payload_error_lowering.sh
  cargo check --locked --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml
  git diff --check
  ```

- [ ] **Step 2: Run repository regression/build checks.**

  ```bash
  ./src/build/test/run_tests.sh
  cd src && zig build -Doptimize=ReleaseSmall
  ```

  Record unrelated failures separately; do not weaken payload-error assertions to make the matrix green.

- [ ] **Step 3: Synchronize evidence.**

  Document the exact service-world task-return shape, admitted variants, offsets/discriminants, pinned tool versions, and the remaining explicit rejection boundary. If Task 2 cannot prove a service-world mapping, leave the payload lowering status blocked and document the exact observation instead of claiming partial support.

## Completion Audit

- [ ] Service-world ABI candidate is reproducible and its exact task-return shape is recorded.
- [ ] Generated service WAT matches the proven candidate at import, callback, payload, and cleanup boundaries.
- [ ] `InternalError(None)` and `InternalError(Some("x"))` pass pending/ready compiler Component and Rust/Wasmtime gates.
- [ ] DNS payload values pass only after the InternalError gate is green.
- [ ] Unsupported payload tags still trap explicitly.
- [ ] Request/resource cleanup is exactly once and `table-empty=true` in every admitted case.
- [ ] Documentation distinguishes verified support from the host-lowered mismatch and any remaining blocker.

## Stop Conditions

- Any hand-authored service candidate traps or changes `Some("x")` to `None`.
- Any generated service path returns an unexpected discriminant, payload, or resource count.
- Any unsupported tag loses its explicit `unreachable` guard.
- Any full-suite failure is unrelated to this phase; record it separately and do not bypass the focused gate.
