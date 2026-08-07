# `future<own<T>>` Canonical ABI Probe Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish one independently reproducible Component/Rust/Wasmtime
runtime gate for `future<own<ticket>>` while keeping ownership types outside Do
source and the compiler registry.

**Architecture:** Use a pinned WIT world and hand-authored Core WAT. The WAT
keeps the canonical payload at frame `+12`, stores the resource representation
at `+16`, and tracks presence at `+20` so representation `0` remains valid.
The Rust host supplies a `FutureProducer<State>` and a `ticket` resource drop
callback. Ready, pending-once, and pending-then-cancel modes assert exactly-once
future/resource cleanup.

**Toolchain:** `wasm-tools 1.255.0`, Wasmtime `47.0.2`, Rust host runner, Bash.

## Constraints

- Do source remains pointer/reference-free; no public `own<T>`, `borrow<T>`, or
  `ref<T>` syntax.
- Do not modify the compiler registry, generic lowering, or default v1 target.
- Preserve the negative borrowed stream/future capability rows.
- Treat this as one private ABI/runtime slice, not generic async support.
- Preserve unrelated dirty worktree changes.

## Task 1: Reproduce the failing runtime gate

**Files:** existing WIT/WAT/Rust gate.

- [x] Run the gate with `wasm-tools 1.255.0` and record the trap at
  `accept-read`.
- [x] Trace the first resource representation to Wasmtime's
  `ResourceTable::push`, which returns `entries.len()` and therefore `0` for an
  empty table.
- [x] Trace the callback contract: callback parameter three is encoded
  `ReturnCode`, while the result payload is written to the destination passed
  to `future.read`.

## Task 2: Add the ownership-presence fix

**Files:**

- Modify: `examples/p3-runtime/future-owned-canonical.wat`
- Modify: `examples/p3-runtime/test_future_owned_canonical_abi.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/future_owned_canonical_abi.rs`

- [x] Add the `+20` `ticket-present` marker and require it in the shell gate.
- [x] Make release logic test the presence bit, clear it before drop, and allow
  ticket representation `0`.
- [x] Add a callback-specific completion/cancellation path. Completion decodes
  frame `+12`; cancellation code `2` cleans up without claiming a ticket.
- [x] Report both payload and presence offsets from the Rust runner.

## Task 3: Verify the runtime matrix

- [x] Run:

  ```bash
  WASM_TOOLS_EXPECT_VERSION=1.255.0 \
    bash examples/p3-runtime/test_future_owned_canonical_abi.sh
  ```

- [x] Require ready, pending, and cancel output markers with an empty
  `ResourceTable` and exactly-once drops.
- [x] Run `rustfmt --edition 2024` on the new runner and check the focused gate
  again.

## Task 4: Record the boundary and repository checks

**Files:**

- Create: this plan and the matching spec.
- Modify: `doc/pending_blocked.md`
- Modify: `doc/host_abi_blockers.md`

- [x] Record the private runtime checkpoint after the focused gate is green.
- [x] Run the focused owned/capability/list/v2 gates, Zig tests, full regression,
  and `git diff --check`. The focused gates and Zig tests pass; the full
  regression passes with `NODE_BIN=$(command -v bun)` as `pass=1109 fail=0
  skip=3`.
- [x] Report the existing full-manifest Cargo fmt drift separately: `cargo fmt
  --all -- --check` still reports only the pre-existing formatting drift in
  `src/bin/generated_async_scalar_i64.rs`; the new runner passes its focused
  `rustfmt --edition 2024 --check`.
