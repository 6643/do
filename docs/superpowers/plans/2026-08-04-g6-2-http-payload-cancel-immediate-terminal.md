# G6.2 HTTP Payload Cancellation Immediate Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Safely discard an already-completed pinned HTTP `send` future when
`@cancel` is called, releasing an immediate owned response exactly once.

**Architecture:** Keep the existing private cancellation world and affine
`Future` semantics. The template passes a fixed, valid 64-byte canonical result
area to `[async-lower]send`; its `Status::Returned` branch decodes only
`Ok(own<response>)` and the already-proven payload-free `Err(DnsTimeout)`.
Pending cancellation continues through the existing subtask cancel/drop path.

**Tech Stack:** Zig compiler emitter tests, Do P3 component build, WAT,
wasm-tools, Rust 2024, Wasmtime component bindgen.

## Global Constraints

- Preserve the user's dirty worktree; do not reset, clean, commit, or push.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, implicit cancellation, or
  generic HTTP resource lowering.
- Do not change post-`await`, double-cancel, or scope-drop semantic diagnostics.
- Payload-bearing immediate errors must trap until a separate ABI/destruction
  probe defines their ownership protocol.

---

### Task 1: Make the ready-response leak observable

**Files:**
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/http_payload_cancel.rs`
- Modify: `examples/p3-runtime/test_rust_http_payload_cancellation.sh`
- Test: `examples/p3-runtime/test_rust_http_payload_cancellation.sh`

**Interfaces:**
- Consumes: a component path and a mode: `pending`, `ready-ok`, or
  `ready-dns-timeout`.
- Produces: counters for request consumption, host future drops, response
  creation/drop, and final `ResourceTable` emptiness.

- [x] **Step 1: Extend the Rust host fixture with a `ready-ok` mode.**

Make `main` parse the mode after the component path and pass it into host
state. In `HostClient::send`, consume the request exactly once. In `ready-ok`,
create `Response`, push it into `ResourceTable`, increment
`response_created`, and return `Ok(response_handle)` immediately. Keep the
existing pending future behavior byte-for-byte for `pending`.

- [x] **Step 2: Require the ready mode to prove resource balance.**

Run:

```bash
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_rust_http_payload_cancellation.sh
```

Before changing the compiler, `ready-ok` must fail because
`response create=1` and `response drop=0` (or a non-empty table). That failure
proves the fixture observes the missing immediate release rather than merely
checking generated WAT text.

- [x] **Step 3: Add a payload-free ready error control.**

Add `ready-dns-timeout` to the same host state and return the exact generated
`ErrorCode::DnsTimeout` variant without allocating a response or error payload.
The shell gate must execute the `pending` and `ready-ok` cases and may execute
the control only after the compiler decoder exists. Its markers must identify
the mode, so a pending result cannot accidentally satisfy ready expectations.

- [x] **Step 4: Format and syntax-check the fixture.**

Run:

```bash
rustfmt --edition 2024 --check examples/p3-runtime/rust-host-runner/src/bin/http_payload_cancel.rs
bash -n examples/p3-runtime/test_rust_http_payload_cancellation.sh
```

Expected: both exit zero; the runtime test remains red only for the missing
compiler resource drop.

### Task 2: Decode and discard the admitted immediate result arms

**Files:**
- Modify: `src/build/codegen_component_wasi_http.zig`
- Test: `src/build/codegen_component_wasi_http.zig`

**Interfaces:**
- Consumes: `[async-lower]send(request, result_area) -> subtask_or_returned`.
- Produces: an immediate branch that releases `Ok(response)`, accepts only
  `Err(DnsTimeout)`, and traps for every other error tag.

- [x] **Step 1: Add the compiler emitter assertions first.**

Extend the existing HTTP payload cancellation test to require all of:

```zig
try std.testing.expect(std.mem.indexOf(u8, wat, ";; [http-payload-cancel] canonical result area") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 64\n    call $send") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, ";; [http-payload-cancel] immediate ok response") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "call $drop-response") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, ";; [http-payload-cancel] immediate dns-timeout") != null);
```

Also require the immediate error default to contain `if unreachable end`, and
remove the obsolete assertion that no result buffer appears in this template.

- [x] **Step 2: Run the focused Zig test and observe its failure.**

Run:

```bash
cd src && zig test build/codegen_component_wasi_http.zig
```

Expected before implementation: the new cancellation marker assertions fail
because the template still passes `i32.const 0` and immediately task-returns.

- [x] **Step 3: Implement the minimum WAT decoder.**

In `http_payload_cancel_core_wat`, pass the fixed nonzero 64-byte scratch area
at address `64` as `$send`'s second parameter. In the `Status::Returned`
branch, load the result tag. The `Ok` arm loads `i32.load offset=8` and calls
`$drop-response`; the `Err` arm accepts only the pinned `DnsTimeout` tag and
uses `if unreachable end` for all other tags. Do not add a generic deallocator
because the fixed scratch area is part of the current module's memory.

- [x] **Step 4: Re-run focused compiler and runtime gates.**

Run:

```bash
cd src && zig test build/codegen_component_wasi_http.zig
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_do_http_payload_cancellation.sh
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_rust_resource_cancellation_shape.sh
```

Expected: compiler assertions pass, pending counts remain unchanged, ready
`Ok` reports one create and one drop with an empty table, and the independent
resource-cancellation shape stays green.

### Task 3: Record the bounded ABI result and run the regression suite

**Files:**
- Modify: `docs/superpowers/specs/2026-08-04-g6-2-http-payload-cancel-immediate-terminal-design.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Test: `src/build/test/run_tests.sh`

**Interfaces:**
- Consumes: successful runtime counters for pending and immediate `Ok`.
- Produces: a documented boundary that admits only `Ok(response)` and
  `Err(DnsTimeout)`; payload-bearing `Err` remains blocked by its own probe.

- [x] **Step 1: Update status text with verified facts only.**

Replace the design status with the verified mode matrix. Add one blocker entry
for payload-bearing immediate errors naming the missing allocation/destruction
probe. Do not present unrun `ready-dns-timeout` as runtime proven.

- [x] **Step 2: Run the complete compiler regression suite.**

Run:

```bash
./src/build/test/run_tests.sh
git diff --check
```

Expected: all default regression fixtures pass and the diff has no whitespace
errors. If unrelated dirty-worktree tests fail, report their files and output
without modifying or discarding them.

- [x] **Step 3: Mark plan tasks with actual verification outcomes.**

Only change checkboxes to `[x]` after their listed command succeeds. Leave a
failed or unavailable `ready-dns-timeout` control unchecked and document why.

### Task 4: Close Runtime Evidence Gaps Found in Review

**Files:**
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/http_payload_cancel.rs`
- Modify: `examples/p3-runtime/test_rust_http_payload_cancellation.sh`
- Modify: `src/build/codegen_component_wasi_http.zig`
- Modify: `docs/superpowers/specs/2026-08-04-g6-2-http-payload-cancel-immediate-terminal-design.md`
- Test: `examples/p3-runtime/test_rust_http_payload_cancellation.sh`

**Interfaces:**
- Consumes: the three admitted modes and the pinned `DNS-error` tag `1`.
- Produces: ready-host lifecycle counters, a runtime payload-error trap gate,
  and an ordered pending cancel/drop emitter assertion.

- [x] **Step 1: Add instrumented ready Future and payload-error modes.**

`ReadySend` records poll/drop once. The `ready-dns-error` mode returns
`DnsError(rcode=Some("EAI"), info_code=Some(7))`; it succeeds only when the
guest traps and still leaves the resource table empty.

- [x] **Step 2: Extend behavior assertions.**

The shell gate requires exact ready poll/drop counts and `expected trap=true`.
The Zig emitter test requires the pending `$subtask-cancel` call to precede
`$subtask-drop`.

- [x] **Step 3: Re-run the focused runtime and compiler gates.**

`ready-ok`, `ready-dns-timeout`, and `ready-dns-error` each record one ready
poll/drop; pending records no ready lifecycle events and one pending drop.

### Follow-on payload discard increment (2026-08-04)

After the dedicated canonical discard probe passed, the registered
`DNS-error` and `InternalError` optional-string arms became admissible. The
runtime matrix now treats their bounded `Some(nonempty)` and `None` cases as
normal completion. `None` validates the canonical option discriminant but does
not read or release pointer/length fields; empty strings and unregistered
payload-bearing tags remain explicit traps.
