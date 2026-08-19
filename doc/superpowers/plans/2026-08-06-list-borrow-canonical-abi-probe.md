# `list<borrow<T>>` Canonical ABI Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record independent canonical ABI evidence for a synchronous `list<borrow<ticket>>` import without admitting public `borrow<T>` syntax or widening the async nested-borrow boundary.

**Architecture:** Add a small WIT world whose exported `run` owns one ticket and passes a list of borrowed tickets to an imported `read` function. A hand-authored Core Wasm module stores a list pointer/length and borrowed handle values in linear memory; a Wasmtime 47.0.2 Rust runner validates decoded values and confirms the owner remains live until the exported call drops it. The shell gate pins `wasm-tools 1.255.0`, assembles and validates the Component, and records capability only.

**Tech Stack:** WIT, WebAssembly text, `wasm-tools`, Rust `wasmtime = 47.0.2`, Bash.

## Global Constraints

- Do source remains pointer/reference-free; no public `own<T>`, `borrow<T>`, or `ref<T>` syntax is added.
- `stream<...>` and `future<...>` nested borrow shapes remain rejected by the pinned validator.
- The probe is evidence only and must not update the compiler registry or promote G6.2.
- Existing dirty worktree changes are preserved.

### Task 1: Add the failing gate and WIT contract

**Files:**
- Create: `examples/p3-runtime/test_list_borrow_canonical_abi.sh`
- Create: `examples/p3-runtime/wit/list-borrow-canonical.wit`

- [x] **Step 1: Write the failing test**

The shell gate must require `wasm-tools 1.255.0`, assemble the WIT with a Core module path, call a not-yet-present Rust runner for `ready-empty`, `ready-one`, and `ready-three`, and assert that the output contains the expected values, `borrow-calls`, and `owner-drops=1`.

- [x] **Step 2: Run it to verify it fails**

Run `bash examples/p3-runtime/test_list_borrow_canonical_abi.sh`.
Expected: FAIL because the canonical Core WAT, Component, or Rust runner is not yet present.

### Task 2: Add the minimal Core canonical ABI fixture

**Files:**
- Create: `examples/p3-runtime/list-borrow-canonical.wat`

- [x] **Step 1: Implement the exact synchronous path**

Export `memory`, `cabi_realloc`, and `run`. `run` receives an owned ticket handle from the Component, writes three borrowed handle reps into a list allocation (or zero pointer/length for the empty case selected by a global), calls the imported canonical `read` function with `(ptr, len)`, then calls the imported `[resource-drop]ticket` for its owner. Keep the list element stride and list result offsets as explicit WAT marker comments consumed by the shell gate.

- [x] **Step 2: Run the focused gate**

Run `bash examples/p3-runtime/test_list_borrow_canonical_abi.sh`.
Expected: FAIL only on missing/incomplete Rust host bindings, not on WIT assembly or component validation.

### Task 3: Add the Rust/Wasmtime host oracle

**Files:**
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/list_borrow_canonical_abi.rs`

- [x] **Step 1: Implement the host import and owner accounting**

Register the `ticket` resource, a `read` host function accepting `Vec<Resource<Ticket>>`, and the ticket drop callback. The host must assert the borrowed list is `[111, 222, 333]` for the non-empty modes, record one borrow callback, and verify the resource table is empty only after the exported `run` returns and the owner drop callback executes.

- [x] **Step 2: Run the focused gate**

Run `bash examples/p3-runtime/test_list_borrow_canonical_abi.sh`.
Expected: PASS for empty, one, and three borrowed handles; no resource is dropped by the borrow call itself.

### Task 4: Document capability without promotion

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`

- [x] **Step 1: Record the evidence**

State that `list<borrow<ticket>>` is independently proven only for a synchronous borrowed list: canonical list lowering is `ptr/len`, each element is a 4-byte resource representation, and owner cleanup occurs after the call. Keep `stream<record{ticket: borrow<ticket>}>` and `future<borrow<ticket>>` rejected and do not add the shape to the Do compiler registry.

- [x] **Step 2: Run the regression gates**

Run `WASM_TOOLS_EXPECT_VERSION=1.255.0 bash examples/p3-runtime/test_borrow_capability_matrix.sh` and `bash examples/p3-runtime/test_list_borrow_canonical_abi.sh`.
Expected: both PASS, with the existing stream/future rejection lines unchanged.

### Task 5: Formatting and status check

- [x] **Step 1: Format/check Rust**

Run `cargo fmt --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml -- --check`.

The full manifest check currently reports pre-existing formatting drift in
`generated_async_scalar_i64.rs`; the new runner itself passes
`rustfmt --edition 2024 --check` and is not joined to that unrelated change.

- [x] **Step 2: Inspect the diff**

Run `git diff --check` and `git status --short`.
Expected: only the probe files, the Rust bin registration, the matrix default,
the plan, and the two evidence documents are changed by this closure; no
compiler registry or public syntax changes appear.
