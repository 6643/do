# G6.2.3 Producer Lease Foundation Closeout Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining semantic and verification work for the approved
path-sensitive `StreamWriter<T>` producer lease foundation without expanding
the public type system or claiming general producer runtime support.

**Architecture:** Keep `sema_stream_lease.zig` as the pure lease state machine
plus token-to-flow adapter, and keep `sema_async.zig` responsible for async
body discovery and the existing Future/StreamReader checks. Freeze only the
new path-sensitive diagnostics and fixtures; do not change the descriptor-
specific Component emitter or its bounded runtime ABI. Finish by re-running
the existing Component/Rust/Wasmtime gates and updating status documents from
fresh evidence.

**Tech Stack:** Zig 0.16 compiler sources, Do semantic fixtures, existing WAT /
WIT / Component regression scripts, pinned `wasm-tools 1.254.0`, Rust 2024 /
Wasmtime legacy runner, shell regression harness.

## Global Constraints

- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Do not implement general async-call lowering, arbitrary producer expressions,
  arbitrary stream element layouts, or unrestricted producer leases.
- Preserve the existing descriptor-specific Component/WAT output and all
  exactly-once writer, stream, future, resource, and cancellation cleanup.
- Keep the pinned WIT/toolchain and legacy Wasmtime runner unchanged.
- Preserve all unrelated dirty worktree changes; do not reset, clean, commit,
  or push during this closeout.
- Use `/home/_/._/do/.tmp/do-tmp` as `TMPDIR` for regression commands because
  the default `/tmp` is quota-constrained and can trigger a Zig 0.16 DWARF
  panic unrelated to this repository.
- Do not mark G6.2 or WASI complete; this plan closes only the semantic lease
  foundation slice.

### Task 1: Reconcile the path-sensitive adapter

**Files:**

- Modify: `src/build/sema_stream_lease.zig`
- Modify: `src/build/sema_async.zig`
- Test: `src/build/test/check/351_stream_writer_close_finalizes_lease.do`
- Test: `src/build/test/check/352_stream_writer_defer_close_finalizes_lease.do`
- Test: `src/build/test/check/353_stream_writer_transfer_finalizes_new_owner.do`
- Test: `src/build/test/check/393_stream_writer_typed_value.do`
- Test: `src/build/test/check/395_stream_writer_source_sequence.do`
- Test: `src/build/test/check/396_stream_writer_helper_transfer.do`
- Test: `src/build/test/check/397_stream_writer_helper_owned_writes.do`
- Test: `src/build/test/check/398_stream_writer_helper_two_hop.do`
- Test: `src/build/test/check/399_stream_writer_dynamic_producer.do`
- Test: `src/build/test/check/400_stream_writer_parameterized_helper.do`
- Test: `src/build/test/check/401_stream_writer_parameterized_forwarding_helper.do`
- Test: `src/build/test/check/402_stream_writer_parameterized_two_hop.do`
- Test: `src/build/test/check/403_stream_writer_parameterized_three_hop.do`
- Test: `src/build/test/check/404_stream_writer_parameterized_four_hop.do`
- Test: `src/build/test/check/408_stream_writer_both_branch_finalize.do`

**Interfaces:**

- `check_async_writer_body(...) !bool` remains the only public adapter entry.
- `LeaseEnv` remains the owner of state transitions; token scanning may only
  produce lease events and control-flow environments.
- A writer call must be recognized when the writer is the callee, while the
  helper-transfer path continues to recognize the writer argument.
- Loop `break` environments must be collected and checked after the loop;
  `continue` must not be mistaken for an exit path.

- [x] **Step 1: Run the focused baseline and record the failing shapes**

Run:

```bash
cd src
zig test build/sema_stream_lease.zig
zig test main.zig
cd ..
zig build -Doptimize=ReleaseSmall
for fixture in src/build/test/check/{399,400,401,402,403,404}_stream_writer*.do \
  src/build/test/check/351_stream_writer_close_finalizes_lease.do \
  src/build/test/check/352_stream_writer_defer_close_finalizes_lease.do \
  src/build/test/check/353_stream_writer_transfer_finalizes_new_owner.do \
  src/build/test/check/408_stream_writer_both_branch_finalize.do; do
  ./bin/do check "$fixture"
done
```

Expected: the pure state tests and full Zig suite pass; every listed positive
fixture passes; any remaining failure is limited to adapter control flow or
writer-call classification.

- [x] **Step 2: Correct loop exits and writer-callee detection**

Keep the existing `BreakCollector` and `WriterCall.callee_idx` boundaries.
When a `break` exits a loop, clone the post-defer environment into the loop's
collector and validate every collected environment at the loop exit. When a
call has the writer as its callee, classify it before scanning helper
arguments; ordinary calls must not consume a lease.

- [x] **Step 3: Re-run the focused matrix**

Run the commands from Step 1 plus:

```bash
./bin/do check src/build/test/err/405_stream_writer_branch_join.do
./bin/do check src/build/test/err/406_stream_writer_loop_exit.do
./bin/do check src/build/test/err/407_stream_writer_nested_defer_mismatch.do
```

Expected: all positive writer fixtures pass; each negative fixture fails with
one stable lease error and never falls back to synchronous output.

### Task 2: Freeze diagnostics and negative fixtures

**Files:**

- Modify: `src/build/diag.zig`
- Modify: `src/build/test/err/405_stream_writer_branch_join.expect`
- Modify: `src/build/test/err/406_stream_writer_loop_exit.expect`
- Modify: `src/build/test/err/407_stream_writer_nested_defer_mismatch.expect`
- Create: `src/build/test/err/409_stream_writer_deferred_transfer.do`
- Create: `src/build/test/err/409_stream_writer_deferred_transfer.expect`
- Create: `src/build/test/err/410_stream_writer_maybe_use.do`
- Create: `src/build/test/err/410_stream_writer_maybe_use.expect`

**Interfaces:**

- Add `StreamWriterLeasePathConflict` to both diagnostic rendering tables for
  branch/loop joins that produce `maybe`.
- Add `StreamWriterDeferredTransfer` to both tables for moving a writer that
  carries a lexical defer cleanup.
- Reuse `StreamWriterAlreadyFinalized` for moved/finalized use and
  `StreamWriterLeaseDropped` for an owned or unresolved `maybe` lease at exit.
- Existing diagnostic substrings for fixtures 351-404 must remain unchanged.

- [x] **Step 1: Add the two diagnostic mappings**

Update the summary and hint switches in `src/build/diag.zig`. Use the existing
Chinese diagnostic style and make the hints actionable: every path must agree
on one finalization state, and a deferred writer must be finalized in its
current cleanup scope.

- [x] **Step 2: Add the deferred-transfer and maybe-use fixtures**

Use these exact source shapes:

```do
async produce(writer StreamWriter<i32>) -> nil {
    defer close(writer)
    next StreamWriter<i32> = writer
}
```

The `410` fixture must create a branch whose two paths leave unequal lease
states and then use the writer; the expected error must point at the writer
operand and be `StreamWriterLeasePathConflict`, not an unrelated return error.

- [x] **Step 3: Freeze the expected substrings**

Run:

```bash
./bin/do check src/build/test/err/405_stream_writer_branch_join.do
./bin/do check src/build/test/err/406_stream_writer_loop_exit.do
./bin/do check src/build/test/err/407_stream_writer_nested_defer_mismatch.do
./bin/do check src/build/test/err/409_stream_writer_deferred_transfer.do
./bin/do check src/build/test/err/410_stream_writer_maybe_use.do
```

Copy only the stable diagnostic substrings into the matching `.expect` files;
do not snapshot line/column noise.

### Task 3: Run the semantic regression under the safe temporary directory

**Files:**

- Verify: `src/build/test/run_tests.sh`
- Modify: `src/build/test/run_tests.sh` (respect explicit Zig cache overrides)
- Verify: all `src/build/test/ok`, `err`, `check`, `compile_ok`, and
  `compile_err` fixtures

- [x] **Step 1: Run focused Zig and build gates**

```bash
cd src
zig test build/sema_stream_lease.zig
zig test main.zig
zig build -Doptimize=ReleaseSmall
cd ..
```

Expected: the lease unit suite and full Zig suite pass, and the release build
installs a compiler in `bin/do`.

- [x] **Step 2: Run the default regression with explicit cache directories**

```bash
TMPDIR=/home/_/._/do/.tmp/do-tmp \
ZIG_LOCAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-cache \
ZIG_GLOBAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-gcache \
  ./src/build/test/run_tests.sh
```

Expected: `fail=0`; the existing skip set is unchanged. `run_tests.sh` keeps
`/tmp/zig-cache` as its default but honors these explicit directories, so the
Debug build and regression pass as `pass=1065 fail=0 skip=3`.

- [x] **Step 3: Run the WASM regression**

```bash
TMPDIR=/home/_/._/do/.tmp/do-tmp \
ZIG_LOCAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-cache \
ZIG_GLOBAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-gcache \
RUN_WASM=1 ./src/build/test/run_tests.sh
```

Expected: `pass=1070 fail=0 skip=3`, `wasm run summary: pass=6 fail=0`, and no
new lease fixture skipped silently.

### Task 4: Re-prove bounded runtime compatibility

**Files:**

- Verify: `examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_five_hop.sh`
- Verify: `examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_five_hop.sh`
- Verify: `examples/p3-runtime/test_do_record_resource_stream_nested_six_level_probe_lowering.sh`
- Verify: `examples/p3-runtime/test_rust_record_resource_stream_nested_six_level_probe.sh`
- Verify: `src/build/codegen_component_stream_writer.zig`

- [x] **Step 1: Run the existing Do and Rust/Wasmtime gates**

```bash
for script in \
  examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_five_hop.sh \
  examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_five_hop.sh \
  examples/p3-runtime/test_do_record_resource_stream_nested_six_level_probe_lowering.sh \
  examples/p3-runtime/test_rust_record_resource_stream_nested_six_level_probe.sh; do
  TMPDIR=/home/_/._/do/.tmp/do-tmp bash "$script"
done
```

Expected: unchanged WAT/WIT export counts, frame offsets 52/60, exactly-once
callback/drop observations, and empty resource tables where the fixtures
assert them.

- [x] **Step 2: Run shell and whitespace checks**

```bash
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_five_hop.sh
bash -n examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_five_hop.sh
git diff --check
```

Expected: both scripts parse and the diff has no whitespace errors.

### Task 5: Update evidence-backed project status

**Files:**

- Modify: `doc/spec_rules.md`
- Modify: `doc/async-design.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `CHANGELOG.md`
- Modify: this plan file

- [x] **Step 1: Record the closed semantic boundary**

State that path-sensitive `StreamWriter<T>` lease checking covers branch/loop
joins, lexical defer, transfer, helper transfer, write, finalization, and exit
checks. State the stable negative diagnostics and the fixture IDs 405-410.

- [x] **Step 2: Preserve the explicit deferred boundaries**

Keep these items visibly pending: public `own<T>`/`borrow<T>`/`ref<T>`, general
async-call lowering, arbitrary producer expressions, borrowed/list/variant
resource fields, payload-bearing task-return errors, D2 real host I/O, and a
general producer runtime scheduler. Do not change the cancellation decision:
already-observed host side effects are not rolled back by compiler-generated
cleanup.

- [x] **Step 3: Check source/document consistency**

```bash
rg -n 'own<T>|borrow<T>|ref<T>|general async|producer lease|StreamWriter' \
  doc README.md CHANGELOG.md src/build/sema_async.zig \
  src/build/sema_stream_lease.zig
git diff --check
```

Expected: every new statement agrees with the route-A design and no public
ownership syntax appears in grammar or ordinary source examples.

### Task 6: Handoff and next design gate

**Files:**

- Verify: `docs/superpowers/specs/2026-08-03-g6-2-producer-lease-foundation-design.md`
- Verify: `docs/superpowers/plans/2026-08-03-g6-2-producer-lease-foundation.md`
- Modify: this plan file

- [x] **Step 1: Mark only this slice complete**

Update this plan and the status docs only after Tasks 1-5 pass. Use the phrase
“path-sensitive producer-lease semantic foundation complete”; do not use
“G6.2 complete” or “WASI async runtime complete”.

- [x] **Step 2: Open a separate design gate for general producer runtime**

The next independent phase must first specify an ownership-state IR, resumable
async-call lowering, producer backpressure, cancellation interaction, and
exactly-once terminal cleanup across Component/Rust/Wasmtime. It must compare:

1. **Recommended:** one more descriptor-bounded producer shape reusing the
   current frame and callback ABI, with no public ownership syntax.
2. **Higher-risk:** general producer expressions and arbitrary async-call
   composition, requiring a new resumable call IR and broader runtime proof.
3. **Not recommended:** public `own<T>`/`borrow<T>`/`ref<T>` syntax, which would
   expand parser, type, borrow, diagnostics, and codegen semantics before the
   runtime contract is proven.

No implementation of those alternatives belongs in this closeout plan.

## Exit Criteria

- The pure lease tests, full Zig suite, default regression, and WASM regression
  pass under the repository-local temporary directory.
- Fixtures 351-404 and 408 remain green; 405-407 and 409-410 fail with their
  intended stable diagnostics.
- Existing five-hop producer and six-level nested-resource Component/Rust/
  Wasmtime gates remain green with unchanged ABI observations.
- Status documents distinguish this semantic closeout from general producer
  runtime lowering and real P3 host runtime support.

## Residual Risk

The default `/tmp` quota can still trigger a Zig 0.16 DWARF panic. This plan
does not delete or reclaim unrelated `/tmp` data; all verification must use the
repository-local `TMPDIR`. General producer runtime lowering remains a new
design problem after this plan and is not implied by passing these gates.
