# D2 descriptor.stat Private Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure and, only if the pinned Component ABI and runtime cleanup evidence are green, promote one private bounded async wasi:filesystem/types@0.3.0-rc-2025-09-16/descriptor.stat compiler slice.

**Architecture:** Keep descriptor.stat as a method-specific opt-in target with its own manifest capability, planner, emitter, hand-authored canonical WAT/WIT, and Rust/Wasmtime oracle. The Do surface uses ordinary opaque resource handles, records, option, and nil | Error unions; WIT own<descriptor> and result<descriptor-stat, error-code> remain generated Component metadata and do not become public ownership or Result<T,E> syntax. The probe and compiler gates are ordered so a toolchain or layout rejection stops before registry admission and leaves existing get-type, sync, and get-flags behavior unchanged.

**Tech Stack:** Zig 0.16 compiler and tests, Do fixtures, hand-authored WebAssembly Component async WAT, the latest pinned wasm-tools 1.255.0, Rust 1.97.1, Wasmtime 47.0.2, Bash gates.

## Global Constraints

- Do not add public own<T>, borrow<T>, ref<T>, lifetime, pointer, or reference syntax.
- Do not introduce generic Future<T>/record/option lowering or general filesystem async lowering.
- Use the pinned upstream filesystem source at src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit; record its SHA-256 and keep any mirror hash separate.
- Use @host_async_func for the asynchronous host binding; do not reintroduce legacy async declarations or change existing @host_func semantics.
- Keep the new compiler target opt-in and fail closed for every shape outside the exact direct one-await method-specific contract.
- Support only the latest pinned wasm-tools release; when its ABI changes, adapt the compiler and probes instead of retaining a compatibility path for older releases.
- Cancellation follows WASI/Component semantics: release live async state exactly once and never roll back an external filesystem effect already issued.
- Every admitted positive shape needs a pinned WIT hash, measured canonical layout, ownership/presence matrix, negative fixtures, current Component validation, and Rust/Wasmtime ready/pending/error/cancel cleanup evidence. Wasmtime 47 host future drop is not guest cancellation; the separate early-drop row may only prove whole-Store disposal.
- A failed probe is a documented no-go, not permission to guess an ABI or weaken a registry predicate.
- Run git diff --check before each commit and preserve unrelated worktree changes.

## Dependency Map

~~~mermaid
flowchart TD
    A[Baseline and source pin] --> B[WIT capability probe]
    B -->|green| C[Canonical stat layout]
    B -->|red| Z[Record no-go and stop promotion]
    C --> D[Rust/Wasmtime hand-authored oracle]
    D -->|green| E[Do stat type contract]
    D -->|red| Z
    E --> F[Negative fixture matrix]
    F --> G[Manifest capability]
    G --> H[Private planner and emitter]
    H --> I[CLI and target routing]
    I --> J[Generated Component ABI gate]
    J --> K[Generated Rust/Wasmtime matrix]
    K --> L[Full regression and release smoke]
    L --> M[Status docs, review, commit, push]
~~~

## File Map

Files are created or modified only after the preceding gate authorizes the next boundary.

- Create docs/superpowers/specs/2026-08-10-d2-filesystem-async-stat-design.md for source, ABI, layout, ownership, cancellation, and stop conditions.
- Create examples/p3-runtime/wit/wasi-filesystem-stat.wit, examples/p3-runtime/wit/wasi-filesystem-stat-cancel.wit, and examples/p3-runtime/wit/wasi-clocks-wall-clock.wit as pinned WIT mirrors and the exact wall-clock dependency.
- Create examples/p3-runtime/wasi-filesystem-stat.core.wat, examples/p3-runtime/wasi-filesystem-stat-cancel.core.wat, and examples/p3-runtime/wasi-filesystem-stat-component.do as canonical probe artifacts.
- Create examples/p3-runtime/test_d2_wasi_filesystem_stat_abi.sh, examples/p3-runtime/test_do_wasi_filesystem_stat.sh, and examples/p3-runtime/test_rust_wasi_filesystem_stat.sh as fail-closed gates.
- Create the Rust oracle binary under examples/p3-runtime/rust-host-runner/src/bin/do-p3-wasi-filesystem-stat-host-runner.rs; modify only runner registration and shared counters required by the binary.
- Create src/build/codegen_component_wasi_filesystem_stat.zig and src/build/wasi_filesystem_stat_component_template.wat only after the hand-authored runtime gate is green.
- Modify src/build/p3_async_registry.json, src/build/p3_async_manifest.zig, src/build/codegen_component_async.zig, src/build/codegen_pipeline.zig, and src/build/cli.zig only for the exact private capability and target routing.
- Create positive fixture src/build/test/compile_ok/498_wasi_filesystem_stat_component.do and negative fixtures 499 through 510 with matching .expect files.
- Update doc/host_abi_blockers.md, doc/pending_blocked.md, doc/start_here.md, doc/roadmap_status.md, and doc/master_plan.md only with command-backed results.

## Tasks

### Task 1: Freeze the baseline and source identity

**Files:**
- Verify: doc/start_here.md, doc/roadmap_status.md, doc/pending_blocked.md, doc/host_abi_blockers.md, doc/master_plan.md
- Verify: src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit

**Interfaces:**
- Consumes: clean main checkout and existing bounded D2 gates.
- Produces: reproducible baseline output and the exact upstream descriptor.stat source hash for Task 2.

- [x] **Step 1: Verify checkout and existing status.**

Run:

~~~bash
git status --short --branch
git rev-parse main origin/main
git log -1 --oneline --decorate
~~~

Expected: branch identity is recorded; any pre-existing user changes are preserved and excluded from this plan.

- [x] **Step 2: Verify tool versions and source hash.**

Run:

~~~bash
zig version
wasm-tools --version
rustc --version
wasmtime --version
sha256sum src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit
rg -n -C 4 'descriptor-stat|stat: async func' src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit
~~~

Expected: current wasm-tools is 1.255.0; the source contains stat: async func() -> result<descriptor-stat, error-code>;, and the observed hash is recorded in the design document. Do not substitute a different WASI revision.

- [x] **Step 3: Run the untouched baseline.**

Run:

~~~bash
(cd src && zig test main.zig)
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
~~~

Expected: all existing suites are green with zero failures. If a baseline command fails, stop feature work and record the failure before proceeding.

- [x] **Step 4: Write the initial design record.**

Create docs/superpowers/specs/2026-08-10-d2-filesystem-async-stat-design.md with the pinned versions/hash, exact WIT signature and record fields, positive runtime modes, ownership/presence matrix, and ABI/runtime stop conditions. Do not state that the method is supported yet.

### Task 2: Probe the pinned WIT and capability matrix

**Files:**
- Modify: docs/superpowers/specs/2026-08-10-d2-filesystem-async-stat-design.md
- Create: examples/p3-runtime/wit/wasi-filesystem-stat.wit
- Create: examples/p3-runtime/wit/wasi-filesystem-stat-cancel.wit
- Create: examples/p3-runtime/wit/wasi-clocks-wall-clock.wit
- Create: examples/p3-runtime/test_d2_wasi_filesystem_stat_abi.sh
- Verify: examples/p3-runtime/test_d2_wasi_filesystem_get_type_abi.sh, examples/p3-runtime/test_d2_wasi_filesystem_sync_abi.sh, examples/p3-runtime/test_d2_wasi_filesystem_get_flags_abi.sh

**Interfaces:**
- Consumes: Task 1 source hash and existing filesystem WIT mirror conventions.
- Produces: latest-tool descriptor.stat capability result, with exact stderr retained for any rejection.

- [x] **Step 1: Author the smallest complete WIT world.**

The regular mirror must preserve package wasi:filesystem@0.3.0-rc-2025-09-16, the types interface, the complete ordered error-code enum, descriptor-type, descriptor-stat, descriptor with only stat, and a probe interface with:

~~~wit
run: async func(file: own<descriptor>) -> result<descriptor-stat, error-code>;
~~~

The cancel mirror adds a test-only cancel: async func(); endpoint and no additional filesystem method. Include the wall-clock datetime dependency exactly as required by the pinned source.

- [x] **Step 2: Run latest-tool dummy embedding.**

Run:

~~~bash
WASM_TOOLS_EXPECT_VERSION='wasm-tools 1.255.0 (76e20611d 2026-07-30)' \
  bash examples/p3-runtime/test_d2_wasi_filesystem_stat_abi.sh
~~~

The gate must resolve the current wasm-tools command, compare its version and binary SHA-256 with the pinned 1.255.0 identity, and run component embed -t --dummy-names legacy --async-callback --features cm-async,cm-more-async-builtins for both regular and cancel mirrors. No 1.254.0 compatibility binary is part of this plan.

- [x] **Step 3: Record a hard no-go when embedding rejects.**

If the pinned current tool rejects the WIT, preserve the complete command, tool identity, and stderr in the design and doc/pending_blocked.md, mark the capability blocked, and do not create a registry row, compiler target, Do fixture, or WAT emitter. This is a valid terminal outcome for this plan.

- [x] **Step 4: Lock the accepted import set.**

When the pinned current tool accepts the WIT, assert the generated metadata contains [async-lower][method]descriptor.stat, [resource-drop]descriptor, the run task-return export, and the cancel endpoint's root [subtask-cancel]. Reject extra filesystem members by comparing imported method names against the expected set.

### Task 3: Measure the canonical record and result layout

**Files:**
- Create: examples/p3-runtime/wasi-filesystem-stat.core.wat
- Create: examples/p3-runtime/wasi-filesystem-stat-cancel.core.wat
- Modify: examples/p3-runtime/test_d2_wasi_filesystem_stat_abi.sh
- Modify: docs/superpowers/specs/2026-08-10-d2-filesystem-async-stat-design.md

**Interfaces:**
- Consumes: green WIT capability from Task 2.
- Produces: hand-authored Core WAT templates based on measured metadata, with no guessed offsets.

- [x] **Step 1: Capture dummy metadata before writing WAT.**

For the pinned current tool, save component embed -t output and extract the method Core type, task-return signature, result-area pointer convention, descriptor-stat field offsets/widths, option discriminants, enum tag order, and resource-drop import. Store those values in the design document and assert them in the ABI shell gate.

- [x] **Step 2: Write the regular and cancellation templates.**

The templates must expose only the measured async imports/exports and include stable comments for [stat-call], [stat-ready], [stat-pending], [stat-error], [stat-result-area], [stat-option-presence], [descriptor-drop], and [subtask-cancel] where applicable. The ready path writes a regular-file record; the error path writes no-entry; the pending path waits for one external wake.

- [x] **Step 3: Assemble and validate both templates with the pinned current tool.**

Run:

~~~bash
wasm-tools parse examples/p3-runtime/wasi-filesystem-stat.core.wat -o /tmp/do-stat.current.wasm
wasm-tools validate --features cm-async,cm-more-async-builtins /tmp/do-stat.current.wasm
~~~

Repeat using the cancel template with the pinned current tool, then run component embed, component new --skip-validation, validate, print, and component wit. Expected: all artifacts validate and retain marker order; otherwise return to Task 2 and record no-go rather than changing layout guesses.

- [x] **Step 4: Add hash and marker assertions.**

The ABI gate must assert the upstream hash, regular/cancel mirror hashes, tool hashes, exact import names, exact measured Core signatures, result layout markers, and absence of generic filesystem imports. It must fail if an artifact is missing or if a hash changes without an explicit design update.

### Task 4: Build the hand-authored Rust/Wasmtime oracle

**Files:**
- Create: examples/p3-runtime/rust-host-runner/src/bin/do-p3-wasi-filesystem-stat-host-runner.rs
- Modify: examples/p3-runtime/rust-host-runner/src/main.rs only for shared runner registration if required
- Create/modify: examples/p3-runtime/test_rust_wasi_filesystem_stat.sh
- Modify: docs/superpowers/specs/2026-08-10-d2-filesystem-async-stat-design.md

**Interfaces:**
- Consumes: assembled hand-authored components from Task 3.
- Produces: machine-checkable Rust/Wasmtime evidence for record payload, Result, cancellation, and cleanup.

- [x] **Step 1: Define host record and descriptor state.**

Use a temporary regular file under DO_D2_FILESYSTEM_ROOT; pass an opaque descriptor handle through the Component resource table; return a deterministic record (regular-file, link count 1, known byte size, and explicit Some/None timestamp cases). Never expose a raw pointer or host address to the component.

- [x] **Step 2: Implement runtime modes.**

Implement ready, pending, error, cancel, early-drop, and repeat modes. pending must observe one external wake and one completion. error must return Err(no-entry) without implicit success. cancel must use only the test-only subtask-cancel endpoint. Because Wasmtime 47 does not cancel a lowered guest task when its host call future is dropped, early-drop must dispose the whole Store and report `result=store-discarded`, one pending host-future drop, `descriptor-drops=0`, and `table-empty=not-applicable`. repeat must make two independent ready calls and show independent record/result cleanup.

- [x] **Step 3: Enforce cleanup invariants.**

Print one stable line per mode containing host calls, completion polls, external wakes, completions, future drops, pending-future drops, descriptor drops, decoded record fields, option presence bits, and `table-empty=true` for terminal/cancel/repeat rows. The early-drop line instead records Store disposal and `table-empty=not-applicable`. Assert exactly one descriptor drop for every terminal/cancel owned input, exactly one future drop, no duplicate completion, and an empty `ResourceTable` wherever the Store remains alive.

- [x] **Step 4: Run the oracle gate.**

Run:

~~~bash
bash examples/p3-runtime/test_rust_wasi_filesystem_stat.sh
~~~

Expected: ready, pending, error, cancel, early-drop(Store disposal), and repeat pass for the hand-authored components. Any duplicate/missing terminal cleanup, unstable decoded field, non-empty `ResourceTable` after a live-Store row, or cancellation mismatch is a no-go for compiler promotion. A host future drop must not be reported as guest cancellation.

### Task 5: Freeze the private Do source contract

**Files:**
- Create: examples/p3-runtime/wasi-filesystem-stat-component.do
- Create: src/build/test/compile_ok/498_wasi_filesystem_stat_component.do
- Modify: docs/superpowers/specs/2026-08-10-d2-filesystem-async-stat-design.md

**Interfaces:**
- Consumes: measured record layout and green hand-authored oracle from Tasks 3-4.
- Produces: one exact direct-await Do shape for the subsequent sema/planner code.

- [x] **Step 1: Declare only measured WASI records.**

Use this exact source shape and field order. If the measured WIT layout cannot represent these names and types, record no-go instead of changing the source contract:

~~~do
stat_descriptor = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.stat", (Dir) -> DescriptorStat | StatError)
Datetime = @wasi_record("clocks/wall-clock/datetime", { seconds i64, nanoseconds u32 })
DescriptorStat = @wasi_record("filesystem/types/descriptor-stat", { .type i32, link_count u64, size u64, data_access_timestamp option<Datetime>, data_modification_timestamp option<Datetime>, status_change_timestamp option<Datetime> })
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
StatError error = Io | NoEntry

run(file Dir) -> DescriptorStat | StatError {
    pending Future<DescriptorStat | StatError> = stat_descriptor(file)
    return @await(pending)
}

start() {}
~~~

If measured WIT cannot map this record without widening generic record/option lowering, stop at the private oracle and record that no compiler admission is authorized.

- [x] **Step 2: Validate source before codegen changes.**

Run:

~~~bash
./bin/do check examples/p3-runtime/wasi-filesystem-stat-component.do
./bin/do build examples/p3-runtime/wasi-filesystem-stat-component.do -o /tmp/do-wasi-filesystem-stat-default.wat
~~~

Expected: check succeeds, while the default build fails with the method-specific unsupported-target diagnostic and does not create /tmp/do-wasi-filesystem-stat-default.wat. It must not lower through a generic async path.

### Task 6: Add the complete negative source matrix

**Files:**
- Create: src/build/test/compile_err/499_wasi_filesystem_stat_unregistered.do
- Create: src/build/test/compile_err/500_wasi_filesystem_stat_wrong_version.do
- Create: src/build/test/compile_err/501_wasi_filesystem_stat_wrong_result.do
- Create: src/build/test/compile_err/502_wasi_filesystem_stat_missing_datetime.do
- Create: src/build/test/compile_err/503_wasi_filesystem_stat_wrong_field_type.do
- Create: src/build/test/compile_err/504_wasi_filesystem_stat_borrowed_result.do
- Create: src/build/test/compile_err/505_wasi_filesystem_stat_second_await.do
- Create: src/build/test/compile_err/506_wasi_filesystem_stat_branch.do
- Create: src/build/test/compile_err/507_wasi_filesystem_stat_loop.do
- Create: src/build/test/compile_err/508_wasi_filesystem_stat_extra_host.do
- Create: src/build/test/compile_err/509_wasi_filesystem_stat_wrong_resource.do
- Create: src/build/test/compile_err/510_wasi_filesystem_stat_async_root.do
- Create matching .expect files for 499 through 510.

**Interfaces:**
- Consumes: exact positive source shape from Task 5.
- Produces: fail-closed diagnostics proving this is not general async lowering.

- [x] **Step 1: Write one mutation per fixture.**

Keep the body and declarations identical to the positive fixture except for one named mutation: locator/version drift, result arm drift, missing or reordered record field, option/field type drift, borrow<Dir> result, a second @await, branch/loop/defer, a second host binding, a non-WASI resource, or an async run root. Do not combine mutations in one fixture.

- [x] **Step 2: Capture exact diagnostics.**

Run each fixture through the normal compiler and record the stable error substring (UnsupportedP3WasiFilesystemStatComponent or the established front-end diagnostic) in its .expect. The error must occur before WAT output; no fixture may pass by falling back to a generic emitter.

- [x] **Step 3: Run focused negative tests.**

Run:

~~~bash
./src/build/test/run_tests.sh
~~~

Expected: all twelve negative cases fail for the intended reason and no unrelated diagnostic changes occur; the full harness is used because it is the repository's registered fixture runner and has no supported per-fixture filter.

### Task 7: Add the manifest capability only after gates are green

**Files:**
- Modify: src/build/p3_async_registry.json
- Modify: src/build/p3_async_manifest.zig
- Modify: docs/superpowers/specs/2026-08-10-d2-filesystem-async-stat-design.md

**Interfaces:**
- Consumes: accepted ABI hashes/layout and exact Do source contract from Tasks 2-6.
- Produces: one filesystem_stat lowering shape that rejects nearby members and stale hashes.

- [x] **Step 1: Add the descriptor row with measured values.**

Add exactly one descriptor for locator wasi:filesystem/types@0.3.0-rc-2025-09-16, member descriptor.stat, canonical import name [async-lower][method]descriptor.stat, measured Core/task-return signatures, exact WIT package/operation, record field metadata, option/presence metadata, descriptor drop, and upstream/mirror/tool hashes. Do not copy a neighboring row and edit only its member name.

- [x] **Step 2: Add strict manifest validation.**

Add a dedicated predicate and LoweringShape.filesystem_stat branch. Validate locator, member, canonical import, package, operation, result spelling, record field order/types, option arms, and hashes. Return InvalidP3AsyncManifest or the existing method-specific error on mismatch.

- [x] **Step 3: Extend manifest tests.**

Add unit cases for the exact row, wrong member, wrong record field, stale mirror hash, and descriptor.stat-at. Run:

~~~bash
(cd src && zig test build/p3_async_manifest.zig)
~~~

Expected: the exact row is accepted and every mutation is rejected.

### Task 8: Implement the private stat planner

**Files:**
- Create: src/build/codegen_component_wasi_filesystem_stat.zig
- Modify: src/build/codegen_component_async.zig only for exact stat predicate/routing
- Create/modify: src/build/test/compile_ok/498_wasi_filesystem_stat_component.do

**Interfaces:**
- Consumes: p3_async_manifest.Descriptor with lowering_shape == .filesystem_stat.
- Produces: StatPlan.analyze(tokens, registry) and emit_component_wat/emit_component_wit for one non-async root, one Future<DescriptorStat | StatError>, one direct host call, and one @await.

- [x] **Step 1: Write planner tests first.**

Assert that the positive fixture admits exactly one host binding, one Dir resource declaration, one DescriptorStat/Datetime record declaration, two function definitions (run and start), and the exact direct-await token sequence.

- [x] **Step 2: Implement guarded source analysis.**

Mirror GetFlagsPlan/SyncPlan. Reject extra host bindings, wrong @host_async_func marker, wrong locator/member, Result<T,E> source spelling, a second await, async run, arbitrary calls, branches, loops, defer, borrowed fields, and resource types other than the exact Dir declaration.

- [x] **Step 3: Emit only the checked-in template.**

Load wasi_filesystem_stat_component_template.wat after rechecking the canonical import name and measured result contract. emit_component_wit must return the pinned package with descriptor-stat, stat, and run; it must not synthesize a generic WIT schema from arbitrary Do declarations.

- [x] **Step 4: Verify planner tests.**

Run cd src && zig test main.zig after focused module tests. Expected: new tests pass and existing async target dispatch tests remain green.

### Task 9: Add canonical stat WAT/WIT emit artifacts

**Files:**
- Create: src/build/wasi_filesystem_stat_component_template.wat
- Modify: src/build/codegen_component_async.zig
- Modify: src/build/codegen_pipeline.zig if the target requires an emitter entry

**Interfaces:**
- Consumes: StatPlan from Task 8 and hand-authored layout from Task 3.
- Produces: deterministic WAT/WIT output with a stable marker/hash contract.

- [x] **Step 1: Copy only the measured async skeleton.**

Keep exact async imports, task-return/callback exports, record result-area writes, option discriminants, and descriptor drop path measured in Task 3. Include markers [stat-call], [stat-ready], [stat-pending], [stat-error], [stat-result-area], [stat-option-presence], and [descriptor-drop] in that order.

- [x] **Step 2: Add output drift assertions.**

Assert emitted WAT contains measured import names and marker order, result-area size/offset comments, and no future<borrow, stream<, or unregistered filesystem method. Assert emitted WIT hash against the generated compiler hash recorded in the design; keep the hand-authored mirror hash as a separate source identity.

- [x] **Step 3: Compile the positive fixture through the opt-in target.**

Run the target with WAT and WIT outputs, then compare artifacts with the hand-authored package and marker expectations. Expected: output is byte-stable for the same compiler build and differs only where generated names are explicitly permitted.

### Task 10: Wire the opt-in CLI target and registry dispatch

**Files:**
- Modify: src/build/cli.zig
- Modify: src/build/codegen_pipeline.zig
- Modify: src/build/codegen_component_async.zig
- Modify: src/main.zig only if command help/dispatch requires it
- Verify: README.md and src/build/test/README.md only if the command surface is documented there

**Interfaces:**
- Consumes: filesystem_stat lowering and emitter from Tasks 7-9.
- Produces: one opt-in flag, --p3-wasi-filesystem-stat-component, mutually exclusive with other special targets and accepted by existing WIT output options.

- [x] **Step 1: Add CLI parse and exclusivity tests.**

Add the boolean field, parser branch, special-target count, output-path eligibility, and unit tests. Selecting the new target with another P3 target must return UnexpectedCliArg.

- [x] **Step 2: Add target dispatch.**

Add wasi_filesystem_stat to the async target enum, source-shape detection, WAT emission, and WIT emission. The default compiler path must continue returning AsyncLoweringUnavailable for the positive fixture when the flag is absent.

- [x] **Step 3: Run CLI and focused compiler checks.**

Run:

~~~bash
./bin/do check examples/p3-runtime/wasi-filesystem-stat-component.do
./bin/do build examples/p3-runtime/wasi-filesystem-stat-component.do -o /tmp/do-wasi-filesystem-stat-default.wat
./bin/do build --p3-wasi-filesystem-stat-component examples/p3-runtime/wasi-filesystem-stat-component.do -o /tmp/do-wasi-filesystem-stat.wat
./bin/do build --p3-wasi-filesystem-stat-component examples/p3-runtime/wasi-filesystem-stat-component.do --p3-wit-output /tmp/do-wasi-filesystem-stat.wit -o /tmp/do-wasi-filesystem-stat-wat.wat
./src/build/test/run_tests.sh
~~~

Expected: check succeeds; the default build fails before creating WAT; the opt-in builds produce WAT/WIT; and all twelve negative fixtures fail before WAT.

### Task 11: Assemble and validate the generated Component on both toolchains

**Files:**
- Verify: examples/p3-runtime/test_d2_wasi_filesystem_stat_abi.sh
- Create: examples/p3-runtime/test_do_wasi_filesystem_stat.sh
- Verify: generated WAT/WIT and src/build/p3_async_registry.json

**Interfaces:**
- Consumes: opt-in compiler target from Tasks 9-10.
- Produces: latest-tool generated Component validation and WIT/hash/marker evidence.

- [x] **Step 1: Add generated artifact assembly.**

For the pinned current tool, parse generated Core WAT, embed generated WIT with --features cm-async,cm-more-async-builtins, create the regular Component with --skip-validation, validate, print, and extract Component WIT. The ABI gate continues to run the same sequence for the hand-authored cancel component because the admitted Do source has no cancel export.

- [x] **Step 2: Compare generated and canonical metadata.**

Require exact [async-lower][method]descriptor.stat, [resource-drop]descriptor, task-return, result record, enum, and option metadata. Compare upstream and generated mirror hashes and fail on marker reordering or extra imports.

- [x] **Step 3: Add the Do gate.**

test_do_wasi_filesystem_stat.sh must compile fixture 498 with --p3-wasi-filesystem-stat-component, inspect WAT/WIT output, verify default rejection, and verify all twelve negative fixture failures. Missing artifacts or a skipped command are failures.

### Task 12: Run the generated Rust/Wasmtime cleanup matrix

**Files:**
- Modify: examples/p3-runtime/test_rust_wasi_filesystem_stat.sh
- Verify: examples/p3-runtime/rust-host-runner/src/bin/do-p3-wasi-filesystem-stat-host-runner.rs
- Modify: docs/superpowers/specs/2026-08-10-d2-filesystem-async-stat-design.md

**Interfaces:**
- Consumes: generated regular/cancel Components from Task 11.
- Produces: evidence that compiler-generated and hand-authored paths have identical observable ABI and cleanup behavior.

- [x] **Step 1: Run generated modes.**

Run ready, pending, error, and repeat for the generated regular Component, and cancel plus early-drop for the hand-authored cancel-world oracle. Require the same record fields, option presence bits, completion counts, drop counts, and `table-empty=true` for terminal/cancel/repeat rows as the hand-authored oracle; the early-drop row is only Store disposal with `table-empty=not-applicable` until Wasmtime exposes per-task host-call cancellation.

- [x] **Step 2: Check cancellation semantics explicitly.**

Verify cancellation after the host stat call does not fabricate an error or undo the filesystem observation; it only drops the pending Component future/task and owned descriptor once. Verify cancel-before-transfer and cancel-after-terminal paths separately where the Component API permits them.

- [x] **Step 3: Preserve a machine-readable matrix.**

Record exact output lines and tool versions in the design document. A missing row, duplicate completion, non-empty ResourceTable, or generated/canonical layout mismatch is a P0 for promotion and blocks closeout.

### Task 13: Expand rejection and regression gates

**Files:**
- Modify: src/build/test/run_tests.sh only if new fixtures require explicit registration
- Modify: src/build/codegen_component_async.zig, src/build/p3_async_manifest.zig, and focused test files for regression assertions
- Verify: all existing D2, G6.2, async, and borrow gates

**Interfaces:**
- Consumes: all new fixtures and generated runtime gates.
- Produces: repo-wide evidence that the private promotion did not widen unrelated lowering.

- [x] **Step 1: Run focused gates in dependency order.**

~~~bash
(cd src && zig test build/p3_async_manifest.zig)
(cd src && zig test main.zig)
bash examples/p3-runtime/test_d2_wasi_filesystem_stat_abi.sh
bash examples/p3-runtime/test_do_wasi_filesystem_stat.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_stat.sh
~~~

- [x] **Step 2: Re-run neighboring boundaries.**

Run:

~~~bash
bash examples/p3-runtime/test_d2_wasi_filesystem_get_type_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_get_type.sh
bash examples/p3-runtime/test_d2_wasi_filesystem_sync_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_sync.sh
bash examples/p3-runtime/test_d2_wasi_filesystem_get_flags_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_get_flags.sh
bash examples/p3-runtime/test_borrow_capability_matrix.sh
bash examples/p3-runtime/test_future_owned_canonical_abi.sh
bash examples/p3-runtime/test_do_async_call_component.sh
bash examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh
~~~

Expected: no output or capability drift in neighboring methods.

- [x] **Step 3: Run full suites.**

~~~bash
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
~~~

Expected: zero failures; retain and diagnose any failure before claiming completion.

### Task 14: Close documentation, review, and delivery

**Files:**
- Modify: doc/host_abi_blockers.md
- Modify: doc/pending_blocked.md
- Modify: doc/start_here.md
- Modify: doc/roadmap_status.md
- Modify: doc/master_plan.md
- Modify: CHANGELOG.md only if the repository release convention requires a user-visible capability entry

**Interfaces:**
- Consumes: command output and hashes from Tasks 1-13.
- Produces: truthful current status and recoverable git delivery.

- [x] **Step 1: Record the outcome, including no-go branches.**

If all gates are green, mark only the private descriptor.stat slice complete and list its exact CLI target, fixture IDs, hashes, layout, and cleanup matrix. Keep general filesystem async, external HTTP, public ownership syntax, arbitrary payload lowering, and borrowed futures/streams pending. If any probe stopped the chain, record the failure, tool version/hash, impact, and recovery condition instead of marking promotion complete.

- [x] **Step 2: Check documentation consistency.**

Search for all descriptor.stat, filesystem_stat, and new CLI flag references. Ensure start_here, roadmap_status, and master_plan agree and do not call a method-specific slice general filesystem async.

- [x] **Step 3: Review and commit in bounded units.**

Run:

~~~bash
git diff --stat
git diff --check
git status --short
~~~

Commit probe artifacts, compiler promotion, and status documentation as separate concise commits when each unit is green. Do not stage unrelated changes.

- [x] **Step 4: Push only after local delivery is green.**

Fetch and compare origin/main; if remote advanced, rebase the bounded commits and rerun full verification. Push to main only after local and remote ancestry are understood.

## Acceptance Checklist

- [x] Baseline is green and recorded.
- [x] The latest pinned tool accepts the exact WIT, or a complete no-go is recorded before promotion.
- [x] Canonical record/result/option layout is measured and hash-locked.
- [x] Hand-authored Rust/Wasmtime ready/pending/error/cancel/early-drop(Store disposal)/repeat matrix is green; the early-drop row is explicitly not a Component resource-cleanup proof.
- [x] Do source remains ordinary records, options, unions, and opaque handles; no public ownership/reference syntax was added.
- [x] Manifest predicate, planner, emitter, and CLI flag admit only the exact private shape.
- [x] Positive fixture 498 and negative fixtures 499-510 are covered before WAT emission.
- [x] Generated Components match canonical metadata and validate with the latest pinned tool.
- [x] Generated Rust/Wasmtime behavior matches hand-authored oracle with exactly-once cleanup.
- [x] Full compiler, WASM, ReleaseSmall, documentation, diff, and delivery checks are green.
