# Async Future Stream Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the proposed public `do`/`Channel<T>` model with the approved
`async`, `await`, `Future<T>`, and `Stream<T>` language model.

**Architecture:** The compiler first represents an async declaration and await
expression explicitly, then enforces affine Future and Stream endpoint
ownership before lowering an async body into a resumable frame. Component WIT
metadata and `wasm-tools` remain the artifact path; Wasmtime is an optional
runtime compatibility target and is not a parser or semantic gate.

**Tech Stack:** Zig compiler, WAT/Core Wasm, Component WIT metadata,
`wasm-tools`, the existing shell regression suite.

## Global Constraints

- A user async declaration has exactly one form: `async name(...) -> T`.
- Calls to that declaration eagerly produce an affine `Future<T>`.
- `f() -> Future<T>` and `async f() -> Future<T>` are invalid user declarations.
- `await`, `await_all`, `await_any`, and `@cancel` consume Future ownership.
- `Stream<T>` uses opaque reader/writer endpoints with bounded backpressure;
  `Channel<T>`, `do`, `worker`, `send`, `recv`, and `yield` are not public
  concurrency syntax.
- Cancellation accepts one terminal event before it runs LIFO defers, resource
  drops, endpoint release, and frame invalidation.
- Component assembly uses WIT metadata plus `wasm-tools`; an embedder-specific
  Wasmtime C API limitation does not reject source syntax or component output.
- Every parser, semantic, or code-generation change runs
  `./src/build/test/run_tests.sh` before handoff.

---

### Task 1: Remove the Replaced Public Contract

**Files:**
- Modify: `doc/async-design.md`
- Modify: `doc/grammar.peg`
- Modify: `src/build/sema.zig`
- Modify: `src/build/sema_function_signatures.zig`
- Modify: `src/build/diag.zig`
- Delete: `src/build/test/compile_err/341_legacy_async_surface.do`
- Delete: `src/build/test/compile_err/341_legacy_async_surface.expect`
- Delete: `src/build/test/compile_err/342_legacy_await_surface.do`
- Delete: `src/build/test/compile_err/342_legacy_await_surface.expect`
- Delete: `src/build/test/compile_err/343_legacy_future_surface.do`
- Delete: `src/build/test/compile_err/343_legacy_future_surface.expect`
- Delete: `src/build/test/compile_err/344_legacy_stream_surface.do`
- Delete: `src/build/test/compile_err/344_legacy_stream_surface.expect`
- Delete: `docs/superpowers/plans/2026-07-28-wasmtime-p3-go-channel-runtime.md`

**Consumes:** The approved design at
`docs/superpowers/specs/2026-07-29-async-future-stream-design.md`.

**Produces:** No compiler diagnostic, grammar, regression fixture, or active
plan describes `async`, `await`, `Future`, or `Stream` as removed syntax or
directs users to `do`/`Channel<T>`.

- [x] Replace the public-model section of `doc/async-design.md` with the
  approved source forms and lifecycle rules.
- [x] Remove `reject_legacy_async_surface` and its call from semantic
  orchestration; remove the matching `LegacyAsyncSyntax` diagnostic text.
- [x] Delete the four negative fixtures which lock the removed diagnostic.
- [x] Delete the superseded channel runtime plan.
- [x] Run `git diff --check` and a focused scan:

```bash
rg -n '旧 async|Channel<T>|do worker|send.*recv|LegacyAsyncSyntax' \
  doc src/build docs/superpowers --glob '*.md' --glob '*.zig' --glob '*.do' --glob '*.expect'
```

Audit note (2026-07-29): the four legacy fixtures and superseded channel plan
are absent; neither `LegacyAsyncSyntax` nor `reject_legacy_async_surface`
exists in the current source. The focused scan now finds only this migration
record and unrelated synchronous `recv` documentation. `do` remains legal as
an ordinary function name, guarded by `compile_ok/341_do_is_ordinary_function_name.do`;
it is not evidence of the replaced concurrency surface.

### Task 2: Parse and Diagnose the New Surface

**Files:**
- Modify: `src/build/parser.zig`
- Modify: `src/build/sema_function_signatures.zig`
- Modify: `src/build/sema.zig`
- Modify: `src/build/diag.zig`
- Modify: `doc/grammar.peg`
- Modify: `doc/spec_rules.md`
- Create: `src/build/test/compile_ok/341_async_function_surface.do`
- Create: `src/build/test/compile_err/341_async_future_return_rejected.do`
- Create: `src/build/test/compile_err/341_async_future_return_rejected.expect`
- Create: `src/build/test/compile_err/342_future_return_rejected.do`
- Create: `src/build/test/compile_err/342_future_return_rejected.expect`

**Consumes:** `parser.FuncSig` adds `is_async: bool`; existing function
signature scans remain the sole source for declaration-name and return-shape
validation.

**Produces:** `async name(params) -> T` parses as a function declaration;
ordinary functions named `async` remain invalid; the two prohibited return
forms receive a stable, specific diagnostic.

- [ ] Add the three failing fixtures first:

```do
async ready() -> i32 { return 1 }
start() { pending Future<i32> = ready() }
```

```do
async nested() -> Future<i32> { return 1 }
```

```do
factory() -> Future<i32> { return 1 }
```

- [ ] Run the focused compile cases and confirm the valid form is rejected
  before parser work.
- [ ] Extend `FuncSig` and `parse_function_decl` to consume an optional
  leading `async` only when followed by a normal function declaration.
- [ ] Teach the type-reference checks to recognize `Future<T>`, `Stream<T>`,
  `StreamReader<T>`, and `StreamWriter<T>` as reserved builtins, while rejecting
  `nil` generic arguments.
- [ ] Add `InvalidAsyncReturn` diagnostics and enforce the two disallowed
  declaration shapes before ordinary code generation.
- [ ] Run the focused cases, then `./src/build/test/run_tests.sh`.

### Task 3: Type and Ownership Semantics

**Files:**
- Create: `src/build/sema_async.zig`
- Modify: `src/build/sema.zig`
- Modify: `src/build/sema_function_calls.zig`
- Modify: `src/build/sema_shapes.zig`
- Modify: `src/build/sema_error.zig`
- Modify: `src/build/diag.zig`
- Create: `src/build/test/err/341_future_use_after_await.do`
- Create: `src/build/test/err/341_future_use_after_await.expect`
- Create: `src/build/test/err/342_future_dropped.do`
- Create: `src/build/test/err/342_future_dropped.expect`
- Create: `src/build/test/err/343_stream_multiple_reader.do`
- Create: `src/build/test/err/343_stream_multiple_reader.expect`

**Consumes:** Task 2 declaration metadata and the current lexical-scope
binding scans.

**Produces:** An explicit async semantic pass that identifies await positions,
Future moves/consumption, StreamReader single-consumer use, StreamWriter lease
transfer, and unconsumed futures at scope exit.

- [ ] Add red fixtures for reuse after `await`, scope-exit drop, and two
  consumers of the same reader.
- [ ] Add a flat `sema_async.zig` pass with named helpers:
  `check_async_declarations`, `check_await_context`, and
  `check_async_ownership`.
- [ ] Require `await` only inside an `async` function and only on a
  `Future<T>` expression; record that the operand is consumed.
- [ ] Reject a copied, re-awaited, cancelled-after-await, or silently dropped
  Future; allow writer lease transfer but require the final owner to close,
  abort, or leave a cancellation cleanup path.
- [ ] Run focused cases and `./src/build/test/run_tests.sh`.

### Task 3a: `@cancel` Future Consumption

**Files:**
- Modify: `src/build/parser.zig`
- Modify: `src/build/sema_async.zig`
- Modify: `src/build/sema_function_calls.zig`
- Modify: `src/build/sema_tokens.zig`
- Create: `src/build/test/err/344_future_cancel_after_await.do`
- Create: `src/build/test/err/344_future_cancel_after_await.expect`

**Produces:** `@cancel(future)` is accepted as a one-argument intrinsic and
transfers the same affine Future ownership tracked by `await`.

- [x] **Step 1: Add a red regression fixture**

The fixture awaits a `Future<i32>` and then passes the same binding to
`@cancel`; it expects `FutureAlreadyConsumed`.

- [x] **Step 2: Verify the parser currently rejects the fixture**

Run: `./bin/do check src/build/test/err/344_future_cancel_after_await.do`

Expected before implementation: `InvalidExpr` at `@cancel`.

- [x] **Step 3: Parse and track cancellation consumption**

Add `cancel` to the intrinsic/reserved-name tables, require exactly one parser
argument, and make `sema_async` route both `await(binding)` and
`@cancel(binding)` through a shared Future-consumption helper. The helper
returns `FutureAlreadyConsumed` for any second consuming operation.

- [x] **Step 4: Verify focused and full regression coverage**

Run:

```bash
cd src && zig build
cd .. && ./bin/do check src/build/test/err/344_future_cancel_after_await.do
./src/build/test/run_tests.sh && git diff --check
```

Expected after implementation: focused `check` returns `FutureAlreadyConsumed`;
the suite reports `fail=0` while async build lowering remains unavailable.

### Task 3c: Aggregate Future Consumption

**Files:**
- Modify: `src/build/parser.zig`
- Modify: `src/build/sema_async.zig`
- Modify: `src/build/sema_tokens.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `doc/grammar.peg`
- Modify: `doc/spec_rules.md`
- Create: `src/build/test/check/347_await_all_consumes_futures.do`
- Create: `src/build/test/check/348_await_any_consumes_futures.do`
- Create: `src/build/test/err/345_await_all_reuses_future.do`
- Create: `src/build/test/err/345_await_all_reuses_future.expect`

**Produces:** `await_all(f1, f2, ...)` and `await_any(f1, f2, ...)` are
reserved async operations. Each requires at least two visible Future bindings
inside an async body and consumes every argument exactly once. Build-mode
lowering remains unavailable.

- [x] **Step 1: Establish the aggregate-await regression cases**

Before implementation, `await_all(left, right)` in an async body produces
`FutureDropped` because neither Future is tracked as consumed. An equivalent
`await_any` check fixture establishes the same red behavior.

- [x] **Step 2: Parse and validate aggregate operations**

Reserve both names in parser/sema token predicates. Require at least two
identifier operands separated by commas, require an async body, and route each
operand through the existing `consume_future` helper. A later `await(left)`
then returns `FutureAlreadyConsumed`.

- [x] **Step 3: Preserve the codegen boundary**

Mark either aggregate operation as requiring async lowering in the same shared
codegen predicate used by build and compiled-test entrypoints. Add a focused
unit test for that token predicate; do not emit WAT for either operation.

- [x] **Step 4: Synchronize the executable grammar and rules**

Document the one-Future and aggregate-await grammar forms and state that the
aggregate forms consume at least two Future bindings.

- [x] **Step 5: Verify focused and full regression coverage**

Run:

```bash
cd src && zig test build/codegen_pipeline.zig --test-filter 'aggregate await tokens require async lowering'
zig build
cd .. && ./bin/do check src/build/test/check/347_await_all_consumes_futures.do
./bin/do check src/build/test/check/348_await_any_consumes_futures.do
./src/build/test/run_tests.sh && git diff --check
```

Expected: both check fixtures pass, the reuse fixture reports
`FutureAlreadyConsumed`, the focused unit test passes, and the complete suite
reports `fail=0`.

### Task 3e: StreamWriter Lease Finalization

**Files:**
- Modify: `src/build/sema_async.zig`
- Modify: `src/build/diag.zig`
- Modify: `doc/spec_rules.md`
- Create: `src/build/test/err/346_stream_writer_dropped.do`
- Create: `src/build/test/err/346_stream_writer_dropped.expect`
- Create: `src/build/test/err/347_stream_writer_double_finalize.do`
- Create: `src/build/test/err/347_stream_writer_double_finalize.expect`
- Create: `src/build/test/err/348_stream_writer_abort_arity.do`
- Create: `src/build/test/err/348_stream_writer_abort_arity.expect`
- Create: `src/build/test/check/351_stream_writer_close_finalizes_lease.do`
- Create: `src/build/test/check/352_stream_writer_defer_close_finalizes_lease.do`
- Create: `src/build/test/check/353_stream_writer_transfer_finalizes_new_owner.do`

**Produces:** An async `StreamWriter<T>` parameter is an affine producer lease.
Same-type local binding transfers the lease; the current owner must finalize it
once with `close(writer)`, `abort(writer, err)`, or `defer close(writer)`. This
is static ownership validation only and does not emit stream runtime code.

- [x] **Step 1: Establish writer-leak and duplicate-finalization regressions**

Before implementation, an unclosed writer parameter, a normal close, and
close followed by abort all incorrectly pass `do check`. The error fixtures
expect `StreamWriterLeaseDropped` and `StreamWriterAlreadyFinalized`.

- [x] **Step 2: Track writer ownership and finalization**

Collect `StreamWriter<T>` parameters into a lease table. A `StreamWriter<T> =
owner` binding deactivates the source and creates the target owner. Recognize
`close(writer)`, `abort(writer, err)`, and `defer close(writer)` token shapes.
For a tracked writer, `close` requires exactly one top-level argument and
`abort` exactly two; the first finalization deactivates the owner and a second reports
`StreamWriterAlreadyFinalized`.

- [x] **Step 3: Reject unfinalized leases**

At async body exit, every active writer lease reports
`StreamWriterLeaseDropped` at its declaration. Add diagnostics and state the
source-level contract in `doc/spec_rules.md`.

- [x] **Step 4: Verify focused and full regression coverage**

Run:

```bash
cd src && zig build
cd .. && ./bin/do check src/build/test/check/351_stream_writer_close_finalizes_lease.do
./bin/do check src/build/test/check/352_stream_writer_defer_close_finalizes_lease.do
./bin/do check src/build/test/check/353_stream_writer_transfer_finalizes_new_owner.do
./bin/do check src/build/test/err/346_stream_writer_dropped.do
./bin/do check src/build/test/err/347_stream_writer_double_finalize.do
./bin/do check src/build/test/err/348_stream_writer_abort_arity.do
./src/build/test/run_tests.sh && git diff --check
```

Expected: all three check fixtures pass; the three error fixtures report their
respective stable diagnostics; the full suite reports `fail=0`.

### Task 3f: StreamWriter Lease Soundness Follow-up

**Files:**
- Modify: `src/build/sema_async.zig`
- Modify: `src/build/sema_tokens.zig`
- Modify: `src/build/sema_function_calls.zig`
- Modify: `src/build/parser.zig`
- Modify: `src/build/diag.zig`
- Modify: `doc/grammar.peg`
- Modify: `doc/spec_rules.md`
- Create: `src/build/test/err/349_stream_writer_transfer_type_mismatch.do`
- Create: `src/build/test/err/349_stream_writer_transfer_type_mismatch.expect`
- Create: `src/build/test/err/350_stream_writer_conditional_finalization.do`
- Create: `src/build/test/err/350_stream_writer_conditional_finalization.expect`
- Create: `src/build/test/err/351_stream_writer_close_reserved.do`
- Create: `src/build/test/err/351_stream_writer_close_reserved.expect`
- Create: `src/build/test/err/352_stream_writer_early_return.do`
- Create: `src/build/test/err/352_stream_writer_early_return.expect`
- Create: `src/build/test/err/353_stream_writer_abort_reserved.do`
- Create: `src/build/test/err/353_stream_writer_abort_reserved.expect`
- Create: `src/build/test/err/354_stream_writer_finalizer_outside_async.do`
- Create: `src/build/test/err/354_stream_writer_finalizer_outside_async.expect`
- Create: `src/build/test/err/355_stream_writer_finalizer_unknown.do`
- Create: `src/build/test/err/355_stream_writer_finalizer_unknown.expect`
- Create: `src/build/test/err/356_stream_writer_finalizer_arity.do`
- Create: `src/build/test/err/356_stream_writer_finalizer_arity.expect`

**Produces:** A sound, deliberately conservative static lease rule before a
CFG-backed ownership analysis exists: only equal `StreamWriter<T>` element
types transfer, only root-level operations before a possible `return` change
the ownership state, and `close`/`abort` are reserved finalizer primitives.

- [x] **Step 1: Establish transfer, path, and finalizer-name regressions**

The initial flat scan accepted mismatched `T`, accepted a branch-only close or
an early-return path, and allowed an ordinary user `close` function to satisfy
the lease check.

- [x] **Step 2: Preserve element type and reject unsafe path claims**

Store the element type token range with each writer binding and compare it on
transfer. Do not let operations in nested blocks, or operations following any
earlier return, discharge the root lease; `defer close(writer)` at root remains
the guaranteed cleanup form.

- [x] **Step 3: Reserve the finalizer spelling**

Reject user declarations of `close` and `abort`, while parsing their existing
plain-call form as static finalizer expressions. Do not introduce runtime
lowering.

- [x] **Step 3a: Reject invalid finalizer sites before lowering**

Require fixed source arity (`close(writer)` or `abort(writer, err)`), an async
body, and a tracked writer first argument. This prevents plain `close`/`abort`
calls from compiling as unknown ordinary calls in synchronous code.

- [x] **Step 4: Verify focused and full regression coverage**

Run:

```bash
cd src && zig build
cd .. && ./bin/do check src/build/test/err/349_stream_writer_transfer_type_mismatch.do
./bin/do check src/build/test/err/350_stream_writer_conditional_finalization.do
./bin/do check src/build/test/err/351_stream_writer_close_reserved.do
./bin/do check src/build/test/err/352_stream_writer_early_return.do
./bin/do check src/build/test/err/353_stream_writer_abort_reserved.do
./bin/do check src/build/test/err/354_stream_writer_finalizer_outside_async.do
./bin/do check src/build/test/err/355_stream_writer_finalizer_unknown.do
./bin/do check src/build/test/err/356_stream_writer_finalizer_arity.do
./src/build/test/run_tests.sh && git diff --check
```

Expected: every focused fixture reports its expected diagnostic, and the full
suite reports `fail=0`.

### Task 3d: Timed Await Source Shape

**Files:**
- Modify: `src/build/sema_async.zig`
- Modify: `doc/grammar.peg`
- Modify: `doc/spec_rules.md`
- Modify: `src/build/diag.zig`
- Create: `src/build/test/check/349_await_timeout_consumes_future.do`
- Create: `src/build/test/check/350_await_timeout_binding_consumes_future.do`

**Produces:** `await(future, timeout_ms)` is accepted in an async body and
consumes its first Future binding exactly as `await(future)` does. The second
argument is one parser-validated expression; its millisecond interpretation,
timer ownership, cancellation race, and result lowering remain runtime work.

- [x] **Step 1: Establish the timeout-await regression**

Before implementation, `await(pending, 10)` reports `InvalidAwaitContext`
because the static checker permits only the one-argument shape. A second
fixture uses a local `timeout` binding to prevent an accidental literal-only
contract.

- [x] **Step 2: Validate the optional timeout expression**

Keep the first argument as a visible Future binding. Permit either the closing
parenthesis immediately after it, or a comma followed by exactly one balanced
expression before that parenthesis. Route the Future argument through the
existing consumption helper in both cases.

- [x] **Step 3: Synchronize diagnostics and grammar**

Document both await forms in the executable grammar, expand the context
diagnostic with the timed spelling, and state that the runtime interprets the
timeout expression as milliseconds.

- [x] **Step 4: Verify focused and full regression coverage**

Run:

```bash
cd src && zig build
cd .. && ./bin/do check src/build/test/check/349_await_timeout_consumes_future.do
./bin/do check src/build/test/check/350_await_timeout_binding_consumes_future.do
./src/build/test/run_tests.sh && git diff --check
```

Expected: both check fixtures pass, repeated Future consumption remains
`FutureAlreadyConsumed`, and the full suite reports `fail=0`.

### Task 3b: Preserve the `@cancel` Lowering Gate

**Files:**
- Modify: `src/build/codegen_pipeline.zig`
- Create: `src/build/test/compile_err/348_cancel_lowering_unavailable.do`
- Create: `src/build/test/compile_err/348_cancel_lowering_unavailable.expect`
- Create: `src/build/test/compile_err/349_cancel_lowering_imported.do`
- Create: `src/build/test/compile_err/349_cancel_lowering_imported.expect`
- Create: `src/build/test/fixture.cancel_lowering.do`

**Produces:** Any root or imported source module containing `@cancel(...)`
fails build-mode lowering with `AsyncLoweringUnavailable` until cancellation
lowering exists, even when the entry source has no `async` declaration.

- [x] **Step 1: Add a red build fixture**

The fixture declares a synchronous `start`, binds `Future<i32>`, and calls
`@cancel(pending)`. Its expected diagnostic is `AsyncLoweringUnavailable`.

- [x] **Step 2: Reproduce the missing gate**

Run: `./bin/do build src/build/test/compile_err/348_cancel_lowering_unavailable.do -o /tmp/do-cancel-sync-review.wat`

Expected before implementation: the command incorrectly succeeds and produces
WAT because the current gate tests only `FuncSig.is_async`.

- [x] **Step 3: Gate the cancellation intrinsic**

Replace the function-only predicate in both `emit_wat_with_options` and
`emit_test_wat` with a shared predicate that returns true for an async
declaration or the token sequence `@ cancel`. Do not add cancellation emission
to the Core-Wasm emitter.

- [x] **Step 3a: Gate reachable imported modules**

Scan `ModuleGraph.modules[].tokens` with the same predicate. The imported
fixture contains the cancellation call only in `~/fixture.cancel_lowering.do`;
its root imports and calls that function without any async token.

- [x] **Step 4: Verify the gate and full regression suite**

Run:

```bash
cd src && zig build
cd .. && ./bin/do build src/build/test/compile_err/348_cancel_lowering_unavailable.do -o /tmp/do-cancel-sync-review.wat
./src/build/test/run_tests.sh && git diff --check
```

Expected after implementation: the focused build fails with
`AsyncLoweringUnavailable`; the full suite reports `fail=0`.

### Task 4: Resumable Lowering and Runtime Boundary

**Files:**
- Create: `src/build/codegen_async_model.zig`
- Create: `src/build/codegen_emit_async.zig`
- Modify: `src/build/codegen_model.zig`
- Modify: `src/build/codegen_collect_functions.zig`
- Modify: `src/build/codegen_body.zig`
- Modify: `src/build/codegen_emit_call.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Create: `src/build/test/compile_ok/342_async_await_frame.do`
- Create: `src/build/test/compile_ok/343_stream_backpressure_frame.do`

**Consumes:** The semantically validated await sites and ownership events from
Task 3.

**Produces:** Per-async-function frame metadata with resume states, captured
live locals, one terminal cleanup path, and operations that lower source
`async` calls, await, direct Component cancellation, and stream waits without
synthesizing a channel API.

- [ ] Add WAT golden fixtures that assert a distinct resume state for each
  await and a common LIFO cleanup exit block.
- [ ] Collect each async function's live locals, defers, owned futures, stream
  endpoints, and resume program counter in `codegen_async_model.zig`.
- [ ] Emit a suspend/resume dispatch and one terminal cleanup path. `@cancel`
  consumes the affine Future and lowers directly through the descriptor-pinned
  Component task/subtask ABI; it observes the ABI terminal state before LIFO
  cleanup and resource drops. Do does not emit an operation ID, broker event,
  acknowledgement protocol, custom `Cancelled` branch, rollback, or
  compensation path.
- [ ] Emit reader and writer operations with bounded-capacity state, FIFO
  waiter order after queue entry, EOF after all writer leases close, and abort
  after accepted buffered items drain.
- [ ] Preserve Component boundary metadata: `async` declarations map to WIT
  `async func`; imported `future<T>`/`stream<T>` map to opaque source values;
  assembly stays on `wasm-tools`.
- [ ] Run focused WAT checks, `examples/p3-runtime/test.sh`, and
  `./src/build/test/run_tests.sh`.

**Current runtime boundary (2026-07-31):** Frontend ownership checks, the
pinned descriptor validator, direct `@cancel` lowering for the selected P3
probe, pure frame metadata, and a descriptor-consumer
`FutureReadLifecycle` state model exist. The pinned CLI stdin `u8` Stream probe
now verifies both pending `read -> cancel-read -> drop` and ready `read -> drop`
paths through Rust/Wasmtime. The custom operation broker and host-drive
experiment were removed. Cancellation follows the pinned Component
task/subtask ABI and does not promise rollback or reconciliation of external
effects. The selected probes are not yet a general async lowering
implementation.

Before general WAT emission can begin, the remaining runtime work is to bind
frame metadata to parsed async bodies, define descriptor-driven canonical ABI
payload lift/lower, and provide a selected runtime adapter with Component
park/wake and resource cleanup. Generating WAT before those contracts exist
would create an unexecutable and misleading ABI surface. The existing
`AsyncLoweringUnavailable` gate remains required until that work is verified.

### Task 5: Documentation and Compatibility Sweep

**Files:**
- Modify: `doc/spec.md`
- Modify: `doc/spec_rules.md`
- Modify: `doc/grammar.peg`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `README.md`

**Consumes:** The implemented source and lowering semantics from Tasks 1-4.

**Produces:** Documentation which states only verified support, distinguishes
compiler artifact assembly from runtime execution, and contains no public
`do`/`Channel<T>` prescription.

- [x] Replace stale public examples and migration text with tested async,
  Future, and Stream syntax.
- [x] Keep `do` references that mean the language/tool name, but remove it
  only where it denotes the deleted task-spawn keyword.
- [x] Retain Wasmtime C API evidence as an optional embedder limitation; do
  not label it a compiler or language blocker.
- [x] Run `rg` scans, `git diff --check`, and the full regression suite.

Audit note (2026-07-29): `README.md` now states that async/Future/Stream are
frontend-only and retains the build-mode lowering gate; the default regression
baseline is `pass=991 fail=0 skip=3`. The public async and host-binding docs
distinguish the generic Wasmtime probe from P3 execution. Scans found no
active public `do`/`Channel<T>` concurrency surface. `./src/build/test/run_tests.sh`,
`examples/p3-runtime/test.sh`, `zig test build/async_operation_broker.zig`,
and `zig test build/p3_async_manifest.zig` completed successfully; the three
existing skips remain outside this work.
