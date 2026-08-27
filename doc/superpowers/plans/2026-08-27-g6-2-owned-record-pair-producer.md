# G6.2 Two-Owned-Field Record Producer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Goal:** Admit one private, hash-pinned `stream<resource-pair>` producer that transfers two owned ticket handles atomically and proves exactly-once cleanup across the complete lifecycle matrix.

**Architecture:** Keep the existing single-field `owned_record_stream_producer` route unchanged. Add a separate `record_resource_pair_stream_producer` lowering shape, exact fail-closed semantic predicate, isolated WAT/WIT emitter, canonical artifact, and Rust/Wasmtime oracle. The pair template owns two handle words plus an independent presence bitmask; ownership changes only after the complete record write succeeds.

**Tech Stack:** Zig 0.16.0 compiler, `wasm-tools` 1.255.0 Component Model tooling, Rust/Cargo 1.97.1, Wasmtime 47.0.2, Bash regression gates.

**Spec:** `doc/superpowers/specs/2026-08-27-g6-2-owned-record-pair-producer-design.md`

## Global Constraints

- Admit only descriptor `do:g6-2-owned-record-pair-producer@0.1.0` and the exact source shape in the spec.
- Pin WIT SHA-256 to `89345a5213936735d7f065cd54ed42b83d159b80305a1a900ae00df2e811704d` including the final newline.
- Keep `left` at offset `0`, `right` at offset `4`, record size `8`, alignment `4`, stream capacity `1`, and source core signature `(i32) -> (i32)`.
- Use an ownership presence mask; handle value `0` is valid and is never an absence sentinel.
- Transfer both fields atomically; before transfer drop `right` then `left`, after transfer the host drops both exactly once.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, `Option`, or `Result` syntax, generic producer inference, arbitrary async lowering, or compatibility aliases.
- Do not change the existing single-field producer, existing inventory row counts, or default routes.
- Use project-local temporary/cache paths when running Zig/Cargo gates: `TMPDIR="$PWD/.tmp/do-tmp"`, `ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache"`, and `ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache"`.
- Preserve unrelated worktree changes and stage only files belonging to this plan.

## File Map

- Create `examples/p3-runtime/wit/g6-2-owned-record-pair-producer.wit` with the pinned WIT contract.
- Create `src/build/owned_record_pair_stream_producer_template.wat` and `src/build/codegen_component_owned_record_pair_stream_producer.zig` for the isolated canonical/template route.
- Modify `src/build/p3_async_manifest.zig` and `src/build/p3_async_registry.json` to add the new shape and hash-pinned descriptor row.
- Modify `src/build/sema_imports.zig` and `src/build/codegen_component_async.zig` only to route the exact shape and preserve fail-closed diagnostics.
- Create `examples/p3-runtime/g6-2-owned-record-pair-producer.do`, its canonical WAT, and positive/negative/equivalence shell gates.
- Create `examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_pair_producer_abi.rs` and a thin runner binary entry if the existing runner convention requires it; update `Cargo.toml` with only the two pair binaries.
- Modify the relevant Zig unit-test aggregation, `src/build/test/check_gc_semantic_equivalence.sh` only if an independent non-ARC row is required by the existing gate, and the G6.2 status/readme documents after all behavior gates pass.

### Task 1: Pin WIT and establish the ABI oracle

**Files:**
- Create: `examples/p3-runtime/wit/g6-2-owned-record-pair-producer.wit`
- Create: `examples/p3-runtime/g6-2-owned-record-pair-producer-canonical.wat`
- Create: `examples/p3-runtime/test_g6_2_owned_record_pair_producer_abi.sh`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_pair_producer_abi.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`

**Interfaces:**
- The WIT file is the exact source in the spec: package `do:g6-2-owned-record-pair-producer@0.1.0`, `ticket`, `resource-pair { left: own<ticket>, right: own<ticket> }`, source `make-ticket`, sink `consume-via-stream`, and world `owned-record-pair-producer`.
- The ABI script must invoke `wasm-tools parse`, `component embed`, `component new --skip-validation`, and `validate` with `cm-async,cm-more-async-builtins`, then assert the pinned hash and canonical markers.
- The Rust oracle accepts `<component> <mode>`, records received seeds, callback/poll/cancel/drop counts, ticket creation/drop counts, and `ResourceTable` emptiness, and emits stable `key=value` lines consumed by shell gates.

- [x] **Step 1: Add the exact WIT source and verify its hash.**

  Run:

  ```bash
  sha256sum examples/p3-runtime/wit/g6-2-owned-record-pair-producer.wit
  ```

  Expected: `89345a5213936735d7f065cd54ed42b83d159b80305a1a900ae00df2e811704d`.

- [x] **Step 2: Add a hand-authored canonical Core-WAT template.**

  It must contain the measured stream/task/drop imports, an 8-byte record slot, two handle locals, a separate mask local, seeds `111` and `222`, one capacity-one write, markers for offsets/transfer/drop ordering, and no `__arc_` symbol. The write path clears both guest bits only after status `0` confirms complete transfer; every pre-transfer cleanup tests mask bits rather than handle values.

- [x] **Step 3: Implement the Rust/Wasmtime oracle for all ten modes.**

  Use one Store per mode except `repeat`, which invokes the producer twice on one Store. Assert the expected seeds and exact two-ticket cleanup for `ready`, `pending`, `sink-error-before`, `sink-error-after`, `cancel-before-transfer`, `cancel-after-transfer`, `early-drop-before-transfer`, `early-drop-after-transfer`, `repeat`, and `invalid`.

- [x] **Step 4: Run the ABI gate before compiler changes.**

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_g6_2_owned_record_pair_producer_abi.sh
  ```

  Expected: the script assembles the canonical component, validates it, and the oracle reports two received seeds, two ticket drops, one stream/task cleanup, and `table-empty=true` for each valid row; invalid reports zero creation/drop.

### Task 2: Register the descriptor and exact semantic admission

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/sema_imports.zig`
- Modify: `src/build/codegen_component_async.zig`
- Test: unit tests in `src/build/p3_async_manifest.zig`, `src/build/sema_imports.zig`, and `src/build/codegen_component_async.zig`

**Interfaces:**
- Add `record_resource_pair_stream_producer: OwnedRecordPairStreamProducerShape` to `LoweringShape`.
- The shape carries the canonical stream, record layout, and producer facts needed by the isolated emitter; it must not reuse a generic “any owned record” predicate.
- `p3_async_signature_matches` dispatches the new shape to a dedicated exact signature matcher and returns the existing `UnsupportedP3AsyncComponent` boundary on mismatch.

- [x] **Step 1: Add the manifest shape and exact validator.**

  Validate descriptor locator/member/effect, WIT package/interface/operation/world, hash, core parameters/results, stream operation arities, record fields, ownership/drop imports, producer mode, seeds, and capacity against the spec. Return `null` on any drift.

- [x] **Step 2: Add one hash-pinned registry row.**

  Record the exact descriptor, `record-resource-pair-stream-producer` effect, WIT metadata, canonical stream/task/drop operations, record size/alignment/offsets, source signature, both resource fields, capacity, and the generated WIT hash. Do not add aliases or alter neighboring rows.

- [x] **Step 3: Add an exact Do signature matcher and routing target.**

  Admit exactly `StreamWriter<ResourcePair> -> Result<nil, ProducerError>` for the sink binding and exactly the source binding/resource/record/error/sentinel topology from the spec, including local binding names `make_ticket` and `consume`. Reject renamed bindings, reordered/extra/scalar/nested/list/borrowed fields, wrong binding kinds, async tokens/intrinsics, extra declarations, and unregistered descriptors before WAT emission.

- [x] **Step 4: Add focused unit tests and run them.**

  Run:

  ```bash
  zig test src/build/p3_async_manifest.zig
  zig test src/build/sema_imports.zig
  zig test src/build/codegen_component_async.zig
  ```

  Expected: the positive exact shape resolves to the new target; all negative mutations resolve to `UnsupportedP3AsyncComponent`; existing single-field tests remain green.

### Task 3: Implement the isolated pair emitter and Do fixtures

**Files:**
- Create: `src/build/codegen_component_owned_record_pair_stream_producer.zig`
- Create: `src/build/owned_record_pair_stream_producer_template.wat`
- Create: `examples/p3-runtime/g6-2-owned-record-pair-producer.do`
- Create: `examples/p3-runtime/test_do_g6_2_owned_record_pair_producer.sh`
- Create: `examples/p3-runtime/test_do_g6_2_owned_record_pair_producer_negative.sh`
- Modify: `src/build/codegen_component_async.zig`

**Interfaces:**
- `OwnedRecordPairStreamProducerPlan.analyze(tokens, registry)` returns the exact plan or `UnsupportedP3OwnedRecordPairStreamProducer`.
- `emit_component_wat_for_tokens` returns only the pinned pair template after internal layout checks and rejects ARC markers.
- `emit_component_wit_for_tokens` returns byte-identical pinned WIT.

- [x] **Step 1: Write the positive Do fixture and a failing compiler gate.**

  Use exactly the source shape in the spec, with `make_ticket`, `consume`, `Ticket`, `ResourcePair`, `ProducerError`, sentinel `produce(mode u32) -> Result<nil, ProducerError> { return Ok() }`, and empty `start()`.

- [x] **Step 2: Implement the plan analyzer and emitter.**

  Reuse only pure parsing/layout helpers; keep the pair-specific record offsets, mask transitions, seeds, and marker text in the new module/template. Do not widen the single-field emitter or add a generic producer branch.

- [x] **Step 3: Add negative fixtures for every boundary listed by the spec.**

  Include old descriptor/locator, renamed local bindings, reversed/third/scalar/nested/list/borrowed fields, wrong source/sink signature or binding kind, duplicate bindings, changed mode/body, async token/intrinsics, seventh hop, arbitrary producer expression, generic list/variant, and unregistered descriptor. Each `.expect` must retain `UnsupportedP3AsyncComponent`.

- [x] **Step 4: Run the Do Component gate.**

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache" bash examples/p3-runtime/test_do_g6_2_owned_record_pair_producer.sh
  bash examples/p3-runtime/test_do_g6_2_owned_record_pair_producer_negative.sh
  ```

  Expected: generated WIT matches the pinned source/hash, generated WAT has the 8-byte/offset/mask/atomic-transfer markers, contains no ARC symbols, and all negatives fail closed before emission.

### Task 4: Add generated lifecycle and canonical-equivalence gates

**Files:**
- Create: `examples/p3-runtime/test_rust_g6_2_owned_record_pair_producer.sh`
- Create: `examples/p3-runtime/test_g6_2_owned_record_pair_producer_equivalence.sh`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_pair_producer.rs` if the Cargo bin wrapper is needed
- Modify: `examples/p3-runtime/README.md` only for a concise gate entry after green verification

**Interfaces:**
- The generated gate compiles the positive Do source, assembles/validates the Component, and runs all ten oracle modes.
- The equivalence gate assembles both canonical and generated Core-WAT/Components and diffs normalized oracle output for every mode; it remains separate from the ARC/GC semantic-equivalence row count.

- [x] **Step 1: Run generated lifecycle modes with exact expected counters.**

  Assert `[111,222]` for all post-transfer valid modes, `[]` for before-transfer/error/invalid modes, two ticket creations/drops per invocation, four/four in repeat, exactly one stream/task cleanup per invocation, and `table-empty=true`.

- [x] **Step 2: Run canonical-vs-generated equivalence.**

  Run the dedicated script with local Cargo/Zig caches. Expected: ten mode outputs are byte-equivalent after the declared component identity fields, with no pending equivalence row silently counted as complete.

- [x] **Step 3: Re-run the old single-field gates.**

  Run `test_do_g6_2_owned_record_producer.sh`, `test_g6_2_owned_record_producer_abi.sh`, and `test_g6_2_owned_record_producer_equivalence.sh`. Expected: unchanged output and lifecycle counters.

- [x] **Step 4: Close lifecycle-observation review findings.**

  Add a real host-future wrapper and independent counters for async-import
  callbacks, stream-consumer polls, `finish=true`, future completion/drop, and
  host-task cancellation. The Wasmtime 47.0.2 observation is explicit: task
  cancellation aborts the host future (`cancel-calls=1` and
  `pending-future-drops=1`) but does not invoke a stream consumer finish callback
  (`finish-calls=0`); pending and before/after-transfer poll counts are asserted
  by mode in the ABI gate.

### Task 5: Full verification, inventory, and documentation closure

**Files:**
- Modify: `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/master_plan.md`, `doc/start_here.md`, `CHANGELOG.md`, and `examples/p3-runtime/README.md` only after all gates pass
- Modify: `src/build/test/check_gc_semantic_equivalence.sh` only if the existing independent row registry requires a pair row; do not alter its established `complete_rows=15 pending_rows=15` result for this independent Component gate

**Interfaces:**
- Documentation must state that the pair descriptor is private and bounded, list the ABI and lifecycle evidence, and keep generic producer/borrowed/list/variant/general async/GC cutover entries pending.
- The migration inventory remains deliberately `complete_rows=15 pending_rows=15` with exit `1`; this new independent gate is not an ARC/GC equivalence row.

- [x] **Step 1: Run compiler/unit/integration verification.**

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache" ./src/build/test/run_tests.sh
  zig test main.zig
  cd src && TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig build -Doptimize=ReleaseSmall
  ```

  Expected: full regression has no new failures, Zig tests pass, and ReleaseSmall installs the compiler to `bin/do`.

  Observed 2026-08-28: `run_tests.sh` `pass=1400 fail=0 skip=3`, `cd src && zig test main.zig` `688/688`, and ReleaseSmall build completed successfully.

- [x] **Step 2: Run release smoke and inventory gates.**

  Run the repository-standard release smoke command plus the relevant G6.2 gates and the migration inventory checker. Expected: all required bounded gates pass; inventory still reports `complete_rows=15 pending_rows=15` and exit `1` by design.

  Observed 2026-08-28: release smoke, pair/old single-field gates, GC default `86 fixtures`, and semantic-equivalence `26 rows; 0 pending` passed; inventory reported `complete_rows=15 pending_rows=15` with expected exit `1`.

- [x] **Step 3: Synchronize documentation from observed output.**

  Record exact command results, tool versions, WIT hash, record layout, ownership mask rule, ten-mode cleanup evidence, and residual non-goals. Do not copy stale counts from older `doc/start_here.md` rows.

  Observed 2026-08-28: current counts and the private bounded/non-goal boundary were synchronized across the status, handoff, README, changelog, and example documents.

- [x] **Step 4: Review the final diff; commit/push remains deferred until explicit delivery authorization.**

  Run:

  ```bash
  git diff --check
  git status --short
  git diff --stat
  ```

  Expected: no whitespace errors, no unrelated file changes, and all required artifacts are present. Commit with a concise subject such as `feat: add bounded two-owned-field producer gate` only after verification; pushing is outside this plan unless explicitly requested.

  Observed 2026-08-28: `git diff --check` passed; all modified/untracked paths are within the pair-producer implementation, tests, plan/spec, and synchronized status documentation. No commit or push was performed.

## Self-Review Checklist

- [x] Every requirement in `doc/superpowers/specs/2026-08-27-g6-2-owned-record-pair-producer-design.md` maps to a task and an executable gate.
- [x] A literal placeholder-token scan over this plan returns no matches.
- [x] Pair code has no dependency on the single-field route's admission predicate or template.
- [x] WIT hash, locator distinction, stream operation set, layout, ownership mask, and lifecycle modes are consistent across WIT, manifest, WAT, Do, shell, and Rust.
- [x] No completion claim is made until canonical, generated, full regression, ReleaseSmall, and inventory evidence are captured.
