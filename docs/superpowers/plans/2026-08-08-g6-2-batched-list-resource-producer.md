# G6.2 Batched List-Resource Producer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote one new private, bounded `stream<list<resource-entry>>` producer shape that transfers exactly two ordered list batches and proves per-batch ownership, cleanup, and cancellation without widening generic lowering.

**Architecture:** Keep the existing C-min and dynamic-count descriptors unchanged. Add a separate package/hash/world, a hand-authored canonical WIT/Core-WAT probe, a separate manifest shape and Zig adapter, and an independent Rust/Wasmtime runtime gate. The admitted Do source is an exact no-body `produce(mode u32)` declaration; the adapter emits the measured two-batch template and never interprets arbitrary list or producer expressions.

**Tech Stack:** Zig 0.16.0, Do lexer/sema/codegen, WAT/WIT Component assembly, capability `wasm-tools 1.255.0`, legacy async assembler `wasm-tools 1.254.0`, Rust/Cargo 1.97.1, Wasmtime 47.0.2, and the existing Bash regression harness.

## Global Constraints

- Keep `--p3-async-component` opt-in and preserve the existing C-min and dynamic-count dispatch behavior byte-for-byte in observable behavior.
- Admit only package `do:g6-2-batched-list-producer@0.1.0`, world `batched-list-producer`, member `consume-via-stream`, and the exact `produce(mode u32) -> Result<nil, ProducerError>` source shape described below.
- Emit exactly two list values per successful invocation: batch 0 contains ticket ids `[111, 222]`; batch 1 contains ticket id `[333]`; list element stride is 4 bytes and the ticket field offset is 0.
- Use stream capacity `1`; do not introduce concurrent list writes, unbounded allocation, arbitrary list expressions, or a runtime count parameter.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, lifetime, or ownership syntax. `own<ticket>` exists only in the private WIT sidecar and manifest metadata.
- Do not admit borrowed stream/future payloads, variant/list generalization, generic producer expressions, independent guest child tasks, root hard-cancel, or general filesystem/HTTP async lowering.
- Cancellation stops guest work and releases live Component resources; it never rolls back an external host effect.
- Capability assembly must pass `wasm-tools 1.255.0`; legacy async assembly must use the pinned `wasm-tools 1.254.0`. A pinned-toolchain rejection is a recorded no-go, not a reason to add a compatibility workaround.
- Preserve the user-untracked `re.md` and all unrelated worktree changes. Do not push or create a PR in this plan.

## File Map

- Create `docs/superpowers/specs/2026-08-08-g6-2-batched-list-resource-producer-design.md` for the approved ABI, ownership state machine, and stop conditions.
- Create `examples/p3-runtime/wit/g6-2-batched-list-resource-producer.wit`, `examples/p3-runtime/g6-2-batched-list-resource-producer.do`, and `examples/p3-runtime/g6-2-batched-list-resource-producer-canonical.wat` for the pinned probe and compiler gate.
- Create `examples/p3-runtime/test_g6_2_batched_list_resource_producer_abi.sh` and `examples/p3-runtime/rust-host-runner/src/bin/g6_2_batched_list_resource_producer_abi.rs` for the hand-authored ABI/runtime probe.
- Modify `src/build/p3_async_manifest.zig`, `src/build/p3_async_registry.json`, and `src/build/sema_imports.zig` only after the probe is green, adding `BatchedListResourceProducerShape` and its fail-closed descriptor validation.
- Create `src/build/cmin_batched_list_resource_producer_template.wat` and `src/build/codegen_component_batched_list_resource_producer.zig`; modify `src/build/codegen_component_async.zig` only to add the isolated target branch and WIT emitter dispatch.
- Create `examples/p3-runtime/g6-2-batched-list-resource-producer.do`, `examples/p3-runtime/test_do_g6_2_batched_list_resource_producer.sh`, `examples/p3-runtime/rust-host-runner/src/bin/g6_2_batched_list_resource_producer.rs`, and `examples/p3-runtime/test_rust_g6_2_batched_list_resource_producer.sh` for compiler-generated gates.
- Create `src/build/test/check/454_g6_2_batched_list_resource_producer.do` and compile-error fixtures `454`-`458` with matching `.expect` files for source and descriptor rejection.
- Modify `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/start_here.md`, `README.md`, and `CHANGELOG.md` only from fresh command output after all gates are green or after a pinned no-go is recorded.

---

### Task 1: Write the design contract and freeze the baseline

**Files:**
- Create: `docs/superpowers/specs/2026-08-08-g6-2-batched-list-resource-producer-design.md`
- Create: `examples/p3-runtime/wit/g6-2-batched-list-resource-producer.wit`
- Create: `examples/p3-runtime/g6-2-batched-list-resource-producer.do`
- Create: `examples/p3-runtime/test_g6_2_batched_list_resource_producer_abi.sh`
- Verify: `examples/p3-runtime/wit/g6-2-c-min-dynamic-list-producer.wit`
- Verify: `doc/pending_blocked.md`

**Interfaces:**
- Probe WIT package: `do:g6-2-batched-list-producer@0.1.0`.
- Probe world: `batched-list-producer`.
- Source import: `make-ticket: func(seed: u32) -> own<ticket>`.
- Sink import: `consume-via-stream: async func(data: stream<list<resource-entry>>) -> result<_, error-code>`.
- Export: `produce: async func(mode: u32) -> result<_, error-code>`.

- [x] **Step 1: Record the exact ownership state machine in the design spec.**

  The spec must define these states and transitions:

  ```text
  GuestBatch0Owned -> Batch0Transferred -> HostBatch0Owned
  GuestBatch1Owned -> Batch1Transferred -> HostBatch1Owned
  GuestBatch0Owned/GuestBatch1Owned -> GuestDropOnFailure
  Batch0Transferred + cancel/error before batch 1 -> HostDropBatch0 + GuestDropBatch1
  Batch0Transferred + Batch1Transferred -> HostDropBatch0/Batch1
  ```

  Both batches are prepared before the first transfer decision, so every mode
  allocates two list areas and creates exactly three tickets. List storage is
  released exactly once for each allocated batch. A successful stream write
  transfers every resource in that list; the guest must never call the ticket
  drop import for a transferred handle.

- [x] **Step 2: Add the exact WIT source.**

  `examples/p3-runtime/wit/g6-2-batched-list-resource-producer.wit` must contain:

  ```wit
  package do:g6-2-batched-list-producer@0.1.0;

  interface types {
    enum error-code { io, pipe, invalid-mode }
    resource ticket {}
    record resource-entry { ticket: own<ticket> }
  }

  interface source {
    use types.{ticket};
    make-ticket: func(seed: u32) -> own<ticket>;
  }

  interface sink {
    use types.{error-code, resource-entry};
    consume-via-stream: async func(
      data: stream<list<resource-entry>>
    ) -> result<_, error-code>;
  }

  world batched-list-producer {
    use types.{error-code};
    import source;
    import sink;
    export produce: async func(mode: u32) -> result<_, error-code>;
  }
  ```

- [x] **Step 3: Run the pre-admission boundary check.**

  Run:

  ```bash
  DO_LIB_ROOT="$PWD/lib" ./bin/do build \
    --p3-async-component \
    "$PWD/examples/p3-runtime/g6-2-batched-list-resource-producer.do" \
    -o /tmp/g6-2-batched-before-admission.wat
  ```

  Expected: fail with `UnknownP3AsyncHostDescriptor` because the package/member
  is not registered. This is the current fail-closed pre-admission diagnostic;
  it proves the input does not reach WAT emission. Do not add a registry row to
  make this baseline pass.

- [x] **Step 4: Commit the design/probe input only after reviewing the boundary.**

  Run `git diff --check` and inspect that no compiler registry, public syntax,
  or existing C-min fixture changed. Commit locally with:

  ```bash
  git add docs/superpowers/specs/2026-08-08-g6-2-batched-list-resource-producer-design.md \
    examples/p3-runtime/wit/g6-2-batched-list-resource-producer.wit \
    examples/p3-runtime/g6-2-batched-list-resource-producer.do \
    examples/p3-runtime/test_g6_2_batched_list_resource_producer_abi.sh
  git commit -m "Define batched list resource producer probe"
  ```

---

### Task 2: Measure the canonical ABI and ownership cleanup

**Files:**
- Create: `examples/p3-runtime/g6-2-batched-list-resource-producer-canonical.wat`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_batched_list_resource_producer_abi.rs`
- Modify: `examples/p3-runtime/test_g6_2_batched_list_resource_producer_abi.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Verify: `examples/p3-runtime/g6-2-c-min-dynamic-list-producer-canonical.wat`

**Interfaces:**
- The Core module must import the source ticket constructor, ticket drop,
  async sink call, stream new/read/write/cancel/drop, and the standard root
  task/waitable callbacks under the new package namespace.
- The Rust ABI runner must expose modes `ready`, `pending`, `sink-error-first`,
  `sink-error-second`, `cancel-before-first`, and `cancel-after-first`.
- The runner must report `batches`, ordered `entries`, `resource-created`,
  `resource-drops`, `list-allocations`, `list-releases`, `stream-drops`,
  `future-drops`, and `table-empty`.

- [ ] **Step 1: Write red shell assertions for the new probe.**

  Require the script to fail when the Core/WIT/Rust files are absent, and then
  assert all of the following once they exist:

  ```text
  package/world identity matches the new WIT
  stream element is list<resource-entry>
  list element stride=4 and ticket offset=0
  stream capacity=1
  batch 0 is [111,222], batch 1 is [333]
  every accepted terminal leaves table-empty=true
  ```

- [ ] **Step 2: Implement the hand-authored Core state machine.**

  Prepare both list pointer/length pairs before the first transfer decision and
  use separate frame slots for each pair and transfer state. Emit stable
  markers `[producer-batch-0]`, `[producer-batch-1]`,
  `[producer-batch-transfer-0]`, `[producer-batch-transfer-1]`,
  `[producer-batch-child-before-parent-cleanup]`, and
  `[producer-batch-list-release]`. The template must perform no allocation or
  ticket construction after a mode has entered a terminal cancellation/error
  path; cancellation before the first transfer therefore drops all three
  guest-owned tickets and releases both already-prepared lists.

- [ ] **Step 3: Implement the Rust/Wasmtime ABI oracle.**

  The host sink reads at most two list values. It records each handle as it is
  transferred and drops transferred handles exactly once. For `cancel-before-first`
  no handle reaches the sink; for `cancel-after-first` only `[111,222]` reaches
  the sink and `[333]` remains guest-owned. A non-empty `ResourceTable`, a
  duplicate drop, a missing list release, or a third list item must fail the
  runner.

- [ ] **Step 4: Run the pinned probe and stop on a toolchain no-go.**

  Run:

  ```bash
  WASM_TOOLS_EXPECT_VERSION=1.255.0 \
    bash examples/p3-runtime/test_g6_2_batched_list_resource_producer_abi.sh
  ```

  The script must parse the Core module, embed the WIT, create and validate the
  Component with `cm-async,cm-more-async-builtins`, and run all six Rust modes.
  If `wasm-tools` rejects the repeated list transfer, record the exact stderr
  and stop this plan before registry or compiler changes.

- [ ] **Step 5: Commit only the green probe evidence.**

  Run `git diff --check`, `rustfmt --edition 2024 --check` on the new Rust bin,
  then commit the probe files:

  ```bash
  git add examples/p3-runtime/g6-2-batched-list-resource-producer-canonical.wat \
    examples/p3-runtime/test_g6_2_batched_list_resource_producer_abi.sh \
    examples/p3-runtime/rust-host-runner/src/bin/g6_2_batched_list_resource_producer_abi.rs \
    examples/p3-runtime/rust-host-runner/Cargo.toml
  git commit -m "Probe repeated list resource producer ownership"
  ```

---

### Task 3: Add fail-closed manifest and sema admission

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/sema_imports.zig`
- Modify: `src/build/diag.zig`
- Test: `src/build/p3_async_manifest.zig`
- Test: `src/build/sema_imports.zig`

**Interfaces:**
- New lowering effect: `record-resource-list-stream-batched-producer`.
- New target identity: `Target.record_resource_list_stream_batched_producer`.
- New analyzer error: `error.UnsupportedP3BatchedListResourceProducer`.
- Descriptor canonical fields: `batch_count=2`, `batch_lengths=[2,1]`,
  `element_stride=4`, `ticket_offset=0`, `stream_capacity=1`,
  `runtime_mode_param=u32`, and `terminal=task-return`.

- [ ] **Step 1: Add manifest red tests.**

  Add tests for the valid descriptor and for each drift case: wrong package
  hash, wrong world, wrong batch count, wrong batch lengths, stride/offset
  mismatch, missing ticket drop, borrowed `resource-entry`, unknown locator,
  and an unbounded or count-bearing producer field. Run:

  ```bash
  cd src && zig test build/p3_async_manifest.zig --test-filter 'batched list producer'
  ```

  Expected: the valid row is rejected before implementation; all malformed rows
  remain rejected.

- [ ] **Step 2: Add one private registry row from the probe output.**

  Add only the new package/hash/world/member and measured canonical imports.
  Keep `do:g6-2-c-min-producer@0.1.0` and
  `do:g6-2-c-min-dynamic-producer@0.1.0` unchanged. Do not add generic fields
  that could match another package.

- [ ] **Step 3: Add exact sema admission tests.**

  Admit only the following declaration topology:

  ```do
  make_ticket = @host("do:g6-2-batched-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
  consume = @host_func("do:g6-2-batched-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
  Ticket = @wasi_resource("do:g6-2-batched-list-producer/source/ticket", { .id i64 })
  ResourceEntry { .ticket Ticket }
  ProducerError error = Io | Pipe | InvalidMode
  produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
  ```

  Reject a second sink binding, a non-`u32` mode, a second producer parameter,
  a borrowed entry, a different resource field, any `@async`/`@await`/`@cancel`
  token, and any non-empty producer body. Every rejection must use
  `UnsupportedP3BatchedListResourceProducer` before WAT emission.

- [ ] **Step 4: Run the full manifest/sema suites and commit admission.**

  ```bash
  cd src && zig test build/p3_async_manifest.zig
  cd src && zig test build/sema_imports.zig
  git add src/build/p3_async_manifest.zig src/build/p3_async_registry.json \
    src/build/sema_imports.zig src/build/diag.zig
  git commit -m "Admit private batched list producer descriptor"
  ```

---

### Task 4: Implement the isolated Do compiler adapter

**Files:**
- Create: `src/build/cmin_batched_list_resource_producer_template.wat`
- Create: `src/build/codegen_component_batched_list_resource_producer.zig`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `examples/p3-runtime/g6-2-batched-list-resource-producer.do`
- Create: `examples/p3-runtime/test_do_g6_2_batched_list_resource_producer.sh`
- Test: `src/build/codegen_component_batched_list_resource_producer.zig`

**Interfaces:**
- Analyzer: `BatchedListResourceProducerPlan.analyze(tokens, registry) !BatchedListResourceProducerPlan`.
- WAT emitter: `emit_component_wat(allocator, plan) ![]u8`.
- WIT emitter: `emit_component_wit(allocator, plan) ![]u8`.
- Dispatcher branch: `Target.record_resource_list_stream_batched_producer`.

- [ ] **Step 1: Add the exact source fixture and red adapter tests.**

  `g6-2-batched-list-resource-producer.do` must contain the five declarations
  in Task 3 and no executable producer statements beyond `return Ok()`.
  Add tests that reject an unknown package version, a second sink, a borrowed
  entry, a non-`u32` mode, and an extra producer-body statement. Run:

  ```bash
  cd src && zig test build/codegen_component_batched_list_resource_producer.zig
  ```

  Expected: the exact positive plan is not emitted before the adapter exists;
  existing C-min and dynamic producer tests remain green.

- [ ] **Step 2: Implement exact plan extraction and bounded frame slots.**

  The plan must carry `root_name`, `mode_name`, source/sink descriptor identity,
  `batch_count=2`, the two batch lengths, list layout, and transfer/drop imports.
  It must reject every token outside the exact declaration topology. Do not
  parse or lower arbitrary expressions.

- [ ] **Step 3: Emit the two transfer state machine.**

  Start the stream, construct both batches, write batch 0, await the
  sink/backpressure result, write batch 1, then await the terminal sink result.
  On every edge use the state machine from Task 1: guest-drop untransferred
  handles, host-drop transferred handles, and release each list allocation
  once. Emit the six batch markers from Task 2 and never export a helper.

- [ ] **Step 4: Wire one dispatcher branch and verify target isolation.**

  Run:

  ```bash
  bash examples/p3-runtime/test_do_g6_2_batched_list_resource_producer.sh
  bash examples/p3-runtime/test_do_g6_2_c_min_dynamic_list_resource_producer.sh
  bash examples/p3-runtime/test_do_g6_2_c_min_list_resource_producer.sh
  ```

  The new fixture must emit only the new package/world markers. Existing C-min
  fixtures must produce the same WAT/WIT and the normal unsupported boundary
  must remain fail-closed for unregistered shapes.

- [ ] **Step 5: Commit the adapter after focused green tests.**

  ```bash
  git add src/build/cmin_batched_list_resource_producer_template.wat \
    src/build/codegen_component_batched_list_resource_producer.zig \
    src/build/codegen_component_async.zig \
    examples/p3-runtime/g6-2-batched-list-resource-producer.do \
    examples/p3-runtime/test_do_g6_2_batched_list_resource_producer.sh
  git commit -m "Lower bounded batched list resource producer"
  ```

---

### Task 5: Add compiler-generated Component/Rust/Wasmtime cleanup gates

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_batched_list_resource_producer.rs`
- Create: `examples/p3-runtime/test_rust_g6_2_batched_list_resource_producer.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`

**Interfaces:**
- Runner input: `<component.wasm> <mode>` with modes `ready`, `pending`,
  `sink-error-first`, `sink-error-second`, `cancel-before-first`, and
  `cancel-after-first`.
- Required output fields: `batches`, ordered `entries`,
  `resource-created`, `resource-drops`, `list-allocations`, `list-releases`,
  `stream-drops`, `future-drops`, `cancel-calls`, and `table-empty`.

- [ ] **Step 1: Write shell assertions before the runner exists.**

  Assert this matrix:

  | Mode | Sink entries | Ownership assertion |
  | --- | --- | --- |
  | `ready` | `[111,222]`, `[333]` | both batches transferred; all three handles dropped by host exactly once |
  | `pending` | `[111,222]`, `[333]` | one pending poll/wake; same cleanup as ready |
  | `sink-error-first` | `[111,222]` | batch 0 host-owned; batch 1 guest-owned and dropped once |
  | `sink-error-second` | `[111,222]`, `[333]` | both batches host-owned and dropped once |
  | `cancel-before-first` | `[]` | no transfer; all guest handles dropped once |
  | `cancel-after-first` | `[111,222]` | batch 0 host-owned; batch 1 guest-owned and dropped once |

  Every row must end with `resource-created=3`, `list-releases=2`,
  `stream-drops=1`, `future-drops=1`, and `table-empty=true`.

- [ ] **Step 2: Implement the host with strict ResourceTable accounting.**

  Register `ticket`, `make-ticket`, the async sink, and the ticket drop
  callback. The sink must reject a third list item, a malformed list length,
  or a duplicate handle. It must not drop a handle before the Component
  transfer contract says the sink owns it.

- [ ] **Step 3: Run the generated Component matrix.**

  ```bash
  bash examples/p3-runtime/test_do_g6_2_batched_list_resource_producer.sh
  bash examples/p3-runtime/test_rust_g6_2_batched_list_resource_producer.sh
  rustfmt --edition 2024 --check \
    examples/p3-runtime/rust-host-runner/src/bin/g6_2_batched_list_resource_producer.rs
  ```

  Expected: all six modes pass with exactly two list releases and an empty
  `ResourceTable`; no assertion may depend on rollback of an already delivered
  host-side effect.

- [ ] **Step 4: Commit the runtime gate.**

  ```bash
  git add examples/p3-runtime/rust-host-runner/src/bin/g6_2_batched_list_resource_producer.rs \
    examples/p3-runtime/test_rust_g6_2_batched_list_resource_producer.sh \
    examples/p3-runtime/rust-host-runner/Cargo.toml
  git commit -m "Gate batched list producer cleanup"
  ```

---

### Task 6: Lock negative fixtures and synchronize status

**Files:**
- Create: `src/build/test/check/454_g6_2_batched_list_resource_producer.do`
- Create: `src/build/test/compile_err/454_g6_2_batched_list_producer_unregistered.do`
- Create: `src/build/test/compile_err/454_g6_2_batched_list_producer_unregistered.expect`
- Create: `src/build/test/compile_err/455_g6_2_batched_list_producer_mode_type.do`
- Create: `src/build/test/compile_err/455_g6_2_batched_list_producer_mode_type.expect`
- Create: `src/build/test/compile_err/456_g6_2_batched_list_producer_second_sink.do`
- Create: `src/build/test/compile_err/456_g6_2_batched_list_producer_second_sink.expect`
- Create: `src/build/test/compile_err/457_g6_2_batched_list_producer_borrowed.do`
- Create: `src/build/test/compile_err/457_g6_2_batched_list_producer_borrowed.expect`
- Create: `src/build/test/compile_err/458_g6_2_batched_list_producer_body.do`
- Create: `src/build/test/compile_err/458_g6_2_batched_list_producer_body.expect`
- Modify after the green gates: `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/start_here.md`, `README.md`, `CHANGELOG.md`

**Interfaces:**
- Positive checker fixture uses only the exact new locator and declaration
  shape; all compile-error fixtures fail before WAT with
  `UnsupportedP3BatchedListResourceProducer` or the stable wrapper
  `UnsupportedP3AsyncComponent`.

- [ ] **Step 1: Add the positive checker fixture.**

  Run:

  ```bash
  ./bin/do test src/build/test/check/454_g6_2_batched_list_resource_producer.do
  ```

  Expected: the exact private source shape is accepted by the front end while
  ordinary source code still cannot name `own`, `borrow`, or `ref` types.

- [ ] **Step 2: Add and run each negative fixture.**

  Run the five compile-error fixtures directly with
  `--p3-async-component`; each must produce no WAT and match its `.expect`
  substring. The cases are an unregistered version, `mode i64`, a second sink,
  a borrowed resource-entry, and a non-empty producer body.

- [ ] **Step 3: Record fresh evidence in status documents.**

  Record the new WIT hash, world, measured batch layout, six runtime modes,
  exact cleanup counters, and the rejection diagnostics. Keep these items in
  the pending table: arbitrary producer expressions, generic/unbounded lists,
  borrowed async payloads, public ownership syntax, root hard-cancel, and D2
  general filesystem/external HTTP async.

- [ ] **Step 4: Commit fixtures and documentation.**

  ```bash
  git add src/build/test/check/454_g6_2_batched_list_resource_producer.do \
    src/build/test/compile_err/45{4,5,6,7,8}_g6_2_batched_list_producer* \
    doc/roadmap_status.md doc/pending_blocked.md doc/start_here.md \
    README.md CHANGELOG.md
  git commit -m "Document batched list producer boundary"
  ```

---

### Task 7: Run the full verification and close the phase

**Files:**
- Verify all files from Tasks 1-6.
- Modify no source files during verification.

**Interfaces:**
- Consumes the probe, registry, adapter, negative fixtures, and runtime matrix.
- Produces a status report separating verified, pending, blocked, deferred, and
  unexecuted external-write items.

- [ ] **Step 1: Run focused Zig and artifact tests.**

  ```bash
  cd src && zig test build/p3_async_manifest.zig
  cd src && zig test build/sema_imports.zig
  cd src && zig test build/codegen_component_batched_list_resource_producer.zig
  cd src && zig test build/codegen_component_async.zig
  bash examples/p3-runtime/test_g6_2_batched_list_resource_producer_abi.sh
  bash examples/p3-runtime/test_do_g6_2_batched_list_resource_producer.sh
  bash examples/p3-runtime/test_rust_g6_2_batched_list_resource_producer.sh
  ```

- [ ] **Step 2: Re-run the neighboring boundaries.**

  ```bash
  bash examples/p3-runtime/test_rust_g6_2_c_min_dynamic_list_producer.sh
  bash examples/p3-runtime/test_rust_g6_2_c_min_list_resource_producer.sh
  bash examples/p3-runtime/test_do_g6_general_boundary_rejection.sh
  bash examples/p3-runtime/test_borrow_capability_matrix.sh
  ```

  Expected: old C-min behavior is unchanged, sixth-hop/arbitrary-producer
  rejection remains green, and borrowed stream/future rows remain rejected.

- [ ] **Step 3: Run repository and release checks.**

  ```bash
  ./src/build/test/run_tests.sh
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  cd src && zig test main.zig
  cd src && zig build -Doptimize=ReleaseSmall
  cd src && zig build -Doptimize=Debug
  ./src/build/test/run_release_smoke.sh
  git diff --check
  ```

  The existing intentional skip set must remain `3`; do not convert a skip or a
  pending generic shape into a pass merely to close this plan.

- [ ] **Step 4: Apply the scope checklist.**

  The phase is complete only if the two ordered batches are observed in ready
  and pending modes, every error/drop/cancel boundary releases exactly once,
  two list allocations are released exactly twice, the old producer gates are
  unchanged, and no public ownership or generic expression lowering appears in
  the diff. A pinned ABI failure closes the phase as a documented no-go instead
  of authorizing a compiler workaround.

## Explicitly Deferred Follow-up

1. Generic producer expressions and arbitrary list construction require a new
   expression ownership IR and a scheduler/frame design; this plan does not
   infer them from two fixed list batches.
2. `list<borrow<T>>`, borrowed stream/future payloads, and public
   `own<T>`/`borrow<T>`/`ref<T>` remain blocked by the pinned Component
   capability matrix and language policy.
3. Root hard-cancel requires an independent pinned Component ABI proof of guest
   task cancellation and child-before-parent cleanup.
4. General filesystem async and external HTTP remain a separate D2 target and
   design; they are not unlocked by this producer gate.
