# G6.2 HTTP Payload Cancellation Discard Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the exact canonical allocation and guest-side destruction
protocol for an immediate `DNS-error(Some("EAI"))` completion before admitting
payload discard to compiler-generated cancellation lowering.

**Architecture:** A hand-authored WAT probe shares the existing private
`http-payload-cancel` Component world but replaces the compiler fixture's
unreachable `cabi_realloc` export with a one-allocation verifier. Its immediate
branch validates the fixed error layout and performs the only permitted string
free. The existing Rust host runner supplies the error and asserts future and
resource balance.

**Tech Stack:** WAT, wasm-tools Component assembly, Rust 2024, Wasmtime async
Component bindings, Zig emitter regression tests.

## Global Constraints

- Preserve the dirty worktree; do not reset, clean, commit, or push.
- Do not modify Do source syntax, resource ownership semantics, or the existing
  compiler cancellation template until the probe is green.
- Use only the pinned `DNS-error(Some("EAI"), Some(7))` layout from the
  registered HTTP descriptor.
- At the initial probe checkpoint, the generated `ready-dns-error` gate remains
  an explicit trap; a later bounded compiler increment may admit only shapes
  backed by the same allocation/free evidence.

---

### Task 1: Add the negative runtime expectation

**Files:**
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/http_payload_cancel.rs`
- Create: `examples/p3-runtime/test_rust_http_payload_cancellation_dns_error_probe.sh`
- Test: `examples/p3-runtime/test_rust_http_payload_cancellation_dns_error_probe.sh`

**Interfaces:**
- Consumes: `<component.wasm> ready-dns-error --expect-dns-error-discard`.
- Produces: normal completion only for a probe that proves one guest-side
  payload release; the original two-argument invocation retains its trap
  expectation.

- [x] **Step 1: Write the new shell gate before the probe WAT exists.**

  Assemble `examples/p3-runtime/http-payload-cancel-dns-error-discard-probe.wat`
  against a temporary copy of the existing `http-payload-cancel` WIT package,
  build `http_payload_cancel`, and call:

  ```bash
  "$runner_dir/target/debug/http_payload_cancel" \
    "$component" ready-dns-error --expect-dns-error-discard
  ```

  Require the normal-return markers for one request, ready poll/drop `1/1`,
  zero response create/drop, and `table-empty=true`.

- [x] **Step 2: Run the gate and observe its red failure.**

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" \
    bash examples/p3-runtime/test_rust_http_payload_cancellation_dns_error_probe.sh
  ```

  Expected: failure because the WAT input is absent (or later because its
  allocator has not proven a matching release). Do not loosen the existing trap
  assertion in `test_rust_http_payload_cancellation.sh`.

- [x] **Step 3: Extend the runner's explicit expectation flag.**

  Parse an optional third argument exactly equal to
  `--expect-dns-error-discard`; reject it for modes other than
  `ready-dns-error`. Set `expected_trap` to false only for that explicit case.
  Preserve the current two-argument behavior byte-for-byte.

- [x] **Step 4: Format and execute the still-red gate.**

  Run:

  ```bash
  rustfmt --edition 2024 --check \
    examples/p3-runtime/rust-host-runner/src/bin/http_payload_cancel.rs
  TMPDIR="$PWD/.tmp/do-tmp" \
    bash examples/p3-runtime/test_rust_http_payload_cancellation_dns_error_probe.sh
  ```

  Expected: formatting passes; runtime gate remains red until Task 2 adds the
  probe Core module.

### Task 2: Implement a single-allocation Core ABI verifier

**Files:**
- Create: `examples/p3-runtime/http-payload-cancel-dns-error-discard-probe.wat`
- Test: `examples/p3-runtime/test_rust_http_payload_cancellation_dns_error_probe.sh`

**Interfaces:**
- Consumes: the existing `wasi:http/client.[async-lower]send` import and
  `Status::Returned` result area at address `64`.
- Produces: normal `[task-return]cancel` only after exact
  `cabi_realloc(0,0,1,3)` and `cabi_realloc(pointer,3,1,0)` events.

- [x] **Step 1: Copy only the required private cancellation imports.**

  Define the same `async-lower-send`, HTTP request/response drop, root task,
  waitable, and subtask import signatures used by
  `http_payload_cancel_core_wat`. Export `[async-lift]cancel`, its callback,
  memory, `cabi_realloc`, and `_initialize`; retain a no-op task-return shape.

- [x] **Step 2: Add exact allocation and release assertions.**

  Use mutable globals for `allocated_ptr`, `allocation_count`, and
  `release_count`. In exported `cabi_realloc`, accept only:

  ```wat
  ;; allocation
  (0, 0, 1, 3) -> 1024
  ;; release
  (1024, 3, 1, 0) -> ignored
  ```

  Every other combination and every duplicate allocation/release must execute
  `unreachable`. The release branch increments `release_count` only after all
  arguments match.

- [x] **Step 3: Decode and discard the immediate DNS payload.**

  Call `$send` with `(request, 64)`, require returned status `2`, validate
  result/error/optional discriminants at `64`, `72`, and `80`, validate the
  pointer/length at `84`/`88`, validate bytes `E`, `A`, `I`, and validate
  `info-code` at `92`/`94`. Invoke `$cabi-realloc` with the loaded pointer and
  length plus `(1, 0)`, then require both counters equal `1` before task return.

- [x] **Step 4: Run the targeted green gate.**

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" \
    bash examples/p3-runtime/test_rust_http_payload_cancellation_dns_error_probe.sh
  ```

  Expected: normal completion with ready poll/drop `1/1`, zero response events,
  and an empty host resource table.

### Task 3: Preserve the negative boundary and document the evidence

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Test: `examples/p3-runtime/test_rust_http_payload_cancellation.sh`

**Interfaces:**
- Consumes: Task 2's exact runtime evidence.
- Produces: a narrow record that the `DNS-error` string destruction protocol is
  proven, without claiming compiler lowering or general payload cancellation.

- [x] **Step 1: Run the existing generated-fixture negative gate.**

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" \
    bash examples/p3-runtime/test_rust_http_payload_cancellation.sh
  ```

  Expected at this probe checkpoint: `ready-dns-error` still prints
  `expected trap=true`; pending, ready-OK, and `DnsTimeout` remain green.

- [x] **Step 2: Record the precise evidence and residual restriction.**

  In both blocker documents, state that the isolated hand WAT proved the
  `Some("EAI")` string allocation/free sequence, while this probe plan itself
  still records the compiler template's then-current payload trap. State that
  every other error variant, dynamic string length, `None`, records with
  resources, and generic payload destruction remain unsupported at that
  checkpoint.

- [x] **Step 3: Run final focused verification.**

  Run:

  ```bash
  cd src && zig test build/codegen_component_wasi_http.zig
  TMPDIR="$PWD/.tmp/do-tmp" \
    bash examples/p3-runtime/test_rust_http_payload_cancellation_dns_error_probe.sh
  TMPDIR="$PWD/.tmp/do-tmp" \
    bash examples/p3-runtime/test_rust_http_payload_cancellation.sh
  rustfmt --edition 2024 --check \
    examples/p3-runtime/rust-host-runner/src/bin/http_payload_cancel.rs
  bash -n examples/p3-runtime/test_rust_http_payload_cancellation_dns_error_probe.sh
  git diff --check
  ```

Expected: all focused commands pass. Do not run or claim the repository-wide
matrix until a later compiler-lowering change makes it relevant.

### Follow-on bounded optional-string increment (2026-08-04)

The subsequent compiler increment consumed the same proven protocol for the
registered `DNS-error.rcode` and `InternalError` optional strings. `Some` with a
nonempty string reads and releases the canonical pointer/length exactly once;
`None` validates only the discriminant and skips pointer/length reads entirely.
The Rust/Wasmtime matrix now includes `ready-dns-error-none` and
`ready-internal-error-none`; empty strings, unregistered variants, and generic
payload destruction remain explicit traps.
