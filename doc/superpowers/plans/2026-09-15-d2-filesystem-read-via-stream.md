# D2 Filesystem Read-Via-Stream Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admit the single pinned `descriptor.read-via-stream` filesystem method as a bounded private byte-stream reader with measured ABI and exactly-once lifecycle cleanup.

**Architecture:** The WIT method is a synchronous `@host_func` which returns a readable byte stream and a separate completion future through a canonical result area. A dedicated descriptor-specific emitter owns its state machine and does not reuse the record-stream layout from `read-directory`. The implementation is admitted only after a template-derived ABI gate verifies the synchronous `(i32, i64, i32) -> nil` method import and after a Wasmtime runner proves the lifetime matrix.

**Tech Stack:** Zig 0.16 compiler modules, WAT Component async lowering, pinned WIT sources, current `bin/do-toolchain` adapter, Rust Wasmtime host runner, Bash regression entrypoints.

**Spec:** `doc/superpowers/specs/2026-09-15-d2-filesystem-read-via-stream-design.md`

**Status:** complete (2026-09-15). Tasks 1-5 and the phase exit gates are
implemented and verified against the current toolchain. The capability remains
private and bounded as specified; no generic filesystem or stream lowering is
implied.

## Global Constraints

- Accept only `@host_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-via-stream", (File, u64) -> Tuple<Stream<u8>, Future<Result<nil, FileError>>>)`.
- The method is synchronous at the Component boundary. `@next` and `@await` are the only asynchronous actions in the source contract.
- Admit one, two, or three explicit byte reads, each `Future<Result<u8, nil>> = @next(reader)` followed by one `@await` and discard.
- Require exactly one completion-future await and discard after the byte reads.
- Do not add generic filesystem lowering, generic stream lowering, dynamic source loops, public ownership/borrow/reference syntax, or compatibility behavior for older tools.
- Cancellation releases live guest Component handles and never reports rollback of an issued filesystem effect.
- Maintain a zeroed-handle cleanup guard for descriptor, stream, completion future, and waitable set.
- Use the project toolchain adapter; active shell scripts must not invoke `wasm-tools` directly.

---

### Task 1: Freeze The Pinned Synchronous Method ABI

**Files:**
- Create: `examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_abi.sh`
- Modify: `examples/p3-runtime/test_wasm_tools_current_only.sh`
- Test: `examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_abi.sh`

**Interfaces:**
- Consumes: `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit` and `bin/do-toolchain embed-component-template`.
- Produces: a reproducible import snapshot for `[method]descriptor.read-via-stream` and a current-toolchain drift gate.

- [x] **Step 1: Write the failing ABI assertion.**

Create the test script using the same adapter setup as `test_do_wasi_filesystem_read_directory_abi.sh`. Generate the `wasi:filesystem/imports` template with `--features component-async`. Assert the pinned WIT declaration and these Core fragments:

```bash
require_wat '(type (;1;) (func (param i32 i64 i32)))'
require_wat '"wasi:filesystem/types@0.3.0-rc-2025-09-16" "[method]descriptor.read-via-stream" (func'
require_import_type '[method]descriptor.read-via-stream' 1
```

The script must parse and validate the generated Component, then require the re-emitted WIT signature:

```bash
grep -Fq 'read-via-stream: func(offset: filesize) -> tuple<stream<u8>, future<result<_, error-code>>>;' "$component_wit"
```

- [x] **Step 2: Run the gate to verify RED.**

Run:

```bash
bash examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_abi.sh
```

Expected: FAIL because the script does not exist.

- [x] **Step 3: Implement the adapter-based probe.**

Implement `require_wat` and `require_import_type` as fixed local shell functions. Use the toolchain adapter, a scoped `mktemp -d` directory, `parse-core`, `new-component`, `validate-component --features component-async`, and `component-wit`. Match only `[method]descriptor.read-via-stream`; the script must fail if `[async-lower][method]descriptor.read-via-stream` appears. Update the current-only scan only when its generated-reference exclusion needs this script name; do not add a legacy version exception.

- [x] **Step 4: Run the focused green gate.**

Run:

```bash
bash examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_abi.sh
bash examples/p3-runtime/test_wasm_tools_current_only.sh
```

Expected: PASS; the import is the synchronous method shape and no async-method import is accepted.

- [x] **Step 5: Commit the ABI gate.**

```bash
git add examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_abi.sh examples/p3-runtime/test_wasm_tools_current_only.sh
git commit -m 'Probe filesystem read stream ABI'
```

### Task 2: Add Fail-Closed Source And Manifest Admission

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/sema_imports.zig`
- Modify: `src/build/codegen_component_async.zig`
- Create: `src/build/test/compile_ok/451_wasi_filesystem_read_via_stream_component.do`
- Test: `src/build/p3_async_manifest.zig`, `src/build/sema_imports.zig`, `src/build/codegen_component_async.zig`

The numeric `compile_err` slots 451-454 are already occupied by G6.2
fixtures. Negative admission coverage therefore stays in the in-memory Zig
tests and route-plan analysis instead of introducing conflicting fixture names.

**Interfaces:**
- Consumes: the Task 1 Core method shape and the pinned WIT SHA-256 already recorded by `p3_filesystem_wit_manifest`.
- Produces: a new `filesystem_byte_stream_reader` lowering shape and `Target.wasi_read_via_stream` selected only for the exact source grammar.

- [x] **Step 1: Add RED semantic and target tests.**

Add in-memory tests with this accepted declaration:

```do
read_via_stream = @host_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-via-stream", (File, u64) -> Tuple<Stream<u8>, Future<Result<nil, FileError>>>)
File = @wasi_resource("filesystem/types/descriptor", { .id i64 })
FileError error = Io | NoEntry
```

The in-memory tests reject `@host_async_func`, `u32`, and `Stream<u16>` with
the established component diagnostics; manifest drift checks reject altered
Core parameters, stream element, WIT hash, and an async method import; and the
route-plan test rejects a missing completion await. Exact locator/member
matching is enforced by the route parser. No conflicting numeric negative
fixture is created (see the note above).

- [x] **Step 2: Run focused tests and verify RED.**

Run:

```bash
cd src && zig test build/p3_async_manifest.zig --test-filter 'read via stream'
cd src && zig test build/sema_imports.zig --test-filter 'read via stream'
cd src && zig test build/codegen_component_async.zig --test-filter 'read via stream'
```

The pre-implementation RED expectation was recorded before the descriptor and
target existed. The same focused filters are now the green admission gate in
Step 4.

- [x] **Step 3: Define the private descriptor exactly.**

Add one registry entry with effect `filesystem-byte-stream-reader`, pinned filesystem WIT SHA-256, params `["descriptor", "u64"]`, result `tuple<stream<u8>,future<result<_,error-code>>>`, and method Core params `["i32", "i64", "i32"]` with no Core results. Add a manifest validator which requires the exact locator/member, byte stream element, completion result, and all required readable stream/future operations. Add a distinct lowering-shape union member rather than widening `record_stream_reader` or `stream_reader_acquire`.

In `sema_imports.zig`, add a pinned-signature predicate that requires `@host_func`, the descriptor mirror, `u64`, `Stream<u8>`, and `Future<Result<nil, FileError>>`. In `codegen_component_async.zig`, add `Target.wasi_read_via_stream` and select it only after the route-specific plan accepts the complete function body.

- [x] **Step 4: Run focused green and fixture tests.**

Run:

```bash
cd src && zig test build/p3_async_manifest.zig --test-filter 'read via stream'
cd src && zig test build/sema_imports.zig --test-filter 'read via stream'
cd src && zig test build/codegen_component_async.zig --test-filter 'read via stream'
cd .. && ./bin/do build src/build/test/compile_ok/451_wasi_filesystem_read_via_stream_component.do --p3-async-component -o /tmp/read-via-stream.wat
```

Expected: PASS for the fixed fixture; the in-memory drift and route-plan tests
reject the invalid forms listed in Step 1.

- [x] **Step 5: Commit fail-closed admission.**

```bash
git add src/build/p3_async_manifest.zig src/build/p3_async_registry.json src/build/sema_imports.zig src/build/codegen_component_async.zig src/build/test
git commit -m 'Admit bounded filesystem byte stream source'
```

### Task 3: Emit The Dedicated Byte-Stream Component Route

**Files:**
- Create: `src/build/codegen_component_wasi_filesystem_read_via_stream.zig`
- Modify: `src/build/codegen_component_async.zig`
- Create: `examples/p3-runtime/wasi-filesystem-read-via-stream.do`
- Create: `examples/p3-runtime/wasi-filesystem-read-via-stream-bounded.do`
- Create: `examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_lowering.sh`
- Test: `src/build/codegen_component_wasi_filesystem_read_via_stream.zig`

**Interfaces:**
- Consumes: `Target.wasi_read_via_stream` and the Task 2 verified descriptor metadata.
- Produces: `ReadViaStreamPlan` with `read_count: usize`, `1 <= read_count <= 3`, and Core WAT that synchronously acquires handles then asynchronously consumes them.

- [x] **Step 1: Add RED route-plan and WAT tests.**

Use a one-read source and a three-read source. The route-plan unit tests
capture the descriptor variable, `u64` offset variable, tuple, reader,
completion, and `read_count`; the lowering gate covers both read counts and
asserts the synchronous method import, `i64` offset transport, reusable byte
read/completion sites, and guarded drops for stream, future, and descriptor.

- [x] **Step 2: Run focused tests and verify RED.**

Run:

```bash
cd src && zig test build/codegen_component_wasi_filesystem_read_via_stream.zig
```

The pre-implementation RED expectation was recorded before the route module
existed. The module test is now the green gate in Step 4.

- [x] **Step 3: Implement the route-specific parser and state machine.**

Implement `ReadViaStreamPlan.analyze` with token predicates for exactly the fixed source form. It accepts an initial `@host_func` call, extracts tuple elements zero and one, requires one-to-three explicit `@next`/`@await`/discard blocks, then one completion `@await`/discard and `return`.

Emit a separate frame whose acquisition phase calls `[method]descriptor.read-via-stream` with descriptor, `i64` offset, and result-area pointer. Store the returned stream and future handles in independent slots. The byte-ready path consumes the scalar item, decrements the read counter, and starts another byte read or the completion future. EOF skips byte consumption and starts completion. Pending callbacks resume their own state. `cleanup` drops nonzero completion, stream, descriptor, and waitable handles in that order and clears every slot before task return.

- [x] **Step 4: Add assembly gate and run green.**

Create the lowering script using the toolchain adapter. Build both source fixtures, embed WIT, assemble, and validate with `--features component-async`. Require the synchronous `[method]` marker, reject an `[async-lower][method]descriptor.read-via-stream` marker, and require all cleanup calls. Run:

```bash
cd src && zig test build/codegen_component_wasi_filesystem_read_via_stream.zig
cd .. && bash examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_lowering.sh
```

Expected: PASS for both fixed fixtures; the forbidden async-method marker and
missing cleanup markers fail closed.

- [x] **Step 5: Commit the dedicated emitter.**

```bash
git add src/build/codegen_component_wasi_filesystem_read_via_stream.zig src/build/codegen_component_async.zig examples/p3-runtime/wasi-filesystem-read-via-stream.do examples/p3-runtime/wasi-filesystem-read-via-stream-bounded.do examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_lowering.sh
git commit -m 'Emit bounded filesystem read stream component'
```

### Task 4: Prove Runtime Ownership And Cancellation

**Files:**
- Create: `examples/p3-runtime/wit/wasi-filesystem-read-via-stream.wit`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_read_via_stream.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_read_via_stream.sh`
- Test: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_read_via_stream.rs`

**Interfaces:**
- Consumes: the Task 3 assembled component and exported `run(file: own<descriptor>, offset: u64)` probe function.
- Produces: ready, pending, completion-error, cancel-before-EOF, cancel-after-EOF, early-store-drop, and repeat-call counter assertions.

- [x] **Step 1: Add RED host-counter assertions.**

Define `Stats` with method calls, stream reads, completion polls, external wakes, completions, stream drops, future drops, descriptor drops, and pending future drops. Add assertions that every terminal live-store path has each owned drop count exactly one and `ResourceTable::is_empty()` true.

- [x] **Step 2: Run the runtime script and verify RED.**

Run:

```bash
bash examples/p3-runtime/test_rust_wasi_filesystem_read_via_stream.sh
```

The pre-implementation RED expectation was recorded before the sidecar, runner,
and script existed. The complete lifecycle matrix is now the green gate in
Step 4.

- [x] **Step 3: Implement a controlled byte producer and lifecycle modes.**

Use a `VecDeque<u8>` producer returning one byte at a time and a distinct EOF state. Configure completion as ready, pending-once, or `error-code::io`; make cancellation stop at a recorded point before EOF and after EOF but before completion. Add a store-disposal mode that verifies no callback uses a disposed store. Register the explicit binary in `Cargo.toml`.

- [x] **Step 4: Build the Component and run the full matrix.**

The script compiles both source fixtures, embeds the matching WIT, assembles through `bin/do-toolchain`, and runs the runner with each mode. It requires:

```text
mode=ready result=Ok
mode=pending result=Ok
mode=error result=Err(io)
mode=cancel-before-eof result=cancelled
mode=cancel-after-eof result=cancelled
mode=early-drop result=store-discarded
mode=repeat results=Ok,Ok
table-empty=true
```

Run:

```bash
bash examples/p3-runtime/test_rust_wasi_filesystem_read_via_stream.sh
```

Expected: PASS; every live-store terminal mode prints exactly-once drops and
`table-empty=true`, while early-drop reports disposal without a table claim.

- [x] **Step 5: Commit runtime proof.**

```bash
git add examples/p3-runtime/wit/wasi-filesystem-read-via-stream.wit examples/p3-runtime/rust-host-runner examples/p3-runtime/test_rust_wasi_filesystem_read_via_stream.sh
git commit -m 'Probe filesystem read stream lifecycle'
```

### Task 5: Integrate Gates And Record The Bounded Capability

**Files:**
- Modify: `examples/p3-runtime/test.sh`
- Modify: `src/build/test/test_harness.zig`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/superpowers/specs/2026-09-15-d2-filesystem-read-via-stream-design.md`
- Modify: `doc/superpowers/plans/2026-09-15-d2-filesystem-read-via-stream.md`

**Interfaces:**
- Consumes: ABI, lowering, and lifecycle scripts from Tasks 1, 3, and 4.
- Produces: a documented, current-toolchain-tested capability statement that names this route and explicitly leaves every other filesystem stream route unavailable.

- [x] **Step 1: Add integration markers.**

Add a test-harness entry for the accepted fixture which requires the synchronous method marker, byte stream read marker, completion read marker, and all three cleanup calls. Add a forbidden marker for `[async-lower][method]descriptor.read-via-stream`. Add the three focused scripts to `examples/p3-runtime/test.sh` in ABI, lowering, then runtime order.

- [x] **Step 2: Run the integrated harness.**

Run:

```bash
./src/build/test/run_tests.sh
bash examples/p3-runtime/test.sh
```

Expected: PASS; the route has already been implemented by Tasks 1 through 4,
and the harness now makes the integration contract observable.

- [x] **Step 3: Document only the verified route.**

Update blocker documents to say that `descriptor.read-via-stream` is admitted only for the fixed locator, `@host_func` signature, one-to-three byte reads, and completion await. State that `write-via-stream`, `append-via-stream`, generic streams, and public ownership syntax remain unavailable. Update the design and this plan status only after Step 4 passes.

- [x] **Step 4: Run full verification.**

Run:

```bash
bash examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_abi.sh
bash examples/p3-runtime/test_do_wasi_filesystem_read_via_stream_lowering.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_via_stream.sh
bash examples/p3-runtime/test_wasm_tools_current_only.sh
bash src/build/test/check_toolchain_adapter.sh
./src/build/test/run_release_smoke.sh
./src/build/test/run_tests.sh
bash examples/p3-runtime/test.sh
git diff --check
```

Expected: PASS; no test or document claims generic stream or filesystem async support.

- [x] **Step 5: Commit integration and documentation.**

```bash
git add examples/p3-runtime/test.sh src/build/test/test_harness.zig doc/host_abi_blockers.md doc/pending_blocked.md doc/superpowers/specs/2026-09-15-d2-filesystem-read-via-stream-design.md doc/superpowers/plans/2026-09-15-d2-filesystem-read-via-stream.md
git commit -m 'Close bounded filesystem read stream gate'
```

## Phase Exit Criteria

- A current-toolchain ABI probe proves the synchronous method import and `u64` offset ABI from pinned WIT.
- Source admission is exact and rejects host-kind, type, descriptor, and body drift.
- The Component route supports only one-to-three explicit byte reads and the required completion await.
- Runtime counters prove every specified lifecycle mode without a live-store resource leak.
- Full regression, release smoke, toolchain adapter, and P3 runtime gates pass.
