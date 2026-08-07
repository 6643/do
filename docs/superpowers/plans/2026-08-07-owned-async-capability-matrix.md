# Owned Async Capability Matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record pinned Component-toolchain capability for owned resource values in asynchronous WIT shapes without promoting those shapes to the Do compiler.

**Architecture:** Extend the existing capability-only shell probe with two positive WIT rows: `future<own<ticket>>` and `stream<record { ticket: own<ticket> }>`. Keep borrowed `stream`/`future` rows as negative controls, and update the capability specification and pending boundary with the observed 1.255.0 result. No Core WAT, runtime host, compiler registry, public syntax, or lowering code changes are included.

**Tech Stack:** Bash, WIT, `wasm-tools 1.255.0`, existing Do documentation.

## Global Constraints

- Require `wasm-tools 1.255.0` by default and honor `WASM_TOOLS_EXPECT_VERSION` for reproducible overrides.
- Keep `own<T>`/`borrow<T>`/`ref<T>` out of Do source syntax.
- Do not add any shape to the Do compiler registry or generic async lowering.
- Keep the rejected `stream<borrow<T>>` and `future<borrow<T>>` rows and their exact diagnostic unchanged.
- Treat accepted rows as WIT embedding capability only; do not claim canonical layout, ownership cleanup, or Wasmtime runtime support.

---

### Task 1: Extend the capability-only probe

**Files:**
- Modify: `examples/p3-runtime/test_borrow_capability_matrix.sh`

**Interfaces:**
- Consumes: the existing `write_wit`, `check_accepted`, and `check_rejected` helpers.
- Produces: `future-owned=accepted` and `stream-owned=accepted` lines in the existing matrix output.

- [x] **Step 1: Add positive WIT cases**

Add two `write_wit` cases with worlds named `borrow-future-owned` and
`borrow-stream-owned`:

```wit
resource ticket {}
read: func() -> future<own<ticket>>;
```

and:

```wit
resource ticket {}
record entry { ticket: own<ticket> }
read: func() -> stream<entry>;
```

Use `check_accepted future-owned` and `check_accepted stream-owned` after the
existing borrowed rows. Do not change the borrowed `stream`/`future` cases.

- [x] **Step 2: Run the probe before implementation**

Run:

```bash
WASM_TOOLS_EXPECT_VERSION=1.255.0 bash examples/p3-runtime/test_borrow_capability_matrix.sh
```

Expected: the two new rows are accepted by `component embed` and `component
new`; direct, record, variant, and list remain accepted; borrowed stream and
future remain rejected with `contains a \`borrow<T>\` which is not supported`.

- [x] **Step 3: Verify the positive/negative output contract**

Assert the shell gate exits zero and prints exactly one accepted line for each
new owned shape plus the existing rejection lines. No compiler output or WAT
artifact is expected from this probe.

### Task 2: Record the capability boundary

**Files:**
- Modify: `docs/superpowers/specs/2026-08-05-generic-wit-component-abi-v2-capability-matrix.md`
- Modify: `doc/pending_blocked.md`

**Interfaces:**
- Consumes: the fresh matrix output and the existing 1.255.0 borrow refresh.
- Produces: an explicit distinction between toolchain acceptance of owned async
  values and the still-unverified Do/runtime lowering boundary.

- [x] **Step 1: Update the matrix specification**

Make 1.255.0 the current probe version, retain the 1.254.0 observation as a
historical comparison, and add rows for `future<own<ticket>>` and
`stream<record { ticket: own<ticket> }>` marked `component embed` and
`component new` accepted. State that the positive rows do not prove canonical
async frame layout, resource transfer/drop behavior, or Rust/Wasmtime
execution.

- [x] **Step 2: Update the pending boundary**

Append a dated checkpoint stating that owned async rows are toolchain-only
evidence. Keep generic producer/resource lowering, public ownership syntax, and
borrowed stream/future shapes pending. Do not remove the G6.2 blocker or add a
registry descriptor.

- [x] **Step 3: Check documentation consistency**

Run:

```bash
rg -n "future<own|stream<record.*own|borrowed stream|borrowed future" \
  docs/superpowers/specs/2026-08-05-generic-wit-component-abi-v2-capability-matrix.md \
  doc/pending_blocked.md
```

Expected: the new positive rows and all existing negative boundary language
are present, with no claim that Do lowering supports them.

### Task 3: Run focused and repository checks

- [x] **Step 1: Run focused capability gates**

```bash
WASM_TOOLS_EXPECT_VERSION=1.255.0 bash examples/p3-runtime/test_borrow_capability_matrix.sh
bash examples/p3-runtime/test_list_borrow_canonical_abi.sh
bash examples/p3-runtime/test_generic_abi_v2_promotion.sh
```

Expected: all three commands exit zero; the new owned rows do not change the
existing list-borrow runtime or v2 promotion behavior.

- [x] **Step 2: Run compiler regression checks**

```bash
zig test cli.zig
zig test codegen_pipeline.zig
zig test diag.zig
git diff --check
```

Run the Zig tests from `src/build`. Expected: 31/31, 11/11, 18/18, and no
whitespace errors.

- [x] **Step 3: Inspect scope**

Run:

```bash
git diff --stat
git status --short
```

Confirm that only the capability script, the two boundary documents, and this
plan are attributable to this task; no compiler registry, public syntax, WAT
template, or Rust runner is changed.
