# WASI Read-Directory Bounded Multi-Read Implementation Plan

**Status:** completed and verified on 2026-08-02.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Extend the pinned `descriptor.read-directory` Component slice to a statically visible sequence of one to three record-stream reads with an explicit EOF probe and exactly-once cleanup.

**Architecture:** Keep the existing descriptor-specific manifest admission and WIT record layout. Extend `ReadDirectoryPlan` with a bounded `read_count`; parse repeated `@next(reader)` blocks without admitting source loops. Generate one counter-driven Core state machine that reuses the directory-entry result area, advances after an item, routes EOF to the independent completion future, and retains all cleanup guards.

**Tech Stack:** Zig lexer/parser helpers and WAT emitter, pinned `wasm-tools 1.254.0`, Rust Wasmtime host runner, shell regression fixtures.

## Global Constraints

- Keep the pinned locator/member and exact `Dir -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>` signature.
- Admit one to three statically visible `@next(reader)` blocks; reject source loops, branches, a fourth read, arbitrary descriptors, and payload-bearing completion errors.
- Keep public `own<T>`, `borrow<T>`, `ref<T>`, pointers, and references unsupported.
- Preserve one completion future, one descriptor, one stream reader, and exactly-once drop guards on success, EOF, pending, and cancellation paths.
- Do not claim dynamic record-stream or rollback semantics.
- Work in the existing dirty checkout; do not reset, clean, commit, or push.

---

### Task 1: Extend The Source Plan To Bounded Reads

**Files:**
- Modify: `src/build/codegen_component_wasi_filesystem_read_directory.zig`
- Test: `src/build/codegen_component_wasi_filesystem_read_directory.zig`
- Create: `examples/p3-runtime/wasi-filesystem-read-directory-bounded.do`

**Interfaces:**
- Consumes: the existing pinned host declaration and `ReadDirectoryPlan.analyze` token flow.
- Produces: `ReadDirectoryPlan.read_count: usize`, with `1 <= read_count <= 3`.

- [x] **Step 1: Add failing parser tests.**

Add a positive fixture containing two item blocks followed by completion and a
third positive fixture containing three item blocks (the EOF probe). Add
negative cases for a fourth block, a branch between blocks, and a loop. Assert
the positive plans expose `read_count == 2` and `read_count == 3`.

- [x] **Step 2: Run the focused test and verify RED.**

Run:

```bash
cd src && zig test build/codegen_component_wasi_filesystem_read_directory.zig --test-filter 'bounded read'
```

Expected: the new tests fail because the plan currently accepts only one
fixed block and has no `read_count` field.

- [x] **Step 3: Parse repeated blocks with an explicit upper bound.**

Refactor the existing item parse into a helper that returns the next token
index and loops only while the next token matches the exact
`Future<Result<DirectoryEntry,nil>> = @next(reader)` shape. Require the await
and `_ = entry` discard for every block, stop before the completion await,
reject `read_count == 0` and `read_count > 3`, and reject any other token before
completion.

- [x] **Step 4: Run the focused green parser tests.**

Run:

```bash
cd src && zig test build/codegen_component_wasi_filesystem_read_directory.zig --test-filter 'read-directory plan'
```

Expected: one-entry legacy tests, two/three-entry positives, and all
loop/fourth-read negatives pass.

---

### Task 2: Emit The Counter-Driven Stream State Machine

**Files:**
- Modify: `src/build/codegen_component_wasi_filesystem_read_directory.zig`
- Test: `src/build/codegen_component_wasi_filesystem_read_directory.zig`

**Interfaces:**
- Consumes: `ReadDirectoryPlan.read_count` and manifest-owned stream/future import names.
- Produces: WAT whose frame stores the remaining bounded reads and whose item path either starts another read or enters completion.

- [x] **Step 1: Add failing WAT assertions.**

Extend the emitter test to compile the two-read source and assert a
remaining-read frame slot, a decrement/branch marker, and one reusable
stream-read call site in the generated WAT. Assert the one-read fixture keeps
the same single call site.

- [x] **Step 2: Add an explicit frame counter and generated read budget.**

Reserve a frame slot for `remaining_reads`, initialize it from
`plan.read_count`, and add a helper that starts the next stream read only while
the counter is nonzero. Keep the result area at its existing offsets and do
not infer status values or import names from aliases.

- [x] **Step 3: Route item, EOF, pending, and completion paths.**

On a ready item, consume the record area, decrement the counter, and either
start the next read or start the completion future. On an EOF/dropped result,
skip record consumption and start completion immediately. Pending callbacks
must re-enter the same stream state; completion callbacks must use the existing
cleanup helper. Keep all handle slots zeroed after their corresponding drop.

- [x] **Step 4: Run focused emitter and Component assembly checks.**

Run:

```bash
cd src && zig test build/codegen_component_wasi_filesystem_read_directory.zig
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_lowering.sh
```

Expected: the legacy fixture and bounded fixture both parse, assemble, and
validate; the generated WIT remains unchanged.

---

### Task 3: Execute Two Entries And EOF In Wasmtime

**Files:**
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_read_directory.rs`
- Create: `examples/p3-runtime/test_do_wasi_filesystem_read_directory_bounded_lowering.sh`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_read_directory_bounded.sh`

**Interfaces:**
- Consumes: the bounded source fixture and the existing pinned WIT world.
- Produces: host evidence for `alpha`, `beta`, EOF, pending/ready completion,
  exact cleanup, and an empty `ResourceTable`.

- [x] **Step 1: Add host state assertions before changing the producer.**

Extend the host stats with `read_calls` and retain entry names. Add a unit-level
state assertion in the runner module that a producer yields `Completed` for
each queued entry and `Dropped` only for an empty queue, rejecting a read after
EOF.

- [x] **Step 2: Implement the two-entry producer.**

Store `alpha` and `beta` in an owned queue. Return one item with
`StreamResult::Completed` while entries remain, then an empty buffer with
`StreamResult::Dropped`. Keep descriptor/stream/future `Drop` counters and
completion pending-once behavior unchanged.

- [x] **Step 3: Add bounded lowering and runtime scripts.**

Compile `wasi-filesystem-read-directory-bounded.do`, assemble the existing WIT
sidecar, and run the host twice (pending-once and ready). Assert two entry
names, three stream reads including EOF, completion poll counts of two/one,
one drop for each owned handle, and `table-empty=true`.

- [x] **Step 4: Run both focused scripts.**

Run:

```bash
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_bounded_lowering.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory_bounded.sh
```

Expected: both modes pass and the existing one-entry runtime script remains
green.

---

### Task 4: Document The Bounded Boundary And Close Regression

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/master_plan.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-08-02-wasi-read-directory-bounded-multiread-design.md`
- Modify: this plan

**Interfaces:**
- Consumes: focused ABI/lowering/runtime evidence from Tasks 1–3.
- Produces: a status statement that bounded multi-read is verified while
  dynamic loops, generic record streams, payload errors, and arbitrary
  filesystem async methods remain unsupported.

- [x] **Step 1: Add explicit bounded evidence and rejection tests to docs.**

Record the two-entry/EOF fixture and commands in the runtime README and blocker
documents. Update the plan and design checkboxes only after the commands pass.

- [x] **Step 2: Run focused and full verification.**

Run:

```bash
cd src && zig test build/codegen_component_wasi_filesystem_read_directory.zig
cd src && zig test main.zig
cd .. && SKIP_BUILD=1 ./src/build/test/run_tests.sh
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_lowering.sh
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_bounded_lowering.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory_bounded.sh
bash src/build/test/run_release_smoke.sh
git diff --check
```

Verified: zero failures, default regression `pass=1049 fail=0 skip=3`,
`zig test main.zig` `188/188`, read-directory component tests `71/71`, async
component tests `220/220`, both old and bounded lowering/runtime gates green,
ReleaseSmall smoke green, and `git diff --check` clean.

## Phase Exit Criteria

- `ReadDirectoryPlan` accepts only one to three statically visible reads.
- Core WAT advances through item, pending, EOF, completion, and cleanup states.
- Rust/Wasmtime proves `alpha`, `beta`, EOF and exact lifecycle disposal.
- Existing one-entry, full regression, ReleaseSmall, and diff checks pass.
- Docs do not claim dynamic or generic record-stream support.
