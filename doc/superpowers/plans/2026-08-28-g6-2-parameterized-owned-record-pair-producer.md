# G6.2 Parameterized Two-Owned-Field Record Producer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Goal:** Add one private, hash-pinned `stream<resource-pair>` producer whose two owned ticket seeds are explicit `u32` inputs, while preserving the closed static pair route and proving exactly-once cleanup.

**Architecture:** First isolate and commit the already verified static pair baseline. Then add a separate `record-resource-pair-parameterized-stream-producer` lowering shape, manifest row, fail-closed Do admission, WAT template, and Rust/Wasmtime oracle. The new emitter owns two handle words plus a presence mask and changes ownership only after the complete record write succeeds; it does not widen any generic producer predicate.

**Tech Stack:** Zig `0.16.0`, `wasm-tools 1.255.0`, Rust/Cargo `1.97.1`, Wasmtime `47.0.2`, Bash regression gates, and the existing `do` compiler test harness.

**Spec:** `doc/superpowers/specs/2026-08-28-g6-2-parameterized-owned-record-pair-producer-design.md`

## Global Constraints

- Keep `do:g6-2-owned-record-pair-producer@0.1.0` byte-compatible and independently runnable.
- Admit only `do:g6-2-owned-record-pair-parameterized-producer@0.1.0` with the exact WIT hash `e7abd3cf7b7543325865a0b4be4b32ae50a2470ac5083169250719f89b7ce53a`.
- The new Do sentinel has exactly `produce(mode u32, left_seed u32, right_seed u32)`; the WIT export order is `mode`, `left-seed`, `right-seed`.
- Keep the pair record at 8 bytes/alignment 4, `left@0`, `right@4`, stream capacity 1, and source ABI `(i32) -> (i32)`.
- Use presence bits, never handle value `0`, for ownership state; before-transfer cleanup is `right` then `left`, and successful transfer is atomic for both fields.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, `Option`, or `Result` syntax; do not admit generic producers, arbitrary producer expressions, borrowed/list/variant/mixed payloads, or general async/resource lowering.
- Keep migration inventory at `complete_rows=15 pending_rows=15` with deliberate exit `1`; this Component gate is not an ARC/GC semantic-equivalence row.
- Use project-local caches when needed: `TMPDIR="$PWD/.tmp/do-tmp"`, `ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache"`, and `ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache"`.
- Stage only files belonging to the baseline or this plan; preserve unrelated worktree changes. Pushing is a separate explicit delivery action.

## File Map

Baseline files already present in the worktree:

- `CHANGELOG.md`, `README.md`, `doc/master_plan.md`, `doc/pending_blocked.md`, `doc/roadmap_status.md`, `doc/start_here.md`
- `doc/superpowers/specs/2026-08-27-g6-2-owned-record-pair-producer-design.md`
- `doc/superpowers/plans/2026-08-27-g6-2-owned-record-pair-producer.md`
- `examples/p3-runtime/README.md`, `examples/p3-runtime/rust-host-runner/Cargo.toml`
- `src/build/codegen_component_async.zig`, `src/build/p3_async_manifest.zig`, `src/build/p3_async_registry.json`, `src/build/sema_imports.zig`
- existing static pair WIT/Do/WAT/Rust/gate files, pair emitter/template, and compile-error fixtures.

New parameterized-route files:

- Create `examples/p3-runtime/wit/g6-2-owned-record-pair-parameterized-producer.wit`.
- Create `examples/p3-runtime/g6-2-owned-record-pair-parameterized-producer-canonical.wat`.
- Create `src/build/codegen_component_parameterized_owned_record_pair_stream_producer.zig` and `src/build/parameterized_owned_record_pair_stream_producer_template.wat`.
- Create `examples/p3-runtime/g6-2-owned-record-pair-parameterized-producer.do`.
- Create `examples/p3-runtime/test_g6_2_owned_record_pair_parameterized_producer_abi.sh`.
- Create `examples/p3-runtime/test_do_g6_2_owned_record_pair_parameterized_producer.sh` and `test_do_g6_2_owned_record_pair_parameterized_producer_negative.sh`.
- Create `examples/p3-runtime/test_rust_g6_2_owned_record_pair_parameterized_producer.sh` and `test_g6_2_owned_record_pair_parameterized_producer_equivalence.sh`.
- Create `examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_pair_parameterized_producer_abi.rs` and `g6_2_owned_record_pair_parameterized_producer.rs` if the runner convention requires a wrapper.
- Add one manifest/registry shape and target route in `src/build/p3_async_manifest.zig`, `src/build/p3_async_registry.json`, and `src/build/codegen_component_async.zig`; add only the required semantic admission helpers/tests in `src/build/sema_imports.zig`.
- Add numbered compile-error fixtures `702` onward for the parameterized signature and boundary mutations.

### Task 1: Isolate and commit the verified static pair baseline

**Files:** only the existing pair-related paths listed under “Baseline files already present”.

**Interfaces:** Consumes the current worktree's verified static pair implementation. Produces a local commit that makes the old descriptor a stable dependency for the new route.

- [ ] **Step 1: Confirm the baseline file set.**

  Run:

  ```bash
  git status --short
  git diff --check
  git diff --name-only
  ```

  Expected: every modified/untracked path is part of the static pair implementation, its gates, or its synchronized documentation; stop before staging if an unrelated path appears.

- [ ] **Step 2: Re-run the narrow static pair gates.**

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache" bash examples/p3-runtime/test_g6_2_owned_record_pair_producer_abi.sh
  TMPDIR="$PWD/.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache" bash examples/p3-runtime/test_do_g6_2_owned_record_pair_producer.sh
  bash examples/p3-runtime/test_do_g6_2_owned_record_pair_producer_negative.sh
  bash examples/p3-runtime/test_rust_g6_2_owned_record_pair_producer.sh
  bash examples/p3-runtime/test_g6_2_owned_record_pair_producer_equivalence.sh
  ```

  Expected: all ten static modes remain green, the WIT hash is unchanged, and cleanup remains `2/2` (repeat `4/4`) with `table-empty=true`.

- [ ] **Step 3: Commit only the static baseline.**

  Stage the exact existing pair paths and commit:

  ```bash
  git add CHANGELOG.md README.md doc/master_plan.md doc/pending_blocked.md doc/roadmap_status.md doc/start_here.md \
    doc/superpowers/specs/2026-08-27-g6-2-owned-record-pair-producer-design.md \
    doc/superpowers/plans/2026-08-27-g6-2-owned-record-pair-producer.md \
    examples/p3-runtime/README.md examples/p3-runtime/rust-host-runner/Cargo.toml \
    examples/p3-runtime/g6-2-owned-record-pair-producer.do \
    examples/p3-runtime/g6-2-owned-record-pair-producer-canonical.wat \
    examples/p3-runtime/wit/g6-2-owned-record-pair-producer.wit \
    examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_pair_producer.rs \
    examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_pair_producer_abi.rs \
    examples/p3-runtime/test_do_g6_2_owned_record_pair_producer.sh \
    examples/p3-runtime/test_do_g6_2_owned_record_pair_producer_negative.sh \
    examples/p3-runtime/test_g6_2_owned_record_pair_producer_abi.sh \
    examples/p3-runtime/test_g6_2_owned_record_pair_producer_equivalence.sh \
    examples/p3-runtime/test_rust_g6_2_owned_record_pair_producer.sh \
    src/build/codegen_component_owned_record_pair_stream_producer.zig \
    src/build/owned_record_pair_stream_producer_template.wat \
    src/build/test/compile_err/700_g6_2_owned_record_pair_producer_extra_field.do \
    src/build/test/compile_err/700_g6_2_owned_record_pair_producer_extra_field.expect \
    src/build/test/compile_err/701_g6_2_owned_record_pair_producer_renamed_binding.do \
    src/build/test/compile_err/701_g6_2_owned_record_pair_producer_renamed_binding.expect \
    src/build/codegen_component_async.zig src/build/p3_async_manifest.zig src/build/p3_async_registry.json src/build/sema_imports.zig
  git diff --cached --check
  git commit -m "feat: add bounded two-owned-field producer gate"
  ```

  Expected: the commit contains no parameterized-route files; the worktree is clean apart from any unrelated pre-existing changes.

### Task 2: Pin the parameterized WIT and canonical ABI oracle

**Files:**

- Create `examples/p3-runtime/wit/g6-2-owned-record-pair-parameterized-producer.wit`.
- Create `examples/p3-runtime/g6-2-owned-record-pair-parameterized-producer-canonical.wat`.
- Create `examples/p3-runtime/test_g6_2_owned_record_pair_parameterized_producer_abi.sh`.
- Create the two parameterized Rust runner binaries and modify `Cargo.toml` with only their `[[bin]]` entries.

**Interfaces:** The WIT and canonical WAT are the ABI oracle consumed by manifest validation, the Do emitter, and the generated/canonical equivalence gate.

- [ ] **Step 1: Add the exact WIT source.**

  Use the source in the spec verbatim. Its package is
  `do:g6-2-owned-record-pair-parameterized-producer@0.1.0`; the world is
  `owned-record-pair-parameterized-producer`; the export is
  `produce(mode: u32, left-seed: u32, right-seed: u32) -> result<_, error-code>`.

- [ ] **Step 2: Lock the source hash before compiler changes.**

  Run:

  ```bash
  test "$(sha256sum examples/p3-runtime/wit/g6-2-owned-record-pair-parameterized-producer.wit | awk '{print $1}')" = \
    e7abd3cf7b7543325865a0b4be4b32ae50a2470ac5083169250719f89b7ce53a
  ```

  Expected: the command exits `0`; a mismatch stops this plan.

- [ ] **Step 3: Build the canonical WAT and ABI script.**

  The WAT must contain an 8-byte pair slot, source seed parameters loaded in `left` then `right` order, a separate mask, one capacity-one write, explicit transfer/drop markers, and no `__arc_` symbol. The script must run `wasm-tools 1.255.0` `parse`, `component embed`, `component new --skip-validation`, and `validate` with `cm-async,cm-more-async-builtins`, then assert the 8-byte/offset/three-input facts and absence of GC references.

- [ ] **Step 4: Implement the ABI runner and run the oracle.**

  The runner accepts `<component> <mode> <left-seed> <right-seed>`, records received seed order and callback/poll/cancel/future/ticket/stream counters, and reports stable `key=value` lines. Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_g6_2_owned_record_pair_parameterized_producer_abi.sh
  ```

  Expected: canonical assembly/validation passes and the matrix values match the spec before any compiler route is added.

### Task 3: Register the descriptor and add exact fail-closed admission

**Files:**

- Modify `src/build/p3_async_manifest.zig`, `src/build/p3_async_registry.json`, `src/build/codegen_component_async.zig`, and `src/build/sema_imports.zig`.
- Add focused Zig unit tests and numbered compile-error fixtures `702` onward.

**Interfaces:** Produces `ParameterizedOwnedRecordPairStreamProducerShape`, target `parameterized_owned_record_pair_stream_producer`, and an exact `ParameterizedOwnedRecordPairStreamProducerPlan.analyze` input contract for the isolated emitter.

- [ ] **Step 1: Add the manifest shape and registry row test first.**

  Add a unit test that asserts effect
  `record-resource-pair-parameterized-stream-producer`, the exact package/locator/world/member values, WIT hash, record layout `8/4` with offsets `0/4`, source ABI `(i32)->(i32)`, producer input words `(i32,i32,i32)`, and stream capacity `1`. Run `zig test src/build/p3_async_manifest.zig` and retain the expected failure until the row is wired.

- [ ] **Step 2: Add an isolated manifest type and validator.**

  Define:

  ```zig
  pub const ParameterizedOwnedRecordPairStreamProducerCanonical = struct {
      stream_capacity: u32,
      runtime_mode_param: []const u8,
      left_seed_param: []const u8,
      right_seed_param: []const u8,
      terminal: []const u8,
  };
  ```

  Add the corresponding shape and `LoweringShape` variant. Validate every WIT, canonical operation, layout, resource/drop, parameter, and hash field; return `null` on the first mismatch. Do not reuse the static pair validator or add a generic owned-record predicate.

- [ ] **Step 3: Add target dispatch and exact Do admission.**

  Route only the new descriptor to the new target. The matcher accepts exactly `make_ticket`, `consume`, `Ticket`, `ResourcePair`, `ProducerError`, the three-argument sentinel, and `start`; it rejects old locators, one/two/four arguments, reordered/non-`u32` seeds, renamed bindings, changed body, extra declarations, async intrinsics, borrowed/list/variant/nested fields, and unregistered descriptors with `UnsupportedP3AsyncComponent` before WAT.

- [ ] **Step 4: Add and run focused negatives.**

  Create fixtures for wrong arity, wrong parameter order, non-`u32` seed, old descriptor, renamed binding, third/reversed/scalar/list/borrowed field, wrong binding kind, and async token/intrinsic. Each `.expect` contains `UnsupportedP3AsyncComponent`. Run:

  ```bash
  zig test src/build/p3_async_manifest.zig
  zig test src/build/sema_imports.zig
  zig test src/build/codegen_component_async.zig
  ```

  Expected: new positive resolves only to the parameterized target; static pair tests remain green; every mutation fails before WAT.

### Task 4: Implement the isolated parameterized emitter and Do gates

**Files:**

- Create `src/build/codegen_component_parameterized_owned_record_pair_stream_producer.zig` and `src/build/parameterized_owned_record_pair_stream_producer_template.wat`.
- Create `examples/p3-runtime/g6-2-owned-record-pair-parameterized-producer.do`, `test_do_g6_2_owned_record_pair_parameterized_producer.sh`, and its negative script.
- Modify only target imports/dispatch in `src/build/codegen_component_async.zig`.

**Interfaces:** `ParameterizedOwnedRecordPairStreamProducerPlan.analyze(tokens, registry)` returns an exact plan or `UnsupportedP3ParameterizedOwnedRecordPairStreamProducer`; emitter functions return the pinned WIT/WAT for the new descriptor only.

- [ ] **Step 1: Add the positive Do fixture and a failing route assertion.**

  The fixture uses:

  ```do
  make_ticket = @host_func("do:g6-2-owned-record-pair-parameterized-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
  consume = @host_async_func("do:g6-2-owned-record-pair-parameterized-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourcePair>) -> Result<nil, ProducerError>)
  Ticket = @wasi_resource("do:g6-2-owned-record-pair-parameterized-producer/source/ticket", { .id i64 })
  ResourcePair {
      .left Ticket
      .right Ticket
  }
  ProducerError error = Io | Pipe | InvalidMode
  produce(mode u32, left_seed u32, right_seed u32) -> Result<nil, ProducerError> { return Ok() }
  start() {}
  ```

- [ ] **Step 2: Emit the three input words without changing ownership semantics.**

  The template loads mode/left/right seed locals once, calls `make-ticket` with each seed in order, writes both handles at offsets `0/4`, and clears both guest bits only after a successful complete-record write. It includes explicit right-then-left cleanup for all pre-transfer failures and rejects mode `255` before any allocation.

- [ ] **Step 3: Run the positive and negative Do gates.**

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache" bash examples/p3-runtime/test_do_g6_2_owned_record_pair_parameterized_producer.sh
  bash examples/p3-runtime/test_do_g6_2_owned_record_pair_parameterized_producer_negative.sh
  ```

  Expected: generated WIT is byte-identical to the pinned source/hash, generated WAT contains the three input markers, seed order, layout, mask, and no ARC marker; every negative fails before WAT.

### Task 5: Run lifecycle, equivalence, old-route regression, and full verification

**Files:**

- Create the parameterized Rust/Wasmtime and equivalence shell gates.
- Modify `examples/p3-runtime/README.md`, `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/master_plan.md`, `doc/start_here.md`, and `CHANGELOG.md` only after all behavior gates pass.

**Interfaces:** Produces independently observed generated/canonical lifecycle equivalence and synchronized current-state documentation; no migration row is closed.

- [ ] **Step 1: Execute the parameterized ten-mode lifecycle matrix.**

  Use the exact seed/mode table in the spec. Assert receive order, two ticket creations/drops per valid invocation, four/four for repeat, one stream/task cleanup, `table-empty=true`, zero creation for invalid, and mode-specific poll/cancel/future-drop counters.

- [ ] **Step 2: Compare canonical and generated Components.**

  Assemble both artifacts separately, normalize only component identity fields, and compare every mode's lifecycle output. Do not count this as an ARC/GC semantic-equivalence row.

- [ ] **Step 3: Re-run all closed neighboring gates.**

  Run the static single-field producer and static two-field producer ABI/Do/Rust/equivalence gates. Expected: unchanged WIT hashes, payloads, and cleanup counters.

- [ ] **Step 4: Run repository verification.**

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache" ./src/build/test/run_tests.sh
  (cd src && TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig)
  (cd src && TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig build -Doptimize=ReleaseSmall)
  bash src/build/test/run_release_smoke.sh
  git diff --check
  ```

  Expected: no regression, ReleaseSmall and release smoke pass, and all gates use the pinned current toolchain.

- [ ] **Step 5: Verify inventory and synchronize documentation.**

  Run the inventory checker and assert `complete_rows=15 pending_rows=15` with exit `1`; record the new descriptor/hash/layout/matrix and retain all generic/borrowed/general async/full-GC non-goals. Review `git diff --stat` and the staged path list before committing the new route with:

  ```bash
  git commit -m "feat: add parameterized owned-record pair producer gate"
  ```

  Do not push in this plan unless a separate explicit delivery instruction is given.

## Stop Conditions and Rollback

- If WIT hash, canonical ABI, Component validation, admission, lifecycle, or equivalence fails, stop the new route and keep it unadmitted; record the observed failure without adapting silently.
- If a shared-module change would widen the static route or alter an existing hash, revert only the new-route working changes and leave the committed static baseline untouched.
- If the default `/tmp` quota fails, rerun with the project-local cache paths above; do not weaken the tests.
- Rollback removes only the new parameterized WIT, manifest row, emitter/template, fixtures, runner, and documentation entries; the static pair descriptor remains intact.
