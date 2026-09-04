# G6.2 Nested-Owned-Resource Record Producer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:executing-plans` (or `superpowers:subagent-driven-development`)
> to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** Admit exactly one measured fixed-shape producer whose `stream<outer>`
 element contains `inner.ticket: own<ticket>`, with recursive ownership cleanup,
 transfer, and lifecycle evidence.

**Architecture:** Add a new hash-pinned private descriptor and a dedicated
 nested producer lowering module. The compiler first matches the complete Do
 sentinel topology and descriptor, then emits a checked-in canonical WAT
 template and exact WIT surface. The route remains opt-in behind the existing
 `--p3-async-component` path and does not generalize record producers,
 ownership syntax, or async lowering.

**Tech Stack:** Zig `0.16.0`, `wasm-tools 1.255.0`, Rust/Cargo `1.97.1`,
 Wasmtime `47.0.2`, Bash gates, and the existing `do` regression harness.

**Spec:** `doc/superpowers/specs/2026-08-30-g6-2-owned-record-nested-producer-design.md`

## Global Constraints

- Add only `do:g6-2-owned-record-nested-producer@0.1.0` / member
  `consume-via-stream`; pin the exact WIT source hash measured by the probe.
- Admit only `outer { inner: inner }` and `inner { ticket: own<ticket> }` with
  one `ticket` resource, one source `make-ticket(u32) -> own<ticket>`, one
  async sink `stream<outer>`, capacity one, and one record write per call.
- Keep the measured canonical ABI fail-closed: `outer` size 4, alignment 4,
  flattened `inner.ticket` `i32` at offset 0, source `(i32) -> (i32)`, and no
  Wasm GC reference crossing the component boundary. The independent probe is
  the authority; any mismatch leaves the route pending.
- Keep ownership bits independent from handle values: bit 0 is the nested leaf
  `inner.ticket`, bit 1 is nested-record transfer. Transfer occurs only after
  a complete accepted write; pre-transfer cleanup walks the nested path exactly
  once.
- Require modes `ready=0`, `pending=1`, `sink-error-before=2`,
  `sink-error-after=3`, `cancel-before-transfer=4`,
  `cancel-after-transfer=5`, `early-drop-before-transfer=6`,
  `early-drop-after-transfer=7`, `repeat=8`, and `invalid=255`; seed is `111`.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, `Option`, or `Result`
  syntax; do not admit borrowed/list/variant/mixed/multiple-owned/deeper nested
  payloads, generic producers, arbitrary expressions, or general async.
- Existing direct, pair, parameterized-pair, triple, list, scalar, variant,
  filesystem, and generic async routes must retain their descriptors, hashes,
  output markers, and behavior.
- Do not change the default compilation route or GC migration inventory;
  preserve the deliberate `complete_rows=15 pending_rows=15` exit-1 gate.
- Use project-local temporary paths for Zig and probe artifacts:
  `TMPDIR="$PWD/.tmp/do-tmp"`, `ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache"`,
  `ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache"`.
- Stage only this route, its tests, and synchronized documentation. Do not
  push from this plan without a separate explicit delivery request.

## File Map

| Path | Responsibility |
| --- | --- |
| `examples/p3-runtime/wit/g6-2-owned-record-nested-producer.wit` | Pinned WIT source used by the canonical probe and generated parity gate. |
| `examples/p3-runtime/g6-2-owned-record-nested-producer-canonical.wat` | Hand-authored canonical core WAT with ABI and ownership markers. |
| `examples/p3-runtime/g6-2-owned-record-nested-producer.do` | Exact Do adapter sentinel accepted by the private route. |
| `src/build/p3_async_manifest.zig` | Descriptor parsing, nested shape validation, and manifest unit tests. |
| `src/build/p3_async_registry.json` | Hash-pinned descriptor and measured canonical facts. |
| `src/build/owned_record_nested_stream_producer_template.wat` | Byte-identical checked-in WAT template consumed by codegen. |
| `src/build/codegen_component_owned_record_nested_stream_producer.zig` | Exact source matcher, ABI validation, WAT/WIT emission, and unit tests. |
| `src/build/codegen_component_async.zig` | Target enum, classification, dispatch, and dispatch tests. |
| `src/build/test/compile_ok/713_g6_2_owned_record_nested_component.do` | Positive compile-mode fixture. |
| `src/build/test/compile_ok/713_g6_2_owned_record_nested_component.expect` | Positive output and route markers. |
| `src/build/test/compile_err/725_g6_2_nested_*.do` | One-contract-fact-per-file negative source mutations. |
| `src/build/test/compile_err/725_g6_2_nested_*.expect` | Stable rejection diagnostics. |
| `examples/p3-runtime/test_do_g6_2_owned_record_nested_producer.sh` | Positive Do/WIT/WAT/Component admission gate. |
| `examples/p3-runtime/test_do_g6_2_owned_record_nested_producer_negative.sh` | Fail-closed source, descriptor, and drift gate. |
| `examples/p3-runtime/test_rust_g6_2_owned_record_nested_producer.sh` | Rust/Wasmtime ten-mode lifecycle runner and cleanup assertions. |
| `examples/p3-runtime/test_g6_2_owned_record_nested_producer_equivalence.sh` | Canonical/generated WIT/WAT and lifecycle parity gate. |
| `examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_nested_producer.rs` | Rust/Wasmtime host implementation and lifecycle assertions for the nested probe. |
| `examples/p3-runtime/rust-host-runner/Cargo.toml` | Register the nested runner only if the current Cargo configuration requires an explicit `[[bin]]` entry. |
| `doc/start_here.md`, `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/master_plan.md`, `examples/p3-runtime/README.md`, `CHANGELOG.md` | Record private admission, evidence, and remaining scope. |

### Task 1: Measure and pin the independent canonical contract

**Files:**

- Create: `examples/p3-runtime/wit/g6-2-owned-record-nested-producer.wit`
- Create: `examples/p3-runtime/g6-2-owned-record-nested-producer-canonical.wat`
- Create: `examples/p3-runtime/test_g6_2_owned_record_nested_canonical.sh`
- Test: `examples/p3-runtime/test_g6_2_owned_record_nested_canonical.sh`

**Interfaces:**

- Consumes: the exact WIT surface in the approved spec and the current pinned
  `wasm-tools` toolchain.
- Produces: canonical WAT, WIT SHA-256, parsed core signatures, stream import
  names, record layout markers, and a non-GC boundary assertion consumed by all
  later tasks.

- [x] **Step 1: Write the pinned WIT source.**

  Create the exact text from the spec, including the final newline. The source
  must define `types.inner`, `types.outer`, `types.ticket`, `source`, `sink`,
  and world `owned-record-nested-producer`; the only owned leaf is
  `inner.ticket`.

- [x] **Step 2: Write the failing canonical gate.**

  The shell gate must first assert that the canonical WAT file is absent or
  incomplete, then run the current toolchain against the WIT and WAT. It must
  check `wasm-tools --version` exactly, parse the core module, embed the WIT,
  construct and validate the Component, compute `sha256sum` of the WIT, and
  assert markers for outer size `4`, alignment `4`, leaf offset `0`, source
  `(i32) -> (i32)`, capacity `1`, and absence of `__arc_`, `ref.null`,
  `struct.new`, and `array.new`.

- [x] **Step 3: Run the gate and record the expected RED result.**

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" \
  ./examples/p3-runtime/test_g6_2_owned_record_nested_canonical.sh
  ```

  Expected: fail because the canonical artifact or required markers do not yet
  exist. Preserve the failure output before adding implementation artifacts.

- [x] **Step 4: Add the minimum canonical WAT and rerun.**

  Author the core module using the measured canonical component ABI. Include
  explicit comments/markers for `inner.ticket`, the flattened slot at offset
  `0`, source `make-ticket`, stream capacity one, and the two ownership bits.
  Keep all handles as `i32` and keep resource drop, stream, task, and waitable
  operations explicit. The gate must pass before the descriptor is added.

- [x] **Step 5: Record the measured hash and ABI facts.**

  Store the command output and exact hash in the implementation notes used by
  Task 2. Do not infer the hash from another descriptor or reuse direct-triple
  evidence.

### Task 2: Add the hash-pinned nested descriptor and manifest shape

**Files:**

- Modify: `src/build/p3_async_manifest.zig` (`LoweringShape`, nested shape
  struct, `lowering_shape`, validator, and unit tests)
- Modify: `src/build/p3_async_registry.json` (one nested descriptor object)
- Test: `src/build/p3_async_manifest.zig`

**Interfaces:**

- Consumes: Task 1 WIT hash and canonical ABI facts.
- Produces: `.record_resource_nested_stream_producer` shape with exact nested
  record metadata, `RecordNestedField` ownership path, canonical producer and
  stream operation facts, and fail-closed descriptor lookup.

- [x] **Step 1: Add the failing manifest test.**

  Add a test that constructs the approved descriptor and asserts
  `lowering_shape` is `.record_resource_nested_stream_producer`; add a second
  assertion that the same descriptor with a changed hash returns `null`. Run:

  ```bash
  (cd src && zig test build/p3_async_manifest.zig)
  ```

  Expected: fail because the new shape and descriptor are not recognized.

- [x] **Step 2: Add the shape and registry row.**

  Extend the manifest union and registry parser using the existing dedicated
  producer shape conventions. Add exactly one descriptor row with effect
  `record-resource-nested-stream-producer`, measured WIT hash, source module
  `do:g6-2-owned-record-nested-producer/source@0.1.0`, source import
  `make-ticket`, resource drop import `[resource-drop]ticket`, stream element
  `outer`, capacity `1`, and canonical operation signatures. Store nested
  metadata as `outer.inner.ticket`, with `inner` and `outer` preserved as record
  containers rather than flattening the semantic path.

- [x] **Step 3: Require exact descriptor facts.**

  The validator must reject wrong locator, member, effect, parameter, result,
  package, world, interface, WIT parameter name, hash, source module, source
  arity, stream operation import, record byte size, alignment, leaf offset,
  ownership, resource name, or drop import. It must reject a list, variant,
  borrowed leaf, direct outer leaf, extra nested field, extra nesting, batch
  count, runtime mode field, result payload, or side-channel drop metadata.

- [x] **Step 4: Add mutation tests and verify green.**

  Clone the registered descriptor and mutate one fact at a time: hash,
  package/world, element, field count, field order, nested path, leaf
  ownership, leaf resource, offset, byte size, source module, source result,
  stream write import, and operation signature. Every mutation must return
  `null`; existing direct/pair/triple descriptors must retain their original
  shapes.

  Run the manifest test again and keep the output free of warnings/errors.

### Task 3: Build the closed nested producer emitter and dispatch

**Files:**

- Create: `src/build/owned_record_nested_stream_producer_template.wat`
- Create: `src/build/codegen_component_owned_record_nested_stream_producer.zig`
- Modify: `src/build/codegen_component_async.zig`
- Test: the new emitter module and async dispatch tests

**Interfaces:**

```zig
pub const ProducerError = error{UnsupportedP3OwnedRecordNestedStreamProducer};

pub const OwnedRecordNestedStreamProducerPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    source_host_name: []const u8,
    sink_host_name: []const u8,
    ticket_type_name: []const u8,
    inner_type_name: []const u8,
    record_type_name: []const u8,
    error_type_name: []const u8,
    root_name: []const u8,
    mode_name: []const u8,
    layout: p3_async_manifest.RecordLayout,
    producer: p3_async_manifest.ProducerCanonical,
};

pub fn analyze(tokens: []const lexer.Token,
    registry: p3_async_manifest.Registry) ProducerError!OwnedRecordNestedStreamProducerPlan;
pub fn emit_component_wat(allocator: std.mem.Allocator,
    plan: OwnedRecordNestedStreamProducerPlan) ![]u8;
pub fn emit_component_wat_for_tokens(allocator: std.mem.Allocator,
    tokens: []const lexer.Token) ![]u8;
pub fn emit_component_wit(allocator: std.mem.Allocator,
    plan: OwnedRecordNestedStreamProducerPlan) ![]u8;
pub fn emit_component_wit_for_tokens(allocator: std.mem.Allocator,
    tokens: []const lexer.Token) ![]u8;
```

- [x] **Step 1: Add the template parity test.**

  Copy the canonical WAT byte-for-byte to the compiler template and add a unit
  test using `@embedFile` that compares the two. The test must also reject
  `__arc_`, `ref.null`, `struct.new`, and `array.new`, and assert markers for
  `inner.ticket`, leaf offset `0`, outer size `4`, ownership mask bits `1/2`,
  and transfer order.

- [x] **Step 2: Add the failing exact-source matcher tests.**

  Add positive and negative unit fixtures for the approved Do topology. The
  matcher must require exactly two host bindings named `make_ticket` and
  `consume`, one `Ticket` resource at the exact source path, exactly `Inner`
  and `Outer` records with the ordered fields, one `ProducerError` error, one
  `produce(mode u32) -> Result<nil, ProducerError> { return Ok() }`, and one
  empty `start`. Reject every async token/intrinsic, extra declaration, wrong
  host marker, direct resource leaf, borrowed leaf, list/variant field, third
  nested record, wrong result, and changed descriptor fact.

- [x] **Step 3: Validate the nested ABI and ownership plan.**

  Build `AbiType.resource(..., .own)` under the `Inner` record and use
  `wit_abi_layout.LayoutPlan.record` for `Outer`. Assert size/alignment and
  field offsets against Task 1. Require the semantic ownership path
  `inner.ticket`, exactly one leaf bit and one transfer bit, and the measured
  stream operation signatures. Reject any plan with a flattened direct field,
  extra ownership bit, or changed drop order.

- [x] **Step 4: Emit WAT and exact WIT.**

  `emit_component_wat` must return the checked-in template only after all
  validation and must reject any output containing `__arc_`. `emit_component_wit`
  must return the exact pinned WIT from Task 1, including `inner`, `outer`,
  `make-ticket`, `consume-via-stream`, and async world `produce` declarations.
  Do not synthesize a generic WIT printer in this task.

- [x] **Step 5: Add target classification and dispatch.**

  Add `.owned_record_nested_stream_producer` to the compiler target enum and
  classify only the exact descriptor/source matcher before the existing direct
  triple route. Dispatch WAT and WIT emission through the new module, map only
  `UnsupportedP3OwnedRecordNestedStreamProducer` to the existing unsupported
  component diagnostic, and leave every other error visible.

- [x] **Step 6: Run focused compiler tests.**

  Run:

  ```bash
  (cd src && zig test build/codegen_component_owned_record_nested_stream_producer.zig)
  (cd src && zig test build/codegen_component_async.zig)
  ```

  Expected: positive matcher/emitter/dispatch tests pass; all negative source
  mutations reject before WAT emission; existing route tests remain green.

### Task 4: Add compiler fixtures and Do/Component gates

**Files:**

- Create: `src/build/test/compile_ok/713_g6_2_owned_record_nested_component.do`
- Create: `src/build/test/compile_ok/713_g6_2_owned_record_nested_component.expect`
- Create: `src/build/test/compile_err/725_g6_2_nested_*.do`
- Create: matching `src/build/test/compile_err/725_g6_2_nested_*.expect`
- Create: `examples/p3-runtime/g6-2-owned-record-nested-producer.do`
- Create: `examples/p3-runtime/test_do_g6_2_owned_record_nested_producer.sh`
- Create: `examples/p3-runtime/test_do_g6_2_owned_record_nested_producer_negative.sh`
- Test: the compiler harness and both shell gates

**Interfaces:**

- Consumes: Task 3 private target and Task 1 canonical files.
- Produces: reproducible positive compile evidence, one-fact-per-fixture
  negative evidence, valid Component bytes, and generated WIT/WAT artifacts.

- [x] **Step 1: Write the positive fixture and expected output first.**

  Copy the exact adapter shape from the approved spec. The expectation must
  require the nested target marker, package/world marker, and no ARC marker.
  Run the fixture before implementation wiring and confirm it fails for the
  missing target; then run it after Task 3 and confirm it passes.

- [x] **Step 2: Add one negative fixture per contract fact.**

  Include direct `Outer.ticket`, renamed/reordered fields, extra field,
  third nested record, `borrow<ticket>`, non-resource leaf, list, variant,
  wrong stream element, marker, descriptor, result, host marker, WIT hash,
  package/world/source module, wrong source arity/seed, and an async intrinsic
  in the sentinel body. Each `.expect` must assert the stable unsupported
  component diagnostic and each file must be rejected before WAT output.

- [x] **Step 3: Add the positive Do gate.**

  The gate must build `bin/do` with local caches, compile the `.do` fixture with
  `--p3-async-component`, compare emitted WAT/WIT to the checked-in template
  and pinned WIT, parse/embed/new/validate with `wasm-tools 1.255.0`, assert no
  ARC or GC-reference boundary, and check the nested ABI markers.

- [x] **Step 4: Add the negative gate.**

  Iterate the negative fixture list, require non-zero compiler status, require
  the expected diagnostic substring, and fail if any fixture emits WAT or is
  classified as the existing direct/pair/triple route. Also mutate a copy of
  the registry row for hash/package/world/offset/ownership/stream operation
  drift and require `lowering_shape == null` through the Zig manifest test.

- [x] **Step 5: Run the focused gates.**

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache" \
  ./examples/p3-runtime/test_do_g6_2_owned_record_nested_producer.sh
  ./examples/p3-runtime/test_do_g6_2_owned_record_nested_producer_negative.sh
  ```

### Task 5: Exercise the ten lifecycle modes in Rust/Wasmtime

**Files:**

- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_nested_producer.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` only if an explicit
  `[[bin]]` registration is required by its current configuration
- Create: `examples/p3-runtime/test_rust_g6_2_owned_record_nested_producer.sh`
- Test: Rust/Wasmtime lifecycle runner

**Interfaces:**

- Consumes: validated Component and generated WIT/WAT from Task 4.
- Produces: per-mode ticket observations, exactly-once cleanup counters,
  pending/cancel behavior, repeat-store reuse, and empty resource table.

- [x] **Step 1: Write the failing runner assertions.**

  Add one Store per mode except `repeat`, which runs two calls in one Store and
  resource table. Before the host implementation exists, assert the complete
  matrix: ready/pending/sink-error-before/sink-error-after,
  cancel-before/after-transfer, early-drop-before/after-transfer, repeat, and
  invalid. The expected observations are `[]`, `[111]`, or `[111,111]` exactly
  as listed in the spec; every valid row must have one create/drop and an empty
  table.

- [x] **Step 2: Implement the minimal host resource and stream callbacks.**

  Track ticket handles and seed values in the existing Rust host-runner table.
  Implement source creation, nested record read/lift, stream backpressure,
  sink result, cancellation, early drop, task/future cleanup, and resource
  table inspection. The host must drop a transferred ticket exactly once and
  must not drop a pre-transfer ticket twice.

- [x] **Step 3: Run the runner in RED/GREEN order.**

  Run the runner before the callbacks and preserve the expected failure. Then
  run all ten modes after implementation and require zero completion calls in
  the four cancellation/early-drop rows, one pending-future drop and one host
  cancel in each, and `table-empty=true` everywhere.

- [x] **Step 4: Add repeat and invalid regression assertions.**

  Confirm `repeat` produces `[111,111]` with two creates and two drops in one
  Store and no stale nested handle. Confirm `invalid` rejects before stream,
  task, future, waitable, frame, or ticket allocation.

### Task 6: Prove canonical/generated parity and preserve existing routes

**Files:**

- Create: `examples/p3-runtime/test_g6_2_owned_record_nested_producer_equivalence.sh`
- Modify: `examples/p3-runtime/README.md` and the route evidence entries in
  the status documents listed in Task 7
- Test: parity and regression gates

- [x] **Step 1: Compare generated artifacts byte-for-byte.**

  Compile the positive Do adapter, extract generated WAT/WIT, normalize only
  the explicitly documented tool metadata, and compare all semantic sections
  byte-for-byte with the canonical files. Fail on changed imports, offsets,
  markers, ownership bits, or field path.

- [x] **Step 2: Compare lifecycle observations.**

  Run canonical WAT and generated Component through the same Rust/Wasmtime host
  runner for all ten modes and compare ticket observations, cleanup counts,
  cancellation calls, completion calls, and resource-table emptiness.

- [x] **Step 3: Re-run existing route evidence.**

  Run the existing direct/pair/parameterized-pair/triple/list/scalar/variant
  component gates and assert their descriptor hashes and target markers are
  unchanged. Run the migration inventory and require
  `complete_rows=15 pending_rows=15` with exit status `1`.

### Task 7: Synchronize status documents and complete the verification gate

**Files:**

- Modify: `doc/start_here.md`, `doc/roadmap_status.md`,
  `doc/pending_blocked.md`, `doc/master_plan.md`,
  `examples/p3-runtime/README.md`, `CHANGELOG.md`
- Test: full repository regression and release smoke

- [x] **Step 1: Document the bounded admission.**

  Record the exact descriptor, WIT hash, measured nested path/layout, ten-mode
  evidence, and the fact that this is a private fixed probe. State explicitly
  that public ownership syntax, generic nested producers, arbitrary expressions,
  and full GC cutover remain out of scope.

- [x] **Step 2: Keep blocker state honest.**

  If any canonical, lifecycle, or parity gate is red, record the concrete
  evidence under `doc/pending_blocked.md` and leave the route pending; do not
  call a partial probe complete or alter the migration inventory.

- [x] **Step 3: Run the complete verification set.**

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache" \
  ./src/build/test/run_tests.sh
  (cd src && zig build -Doptimize=ReleaseSmall)
  ./examples/p3-runtime/test_do_g6_2_owned_record_nested_producer.sh
  ./examples/p3-runtime/test_do_g6_2_owned_record_nested_producer_negative.sh
  ./examples/p3-runtime/test_rust_g6_2_owned_record_nested_producer.sh
  ./examples/p3-runtime/test_g6_2_owned_record_nested_producer_equivalence.sh
  ./examples/p3-runtime/test_wasm_tools_current_only.sh
  ```

  Record each command's status and retain failures. A successful build or
  focused probe does not waive any failed full-harness or migration gate.

- [x] **Step 4: Review the final diff and preserve the existing worktree; do not commit or push without an explicit delivery request.**

  Verify that the two pre-existing uncommitted plan files remain untouched,
  no generated cache or large Rust target artifact is staged, and no unrelated
  ARC/GC or public type changes are present. Commit locally only after every
  applicable gate is green; do not push without a separate explicit request.

## Self-review checklist

- [x] Every approved spec section has a corresponding task and executable
  verification.
- [x] No step depends on an unspecified type, function, marker, or path.
- [x] All nested names and ownership paths remain distinct from flattened ABI
  offsets.
- [x] Every negative boundary mutation is rejected before emission.
- [x] Canonical and generated artifacts plus lifecycle observations are both
  compared.
- [x] Existing routes and the GC migration inventory are explicitly guarded.
