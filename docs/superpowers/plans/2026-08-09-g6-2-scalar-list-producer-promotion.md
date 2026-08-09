# G6.2 Scalar List Producer Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the already-green, bounded `stream<list<u32>>` Component probe into one private, fail-closed Do compiler capability without generalizing list lowering or adding ownership/reference syntax.

**Architecture:** Keep the scalar-list capability in its own manifest shape, semantic admission predicate, WAT template, and emitter. The adapter recognizes exactly one pinned sink descriptor and one fixed Do declaration topology, then lowers a bounded `count: u32` producer with values `10..30`; every other shape is rejected before WAT emission. The existing record/resource list producer emitters remain unchanged and are not made generic.

**Tech Stack:** Zig 0.16.0, the Do compiler, WIT/Core WAT canonical ABI, `wasm-tools` 1.255.0, Rust 1.97.1, Wasmtime 47.0.2, Bash gates, and `src/build/test/run_tests.sh`.

## Global Constraints

- Begin from a clean `main`/`origin/main` at `a98b4be`; preserve unrelated worktree changes if another actor creates them.
- The admitted descriptor is exactly `do:g6-2-scalar-list-producer@0.1.0`, member `consume-via-stream`, WIT hash `a24e467b1746f94432bb495c13fc0ce718a3833dc0ce7659228cfb6eaf69ff9f`.
- Admit only `stream<list<u32>>`, one `count: u32` parameter, maximum list length `3`, list pointer offset `64`, length offset `68`, element stride `4`, and stream capacity `1`.
- The Do surface is `(StreamWriter<[u32]>) -> Result<nil, ProducerError>` for the single `@host_async_func` sink and `produce(count u32) -> Result<nil, ProducerError>` for the exported producer.
- Keep `@host_func`, `@host_async_func`, `@async`, `@await`, and `@cancel` semantics unchanged. The producer fixture contains no async declaration or async intrinsic.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, lifetime, `externref`, `anyref`, or `funcref` syntax.
- Do not reuse `record_layout`, `list_resource_layout`, resource drops, or resource producer descriptors for this scalar-only shape. The promoted path must have no resource import and must leave `ResourceTable` empty.
- The capability remains opt-in under `--p3-async-component`; default/v1/v2 dispatch is unchanged. Unsupported or malformed shapes fail before WAT emission.
- Cancellation follows the already-decided Component/WASI semantics: drop live async state exactly once and never compensate an external effect issued before cancellation.
- A failed pinned Component/Rust/Wasmtime gate is a no-go. Record the exact command and stderr in `doc/pending_blocked.md`, do not claim promotion complete, and do not weaken the registry predicate or add a compatibility fallback.

## Promotion Contract

The checked-in evidence in `docs/superpowers/specs/2026-08-09-g6-2-scalar-list-producer-design.md` is the ABI source of truth. The compiler promotion is complete only when all of these are true:

```text
count=0 -> one sink call with []
count=1 -> one sink call with [10]
count=2 -> one sink call with [10, 20]
count=3 -> one sink call with [10, 20, 30]
count=4 -> Result::Err(invalid-mode), zero sink calls, zero list allocation
```

For ready, pending, sink-error, early-drop, cancel-before-transfer, and cancel-after-transfer, list storage is released exactly once. A transfer clears guest ownership before list release; cancellation before transfer retains guest ownership until guest cleanup. No resource handle is created, dropped, or inserted into a `ResourceTable`.

## Files And Boundaries

- `src/build/p3_async_manifest.zig`: parse and validate a new scalar-list canonical descriptor and expose `ScalarListStreamProducerShape`.
- `src/build/p3_async_registry.json`: add one exact private descriptor row; existing resource-list rows stay byte-for-byte unchanged.
- `src/build/sema_imports.zig`: admit only the fixed host binding and producer signature.
- `src/build/codegen_component_scalar_list_stream_producer.zig`: analyze the fixed Do topology and splice the independent scalar WAT/WIT templates.
- `src/build/cmin_scalar_list_stream_producer_template.wat`: implement bounded list allocation, transfer, completion, and cleanup without resource operations.
- `src/build/codegen_component_async.zig`: add an opt-in target and dispatcher branch for the new adapter.
- `src/build/test/check/482_g6_2_scalar_list_producer.do`: positive semantic topology fixture.
- `src/build/test/compile_ok/482_g6_2_scalar_list_producer_component.do` and `.expect`: positive compiler/diagnostic fixture.
- `src/build/test/compile_err/483` through `489` scalar-list fixtures and matching `.expect`: fail-closed signature/topology cases.
- `examples/p3-runtime/g6-2-scalar-list-producer.do`: compiler-generated runtime input.
- `examples/p3-runtime/test_do_g6_2_scalar_list_producer.sh`: Core/WIT/Component lowering gate.
- `examples/p3-runtime/rust-host-runner/src/bin/g6_2_scalar_list_producer.rs`: generated-Component Wasmtime host oracle.
- `examples/p3-runtime/test_rust_g6_2_scalar_list_producer.sh`: ready/pending/error/drop/cancel runtime gate.
- `src/build/p3_async_manifest.zig`, `src/build/sema_imports.zig`, and the new emitter: focused unit tests remain adjacent to their implementation.
- `doc/start_here.md`, `doc/roadmap_status.md`, `doc/master_plan.md`, `doc/pending_blocked.md`, and `CHANGELOG.md`: update only from fresh gate output during closeout.

## Order And Gates

| Order | Task | Deliverable | Stop condition |
| --- | --- | --- | --- |
| 1 | Baseline | Reproducible probe, hashes, and tool versions | Any existing regression blocks promotion |
| 2 | Manifest | Isolated shape and one pinned registry row | Any malformed descriptor is admitted |
| 3 | Sema | Exact source-signature admission | A neighboring shape reaches codegen |
| 4 | Codegen | Independent scalar template and adapter | Cleanup or unsupported-shape guard is missing |
| 5 | Do fixtures | Positive and negative compiler coverage | Failure occurs after WAT emission or diagnostics drift |
| 6 | Component/runtime | Generated Component and Rust/Wasmtime matrix | Validation, cancellation, or release invariant fails |
| 7 | Closeout | Full regressions and truthful roadmap | Any unverified claim remains |

### Task 1: Re-run the scalar probe and freeze the promotion baseline

**Files:**
- Verify: `docs/superpowers/specs/2026-08-09-g6-2-scalar-list-producer-design.md`
- Verify: `examples/p3-runtime/wit/g6-2-scalar-list-producer.wit`
- Verify: `examples/p3-runtime/g6-2-scalar-list-producer-canonical.wat`
- Verify: `examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh`
- Verify: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_scalar_list_producer_abi.rs`

**Interfaces:** Consumes the existing evidence-only probe. Produces a clean, reproducible starting point for compiler changes; no `src/build` file changes are allowed in this task.

- [ ] **Step 1: Check the checkout and pinned tools.**

Run:

```bash
git status --short --branch
git rev-parse main origin/main
zig version
wasm-tools --version
rustc --version
wasmtime --version
```

Expected: clean `main` equal to `origin/main`, Zig `0.16.0`, wasm-tools `1.255.0`, Rust `1.97.1`, and Wasmtime `47.0.2`.

- [ ] **Step 2: Re-run the evidence-only gate.**

Run:

```bash
wasm-tools component wit examples/p3-runtime/wit/g6-2-scalar-list-producer.wit
sha256sum examples/p3-runtime/wit/g6-2-scalar-list-producer.wit
WASM_TOOLS_EXPECT_VERSION=1.255.0 bash examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh
```

Expected: the nine rows in the design spec pass; the WIT hash is `a24e467b1746f94432bb495c13fc0ce718a3833dc0ce7659228cfb6eaf69ff9f`; `count=4` has zero host calls and zero releases; every other terminal row has one list release and an empty resource table.

- [ ] **Step 3: Preserve the clean pre-promotion boundary.**

Run:

```bash
git diff --check
git diff -- src/build/p3_async_manifest.zig src/build/p3_async_registry.json src/build/sema_imports.zig
```

Expected: no compiler admission or registry row exists yet. Commit only a dated baseline note if a tool version or hash changed; otherwise continue without a commit.

### Task 2: Add an isolated manifest shape and exact registry descriptor

**Files:**
- Modify: `src/build/p3_async_manifest.zig: LoweringShape, Canonical, descriptor parser/free helpers, lowering_shape`
- Modify: `src/build/p3_async_registry.json: descriptors[]`
- Test: `src/build/p3_async_manifest.zig`

**Interfaces:** Produces `p3_async_manifest.ScalarListStreamProducerShape` with `element`, `stream_index`, `method`, `stream`, `list_layout`, and `producer`; the shape uses `scalar-list-stream-producer` as its effect and is independent of all resource-list shapes.

- [ ] **Step 1: Write manifest red tests.**

Add tests named `scalar list producer descriptor is admitted only with measured layout` and `scalar list producer descriptor rejects drift`. Construct the valid descriptor with:

```text
locator = do:g6-2-scalar-list-producer@0.1.0
member = consume-via-stream
effect = scalar-list-stream-producer
params = [stream<list<u32>>]
result = Result<nil,error-code>
wit = package do:g6-2-scalar-list-producer@0.1.0,
      interface sink, operation consume-via-stream,
      world scalar-list-producer, parameter data
canonical.core_params = [i32, i32]
canonical.core_results = [i32]
canonical.completion_params = [i32, i32]
canonical.completion = task-return
canonical.async_import_module = do:g6-2-scalar-list-producer/sink@0.1.0
canonical.async_import_name = [async-lower]consume-via-stream
scalar_list_layout = pointer=64, length=68, stride=4, max_items=3
scalar_list_producer = stream_capacity=1, runtime_count_param=u32,
                        runtime_max=3, terminal=task-return
```

The red tests must mutate one fact at a time: WIT hash, package/world/member, element text, pointer offset, length offset, stride, maximum, stream capacity, terminal, runtime count type, or a non-empty resource/record/future field. Run:

```bash
cd src
zig test build/p3_async_manifest.zig --test-filter 'scalar list producer'
```

Expected: the valid descriptor fails before the new shape exists, while every drift case remains rejected.

- [ ] **Step 2: Add the scalar-only data structures and parser ownership.**

Introduce `ScalarListLayout`, `ScalarListProducerCanonical`, and `ScalarListStreamProducerShape`. Add nullable canonical fields with explicit parse and deinit paths; do not reinterpret `list_resource_layout` or `ProducerCanonical`. Require the scalar producer field to be present exactly once, require `resource`, `record_layout`, `list_resource_layout`, `future`, `future_input`, `future_owned`, `result_payload`, and `error_variants` to be absent, and reject unknown scalar-list fields through the existing JSON schema checks.

- [ ] **Step 3: Add one exact registry row.**

Insert one descriptor for `do:g6-2-scalar-list-producer@0.1.0` using the probe's stream operation imports (`[stream-new-0]`, cancel/drop, and `[async-lower][stream-read/write-0]`) and the exact canonical values above. Do not change the neighboring `do:g6-2-c-min-*` rows.

- [ ] **Step 4: Run parser, drift, and manifest tests.**

Run:

```bash
cd src
zig test build/p3_async_manifest.zig
zig test build/p3_async_manifest.zig --test-filter 'scalar list producer'
```

Expected: all existing manifest tests remain green, the valid row returns `.scalar_list_stream_producer`, and every malformed descriptor returns `null` or `error.InvalidP3AsyncManifest` before codegen.

- [ ] **Step 5: Commit the manifest boundary.**

```bash
git diff --check
git add src/build/p3_async_manifest.zig src/build/p3_async_registry.json
git commit -m "feat: register bounded scalar list producer shape"
```

### Task 3: Add exact semantic admission for the Do topology

**Files:**
- Modify: `src/build/sema_imports.zig: p3_async_signature_matches and producer signature helpers`
- Test: `src/build/sema_imports.zig`

**Interfaces:** The admitted source contains exactly one `@host_async_func` named `consume`, no source host function, one `produce(count u32) -> Result<nil, ProducerError>` function with a fixed `return Ok()` body, one empty `start()`, and no `async`, `@async`, `@await`, or `@cancel` token. The sink signature is exactly `(StreamWriter<[u32]>) -> Result<nil, ProducerError>` and its locator/member are pinned.

- [ ] **Step 1: Write red signature tests.**

Add tests for the valid topology and for these rejected inputs: `StreamWriter<[i32]>`, `StreamWriter<[text]>`, `StreamWriter<u32>`, `count i64`, `Result<nil,OtherError>`, a second host binding, a second `produce`, a non-empty producer body, an async declaration, and an unregistered locator/member. Run:

```bash
cd src
zig test build/sema_imports.zig --test-filter 'scalar list producer'
```

Expected: the valid case is rejected until the new signature branch exists; all negative cases are rejected before generic host signature fallback.

- [ ] **Step 2: Implement the narrow signature predicate.**

Add a `.scalar_list_stream_producer` branch and a dedicated `scalar_list_stream_producer_signature_matches` function. Match the token sequence `StreamWriter < [ u32 ] >`, `Result < nil , ProducerError >`, and the exact function/topology counts; never infer admission from a generic `list<T>` token shape.

- [ ] **Step 3: Run sema and existing import tests.**

Run:

```bash
cd src
zig test build/sema_imports.zig
```

Expected: all existing import tests pass and only the pinned scalar-list topology is admitted.

- [ ] **Step 4: Commit semantic admission.**

```bash
git diff --check
git add src/build/sema_imports.zig
git commit -m "feat: admit bounded scalar list producer signature"
```

### Task 4: Implement the independent scalar-list emitter and opt-in dispatch

**Files:**
- Create: `src/build/codegen_component_scalar_list_stream_producer.zig`
- Create: `src/build/cmin_scalar_list_stream_producer_template.wat`
- Modify: `src/build/codegen_component_async.zig: imports, Target, WAT/WIT dispatch, target_for_tokens_with_graph, target_for_descriptor`
- Test: `src/build/codegen_component_scalar_list_stream_producer.zig`
- Test: `src/build/codegen_component_async.zig`

**Interfaces:** Export `ScalarListStreamProducerPlan.analyze`, `emit_component_wat_for_tokens`, and `emit_component_wit_for_tokens`; use `error.UnsupportedP3ScalarListProducer` internally and map it to `error.UnsupportedP3AsyncComponent` at the generic dispatcher boundary. The adapter must select the new target only when the exact descriptor and sema topology match.

- [ ] **Step 1: Write emitter red tests.**

Add unit tests that analyze the positive fixture, reject a different stream element and producer body, and assert the emitted WAT contains the five layout markers, the values `10`, `20`, `30`, the transfer marker, the cleanup marker, and no `[resource-drop]` import. Add a WIT assertion for package `do:g6-2-scalar-list-producer@0.1.0`, world `scalar-list-producer`, and `stream<list<u32>>`.

- [ ] **Step 2: Implement plan analysis and internal guards.**

`ScalarListStreamProducerPlan` stores the descriptor, sink binding name, root name, count name, measured scalar list layout, and producer canonical facts. `analyze` must find exactly one sink binding, require the descriptor's `.scalar_list_stream_producer` variant, require the exact fixture topology from Task 3, and reject any extra function/host binding. `validate_internal_plans` must use `wit_abi_types.AbiType.list` over `u32` and `wit_abi_layout.ListLayoutPlan` with pointer `64`, length `68`, stride `4`, capacity `3`, and accepted lengths `[0,1,2,3]`; no ownership/resource plan is constructed.

- [ ] **Step 3: Implement the fixed WAT template.**

Use a fresh template with only the sink async/stream imports and standard root async imports. The exported `produce` checks `count <= 3`, allocates `count * 4` bytes with `cabi_realloc`, stores the pointer/length words at the measured frame/result locations, writes `10`, `20`, and `30` for the first three positions, transfers one list item through the capacity-one stream, awaits the sink, and returns the sink result. The invalid branch returns `invalid-mode` before `stream-new`, `stream-write`, or allocation.

The terminal cleanup state machine must have one explicit list-release bit. Ready, pending, sink-error, early-drop, cancel-before-transfer, and cancel-after-transfer all release allocated list storage exactly once; after transfer, the guest list pointer/length is cleared before release. Cleanup order is child subtask, waitable set, stream readable/writable handles, list storage, frame. There is no resource drop, ticket slot, or `ResourceTable` state.

- [ ] **Step 4: Add opt-in dispatcher branches.**

Add `scalar_list_stream_producer` to `Target`, import the new emitter, dispatch both WAT and generated WIT, classify the new descriptor in `target_for_tokens_with_graph`, and map the new shape in `target_for_descriptor`. Keep the old producer branches and default/v2 dispatch unchanged. When the target is selected but analysis fails, return `UnsupportedP3AsyncComponent` before calling any WAT emitter.

- [ ] **Step 5: Run focused codegen tests.**

Run:

```bash
cd src
zig test build/codegen_component_scalar_list_stream_producer.zig
zig test build/codegen_component_async.zig --test-filter 'scalar list producer'
```

Expected: the positive plan emits a WAT/WIT pair; malformed plans fail closed and no existing resource producer test changes behavior.

- [ ] **Step 6: Commit the compiler adapter.**

```bash
git diff --check
git add src/build/codegen_component_scalar_list_stream_producer.zig \
  src/build/cmin_scalar_list_stream_producer_template.wat \
  src/build/codegen_component_async.zig
git commit -m "feat: lower bounded scalar list producer"
```

### Task 5: Add Do fixtures and regression coverage

**Files:**
- Create: `examples/p3-runtime/g6-2-scalar-list-producer.do`
- Create: `examples/p3-runtime/test_do_g6_2_scalar_list_producer.sh`
- Create: `src/build/test/check/482_g6_2_scalar_list_producer.do`
- Create: `src/build/test/compile_ok/482_g6_2_scalar_list_producer_component.do`
- Create: `src/build/test/compile_ok/482_g6_2_scalar_list_producer_component.expect`
- Create: `src/build/test/compile_err/483_g6_2_scalar_list_producer_unregistered.do` and `.expect`
- Create: `src/build/test/compile_err/484_g6_2_scalar_list_producer_element.do` and `.expect`
- Create: `src/build/test/compile_err/485_g6_2_scalar_list_producer_count.do` and `.expect`
- Create: `src/build/test/compile_err/486_g6_2_scalar_list_producer_second_sink.do` and `.expect`
- Create: `src/build/test/compile_err/487_g6_2_scalar_list_producer_body.do` and `.expect`
- Create: `src/build/test/compile_err/488_g6_2_scalar_list_producer_borrowed_payload.do` and `.expect`
- Create: `src/build/test/compile_err/489_g6_2_scalar_list_producer_wrong_result.do` and `.expect`

**Interfaces:** The positive fixture is the exact private topology; the negative fixtures exercise source admission, not runtime behavior. Each `.expect` contains the stable diagnostic substring returned before WAT emission (`UnsupportedP3AsyncComponent` or the existing host-signature diagnostic used by `sema_imports`).

- [ ] **Step 1: Write the positive fixture and expected output.**

Use:

```do
consume = @host_async_func("do:g6-2-scalar-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[u32]>) -> Result<nil, ProducerError>)
ProducerError error = Io | Pipe | InvalidMode

produce(count u32) -> Result<nil, ProducerError> {
    return Ok()
}

start() {}
```

The expected WAT must contain the scalar markers and the expected WIT must contain `export produce: async func(count: u32) -> result<_, error-code>;`.

- [ ] **Step 2: Add the compile-error fixtures.**

Use these one-at-a-time mutations: locator `...@0.1.1`; `StreamWriter<[i32]>`; `count i64`; a second `@host_async_func`; a body assigning or branching before `return Ok()`; `StreamWriter<[BorrowedEntry]>`; and `Result<Other, ProducerError>`. Do not add public ownership declarations to make a negative fixture pass.

- [ ] **Step 3: Run focused fixture harnesses.**

Run:

```bash
DO_LIB_ROOT="$PWD/lib" ./bin/do test src/build/test/check/482_g6_2_scalar_list_producer.do
DO_LIB_ROOT="$PWD/lib" ./bin/do build --p3-async-component \
  src/build/test/compile_ok/482_g6_2_scalar_list_producer_component.do \
  --p3-wit-output /tmp/g6-2-scalar-list-producer.wit -o /tmp/g6-2-scalar-list-producer.wat
for fixture in \
  483_g6_2_scalar_list_producer_unregistered \
  484_g6_2_scalar_list_producer_element \
  485_g6_2_scalar_list_producer_count \
  486_g6_2_scalar_list_producer_second_sink \
  487_g6_2_scalar_list_producer_body \
  488_g6_2_scalar_list_producer_borrowed_payload \
  489_g6_2_scalar_list_producer_wrong_result; do
  if DO_LIB_ROOT="$PWD/lib" ./bin/do build \
    "src/build/test/compile_err/$fixture.do" \
    -o "/tmp/$fixture.wat"; then
    printf 'unexpected scalar-list compile success: %s\n' "$fixture" >&2
    exit 1
  fi
done
```

Expected: the positive fixture passes and every negative fixture fails before WAT output. The full harness in Task 7 remains the source of truth for `.expect` matching.

- [ ] **Step 4: Commit source fixtures.**

```bash
git diff --check
git add examples/p3-runtime/g6-2-scalar-list-producer.do \
  examples/p3-runtime/test_do_g6_2_scalar_list_producer.sh \
  src/build/test/check/482_g6_2_scalar_list_producer.do \
  src/build/test/compile_ok/482_g6_2_scalar_list_producer_component.do \
  src/build/test/compile_ok/482_g6_2_scalar_list_producer_component.expect \
  src/build/test/compile_err/483_g6_2_scalar_list_producer_unregistered.do \
  src/build/test/compile_err/483_g6_2_scalar_list_producer_unregistered.expect \
  src/build/test/compile_err/484_g6_2_scalar_list_producer_element.do \
  src/build/test/compile_err/484_g6_2_scalar_list_producer_element.expect \
  src/build/test/compile_err/485_g6_2_scalar_list_producer_count.do \
  src/build/test/compile_err/485_g6_2_scalar_list_producer_count.expect \
  src/build/test/compile_err/486_g6_2_scalar_list_producer_second_sink.do \
  src/build/test/compile_err/486_g6_2_scalar_list_producer_second_sink.expect \
  src/build/test/compile_err/487_g6_2_scalar_list_producer_body.do \
  src/build/test/compile_err/487_g6_2_scalar_list_producer_body.expect \
  src/build/test/compile_err/488_g6_2_scalar_list_producer_borrowed_payload.do \
  src/build/test/compile_err/488_g6_2_scalar_list_producer_borrowed_payload.expect \
  src/build/test/compile_err/489_g6_2_scalar_list_producer_wrong_result.do \
  src/build/test/compile_err/489_g6_2_scalar_list_producer_wrong_result.expect
git commit -m "test: cover scalar list producer admission"
```

### Task 6: Promote through Component validation and Rust/Wasmtime

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_scalar_list_producer.rs`
- Create: `examples/p3-runtime/test_rust_g6_2_scalar_list_producer.sh`
- Modify: `examples/p3-runtime/test_do_g6_2_scalar_list_producer.sh`
- Verify: `examples/p3-runtime/rust-host-runner/Cargo.toml`

**Interfaces:** The Do gate produces a core WAT and generated WIT. The Rust runner accepts `<component> <mode>` and reports `result`, ordered `values`, `host-calls`, `pending-polls`, `stream-drops`, `list-releases`, and `table-empty`.

- [ ] **Step 1: Add the generated Component gate.**

`test_do_g6_2_scalar_list_producer.sh` must build with `--p3-async-component --p3-wit-output`, assert the package/world/signature, assert all scalar markers and values `10`, `20`, `30`, reject neighboring package markers, parse the WAT, embed the generated WIT with world `scalar-list-producer` and features `cm-async,cm-more-async-builtins`, create the Component, and validate it with the same features. Compare the generated WIT with the checked-in probe WIT after normalizing only the temporary path, so promotion cannot silently drift from the measured package.

- [ ] **Step 2: Implement the generated-Component host oracle.**

The host sink reads one `list<u32>` stream item, records the values in order, returns `Ok` or `Err(pipe)` by mode, and releases the stream/list exactly once. Modes are `count-0`, `count-1`, `count-2`, `count-3`, `pending`, `sink-error`, `early-drop`, `cancel-before-transfer`, `cancel-after-transfer`, and `count-4`. Assert that no `ResourceTable` entry is created in any mode and that `count-4` never calls the sink.

- [ ] **Step 3: Run all generated runtime rows.**

Run:

```bash
WASM_TOOLS_EXPECT_VERSION=1.255.0 bash examples/p3-runtime/test_do_g6_2_scalar_list_producer.sh
WASM_TOOLS_EXPECT_VERSION=1.255.0 bash examples/p3-runtime/test_rust_g6_2_scalar_list_producer.sh
```

Expected: the generated component matches every row from the evidence-only probe, including pending/error/drop and both cancellation positions. A mismatch in list release count, stream drop count, result, ordered values, or table emptiness is a stop condition; do not weaken the emitter to make the runner pass.

- [ ] **Step 4: Run focused Rust checks and commit the runtime gate.**

Run:

```bash
rustfmt --edition 2024 --check examples/p3-runtime/rust-host-runner/src/bin/g6_2_scalar_list_producer.rs
CC="$PWD/examples/p3-runtime/rust-host-runner/zig-cc.sh" \
CXX="$PWD/examples/p3-runtime/rust-host-runner/zig-cc.sh" \
CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/examples/p3-runtime/rust-host-runner/zig-cc.sh" \
cargo check --locked --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml --bin g6_2_scalar_list_producer
git diff --check
```

Expected: formatting and locked dependency checks pass. Commit:

```bash
git add examples/p3-runtime/test_do_g6_2_scalar_list_producer.sh \
  examples/p3-runtime/test_rust_g6_2_scalar_list_producer.sh \
  examples/p3-runtime/rust-host-runner/src/bin/g6_2_scalar_list_producer.rs
git commit -m "test: run promoted scalar list producer component"
```

### Task 7: Close out the bounded promotion

**Files:**
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/master_plan.md`
- Modify: `doc/pending_blocked.md`
- Modify: `CHANGELOG.md`

**Interfaces:** Documentation records only verified commands and preserves the remaining generalization boundaries.

- [ ] **Step 1: Run the complete regression matrix.**

Run:

```bash
cd src && zig test main.zig
cd ..
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

Expected: `zig test main.zig` remains `312/312`; default regression remains `1158/0/3`; Wasm regression remains `1160/0/3` with smoke `6/6`; ReleaseSmall smoke remains `8/8`.

- [ ] **Step 2: Update status from the fresh output.**

Record the new private capability as `stream<list<u32>>`, `max-items=3`, with its exact probe and generated runtime gates. State explicitly that this is not generic `list<T>`, not a resource/borrowed payload, not arbitrary producer lowering, and not public ownership syntax. Keep `future<borrow<T>>`, borrowed stream records, general async-call lowering, D2 filesystem/HTTP, and public `own<T>/borrow<T>/ref<T>` in their existing pending/deferred sections unless a separate green gate exists.

- [ ] **Step 3: Commit the phase closeout.**

```bash
git add doc/start_here.md doc/roadmap_status.md doc/master_plan.md \
  doc/pending_blocked.md CHANGELOG.md
git commit -m "docs: record scalar list producer promotion"
```

If any Task 6 gate is red, do not mark promotion complete. Instead add the exact blocker, command, stderr, and next independent action to `doc/pending_blocked.md`; keep the implementation commits isolated and do not add a compatibility fallback.

## Self-Review

- **Spec coverage:** The existing scalar-list design's WIT identity, layout, count matrix, cleanup, cancellation, and no-public-ownership boundary each have a task and a verification command.
- **Placeholder scan:** No task depends on an unspecified generic helper or future toolchain; every created/modified path, fixture number, descriptor field, mode, and gate command is named.
- **Type consistency:** The registry uses `stream<list<u32>>`; sema uses `StreamWriter<[u32]>`; the producer parameter is `count u32`; the generated WIT uses `result<_, error-code>`; the runtime runner checks the same nine rows as the canonical probe.
- **Failure behavior:** Unknown locator, signature drift, unbounded count, borrowed/resource nested payload, allocation/layout drift, and runtime cleanup mismatches all fail closed before promotion can be reported complete.
- **Scope:** No general `list<T>` lowering, arbitrary producer expression, general async-call lowering, D2 filesystem/HTTP lowering, or public ownership/reference feature is included.
