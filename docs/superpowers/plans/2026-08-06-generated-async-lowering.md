# Generated Async Manifest Lowering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** admit one generated WIT `async func() -> Future<nil>` binding through the existing colorless three-operation Component runtime shape using explicit manifest metadata.

**Architecture:** WIT binding generation emits schema 2 only for the pinned private `component-async-unit-v1` capability. The import graph validates module hashes, WIT identity, signature/effect, and canonical async import metadata, then exposes an immutable manifest descriptor to the existing generic async analyzer. The analyzer and Component emitter reuse the current three-operation runtime template; all other generated async shapes remain rejected.

**Tech Stack:** Zig 0.16.0, Do compiler/import graph, WIT parser/resolver/emitter, `wasm-tools 1.254.0`, Wasmtime 47.0.2, Rust 1.97.1, existing Cargo/Rust host runner.

## Global Constraints

- Keep manifest schema 1 valid for metadata-only generated bindings.
- Emit schema 2 only for the exact private `do:generic-async-runtime-probe@0.1.0` `host.work` unit async capability.
- The only schema 2 capability admitted in this phase is `component-async-unit-v1`.
- The admitted Do body remains the existing three distinct `Future<nil>` operations: `@await`, `@await`, then terminal `@cancel`.
- Generated async bindings already return `Future<T>` and must not be wrapped in `@async`.
- Do not add payload, parameters, Stream, resource, aggregate await, branch/loop await, multi-root scheduling, `own<T>`, `borrow<T>`, or `ref<T>` lowering.
- Do not infer Core async imports or completion semantics from a locator or function name.
- Keep the pinned P3 registry path unchanged for existing WASI/Component descriptors.
- Preserve all existing dirty worktree changes; stage only files belonging to the current task at each commit.
- Every failing shape must be rejected before WAT emission with a named diagnostic.

---

### Task 1: Add the schema 2 lowering model and WIT emitter contract

**Files:**
- Create: `src/wit/async_lowering.zig`
- Modify: `src/wit/model.zig`
- Modify: `src/wit/emit_manifest.zig`
- Modify: `src/wit/manifest.zig`
- Modify: `src/wit/manifest_test.zig`
- Modify: `src/wit/tests.zig`

**Interfaces:**
- `src/wit/async_lowering.zig` exports:

```zig
pub const Capability = struct {
    capability: []const u8,
    member: []const u8,
    source_signature: []const u8,
    wit_package: []const u8,
    wit_world: []const u8,
    wit_interface: []const u8,
    wit_member: []const u8,
    async_import_module: []const u8,
    async_import_name: []const u8,
    completion: []const u8,
    wit_sha256: [32]u8,
};

pub fn detect(allocator: std.mem.Allocator, binding: model.BindingModel) ![]Capability;
pub fn deinit(allocator: std.mem.Allocator, capabilities: []Capability) void;
```

  `detect` returns exactly one capability only for the pinned package/world/interface/member and the unit async shape, and returns an empty slice for every other WIT model.
- `manifest.Parsed` gains `async_lowerings: []const AsyncLowering`; schema 1 parses with an empty slice, schema 2 requires the array, and unknown capability names are rejected.

- [x] **Step 1: Add red tests for schema 2 and capability detection.**

Add these manifest tests with the named assertions shown below:

- `schema 2 accepts the pinned unit async capability`: parsed schema is `2`, one lowering is present, and its capability/import/completion fields equal the pinned values.
- `schema 1 remains metadata-only`: parsed schema is `1` and `async_lowerings.len == 0`.
- `schema 2 rejects an unknown capability`: returns `error.ManifestLoweringMismatch`.
- `schema 2 rejects a changed completion import`: returns `error.ManifestLoweringMismatch`.
- `capability detection rejects payload and non-pinned async models`: returns an empty capability slice for both inputs.

The tests must assert the exact errors `ManifestSchemaUnsupported`,
`ManifestEffectMismatch`, `ManifestSignatureMismatch`, or a new named
`ManifestLoweringMismatch` as appropriate; they must not accept a synchronous
member with an async lowering record.

- [x] **Step 2: Run the red WIT tests.**

Run:

```bash
cd src
zig test wit/manifest_test.zig
zig test wit/tests.zig
```

Expected result: the new tests fail because the schema 2 fields and capability
detector do not exist; existing tests continue to compile and pass.

- [x] **Step 3: Implement the exact capability detector.**

In `async_lowering.zig`, guard in this order:

1. require package `do:generic-async-runtime-probe@0.1.0` and world `probe`;
2. require exactly one imported interface named `host`;
3. require exactly one function named `work`, `is_async == true`, zero params,
   no resource/future/stream effects, and no result type;
4. render source signature `() -> Future<nil>`;
5. fill canonical imports `do:generic-async-runtime-probe/host@0.1.0`,
   `[async-lower]work`, and `task-return`;
6. copy `binding.content_hash` into `wit_sha256`.

Return no capability for all other packages or shapes. Keep the helper pure
apart from allocator ownership and do not inspect generated Do source.

- [x] **Step 4: Implement schema 1/schema 2 parsing and emission.**

`emit_manifest.render_modules_with_hashes` must call `detect`. Emit
`{"schema":2,"async_lowerings":[{"capability":"component-async-unit-v1"}]}`
only when the returned list is
non-empty; otherwise preserve byte-for-byte schema 1 output. Parse and validate
the fields listed in the design spec, require every lowering entry to be unique
and to match exactly one manifest member, and
cross-check the lowering against the manifest member signature/effect and WIT
package/world hash.

- [x] **Step 5: Run focused tests and commit.**

Run:

```bash
cd src
zig test wit/manifest_test.zig
zig test wit/tests.zig
git diff --check
```

Commit only Task 1 files:

```bash
git add src/wit/async_lowering.zig src/wit/model.zig src/wit/emit_manifest.zig \
  src/wit/manifest.zig src/wit/manifest_test.zig src/wit/tests.zig
git commit -m "Add generated async manifest capability"
```

---

### Task 2: Carry validated generated async metadata through the import graph

**Files:**
- Modify: `src/build/module_graph.zig`
- Modify: `src/build/generated_wit_manifest.zig`
- Modify: `src/build/import_resolution.zig`
- Test: `src/build/import_resolution.zig`
- Test: `src/build/generated_wit_manifest.zig` if focused unit tests are added there

**Interfaces:**
- `module_graph.ModuleGraph` gains `generated_async_lowerings: []const GeneratedAsyncLowering` and frees all owned strings in `deinit`.
- `GeneratedAsyncLowering` contains the validated locator/member, source signature, WIT identity, Core async import module/name, completion, and WIT hash; it contains no parsed JSON value or borrowed manifest buffer.
- `generated_wit_manifest.load_and_validate(io, allocator, module_path, tokens) !ValidatedManifest` returns parsed lowerings after validating sibling module hashes and host declarations. The existing `validate` wrapper remains for callers that only need a boolean validation.
- `import_resolution.resolve_imports` appends validated generated lowerings to the graph before codegen starts; schema 1 modules append none.

- [x] **Step 1: Add red graph tests.**

Add a temporary `wit/` module plus schema 2 manifest test that loads through
`check_and_load` and asserts one graph lowering with:

```text
locator = do:generic-async-runtime-probe/host@0.1.0
member = work
async_import_name = [async-lower]work
completion = task-return
```

Add a second test with a changed module hash and assert
`GeneratedWitManifestMismatch` before any lowering is appended.

- [x] **Step 2: Run the red graph tests.**

Run:

```bash
cd src
zig test build/import_resolution.zig
```

Expected result: the positive test fails because `ModuleGraph` has no lowering
collection; the drift test remains rejected.

- [x] **Step 3: Implement ownership-safe manifest loading.**

Refactor `generated_wit_manifest` so JSON parsing, module hash validation, host
signature validation, and lowering validation happen in one function. Duplicate
or unknown lowering entries return `GeneratedWitManifestMismatch`; no partial
entry is appended on an error. `ModuleGraph.deinit` must free every string even
when loading fails halfway through.

- [x] **Step 4: Wire graph collection.**

Change `resolve_imports` to accept `*ModuleGraph`, load each generated module's
validated lowerings, clone their strings into graph-owned storage, and append
them once. Non-generated modules and schema 1 manifests keep the existing path.

- [x] **Step 5: Verify and commit.**

Run:

```bash
cd src
zig test build/import_resolution.zig
zig test build/module_graph.zig
git diff --check
```

Commit only Task 2 files:

```bash
git add src/build/module_graph.zig src/build/generated_wit_manifest.zig \
  src/build/import_resolution.zig
git commit -m "Carry generated async metadata through imports"
```

---

### Task 3: Admit manifest-backed unit async in generic analyzers

**Files:**
- Modify: `src/build/codegen_generic_async_plan.zig`
- Modify: `src/build/codegen_component_async_plan.zig`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Create: `src/build/test/check/430_generated_async_manifest_runtime.do`
- Create: `src/build/test/compile_err/430_generated_async_manifest_payload.do`
- Create: `src/build/test/compile_err/430_generated_async_manifest_payload.expect`
- Create: `src/build/test/compile_err/431_generated_async_manifest_missing_capability.do`
- Create: `src/build/test/compile_err/431_generated_async_manifest_missing_capability.expect`

**Interfaces:**
- `codegen_generic_async_plan.analyze` continues to accept `module_graph: ?*const imports.ModuleGraph` and checks graph lowerings before the pinned registry fallback.
- `codegen_component_async_plan.analyze_generic_async_component` gains the same `module_graph` argument and returns the existing `GenericAsyncComponentPlan` with `source_mode = .descriptor_async` and the validated canonical import strings.
- `target_for_tokens` accepts `module_graph` so a generated binding cannot be admitted using tokens alone.

- [x] **Step 1: Add red analyzer tests and fixtures.**

The positive check fixture must import a generated `work` module and contain
the exact three-operation body:

```do
first Future<nil> = work()
@await(first)
second Future<nil> = work()
@await(second)
third Future<nil> = work()
@cancel(third)
```

The payload and missing-capability fixtures must keep the same locator but use
`Future<u32>` or a schema 1 metadata-only manifest. They must fail with
`AsyncLoweringUnavailable` or the precise named manifest diagnostic before WAT
emission.

- [x] **Step 2: Run the red analyzer tests.**

Run:

```bash
cd src
zig test build/codegen_generic_async_plan.zig
zig test build/codegen_component_async_plan.zig
```

Expected result: the generated positive shape is not admitted, while existing
pinned registry tests remain green.

- [x] **Step 3: Implement manifest host matching.**

Add a manifest host binding parser that matches the generated `@host` locator
and member to exactly one `GeneratedAsyncLowering`. Convert it to the existing
generic plan fields without constructing a fake P3 registry descriptor. Reject
duplicate matches, source signature drift, non-unit results, and any generated
lowering whose capability is not `component-async-unit-v1`.

- [x] **Step 4: Thread `ModuleGraph` into Component target selection.**

Change `target_for_tokens(allocator, tokens)` to
`target_for_tokens(allocator, tokens, module_graph)` and update every internal
test/call site. Pass the graph into
`analyze_generic_async_component`; keep all non-generic target checks and the
pinned registry path unchanged.

- [x] **Step 5: Verify WAT admission and negative boundaries.**

Run:

```bash
cd src
zig test build/codegen_generic_async_plan.zig
zig test build/codegen_component_async_plan.zig
zig test build/codegen_component_async.zig
./build/test/run_tests.sh
```

The positive generated fixture must contain the existing `[async-lower]work`,
`[subtask-cancel]`, `[subtask-drop]`, and `[task-return]` markers. Payload and
missing-capability fixtures must remain rejected before WAT output.

- [x] **Step 6: Commit analyzer integration.**

```bash
git add src/build/codegen_generic_async_plan.zig \
  src/build/codegen_component_async_plan.zig src/build/codegen_component_async.zig \
  src/build/codegen_pipeline.zig src/build/test/check/430_generated_async_manifest_runtime.do \
  src/build/test/compile_err/430_generated_async_manifest_payload.do \
  src/build/test/compile_err/430_generated_async_manifest_payload.expect \
  src/build/test/compile_err/431_generated_async_manifest_missing_capability.do \
  src/build/test/compile_err/431_generated_async_manifest_missing_capability.expect
git commit -m "Admit generated unit async manifests"
```

---

### Task 4: Add the generated binding Component/Rust/Wasmtime gate

**Files:**
- Create: `examples/wit-bindgen-do/generic-async-runtime.wit`
- Create: `examples/wit-bindgen-do/test_generated_async_lowering.sh`
- Create: `examples/wit-bindgen-do/project/generic_async_main.do`
- Modify: `examples/wit-bindgen-do/README.md`
- Modify: `examples/p3-runtime/README.md` only for the new gate reference

**Interfaces:**
- The WIT source is the exact private package/world used by the pinned runtime: `do:generic-async-runtime-probe@0.1.0`, world `probe`, interface `host`, `work: async func()`, and `export run: async func()`.
- The shell gate generates into a temporary project-root `wit/` directory and uses the existing `do-p3-generic-async-runtime-host-runner` binary; it does not check in generated build output.
- The caller imports the generated `work` binding and uses the three-operation source shape from Task 3.

- [x] **Step 1: Add the generated WIT/caller source and shell gate.**

The script must run these commands in order:

```bash
bin/do wit check generic-async-runtime.wit --world probe
bin/do wit bind generic-async-runtime.wit --world probe --out "$tmp/wit"
bin/do wit check generic-async-runtime.wit --world probe \
  --manifest "$tmp/wit/manifest.json"
bin/do build "$tmp/generic_async_main.do" --p3-async-component \
  --p3-wit-output "$tmp/generated.wit" -o "$tmp/runtime.wat"
```

The gate must fail closed if the build command reports
`AsyncLoweringUnavailable`, emits a synchronous fallback, or produces a WIT
sidecar different from the generated source.

- [x] **Step 2: Run the positive gate after Task 3.**

Run:

```bash
bash examples/wit-bindgen-do/test_generated_async_lowering.sh
```

Expected result: WIT generation, schema 2 manifest validation, Core WAT
generation, Component validation, and the three Rust/Wasmtime modes all pass.

- [x] **Step 3: Connect the generated caller to the runtime sidecar.**

After Task 3 turns admission green, extend the script to parse Core WAT,
component-embed the generated WIT, create the Component, validate
`cm-async,cm-more-async-builtins`, and run the existing Rust host in `pending`,
`immediate`, and `cancel` modes. Assert the same exact output markers as
`test_do_generic_async_runtime.sh`.

- [x] **Step 4: Add drift mutations.**

Within temporary files only, mutate one field at a time: module hash, WIT hash,
`source_signature`, `async_import_name`, `completion`, and `capability`. Each
mutation must fail before WAT emission. Keep the existing schema 1 drift tests
unchanged.

- [x] **Step 5: Verify and commit the gate.**

Run:

```bash
bash examples/wit-bindgen-do/test_generated_async_lowering.sh
git diff --check
```

Commit only Task 4 files:

```bash
git add examples/wit-bindgen-do/generic-async-runtime.wit \
  examples/wit-bindgen-do/test_generated_async_lowering.sh \
  examples/wit-bindgen-do/project/generic_async_main.do \
  examples/wit-bindgen-do/README.md examples/p3-runtime/README.md
git commit -m "Gate generated async manifest runtime"
```

---

### Task 5: Close documentation and verification gates

**Files:**
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-06-generated-async-lowering-design.md`

**Interfaces:**
- Documentation records only the verified `component-async-unit-v1` capability.
- Existing generic payload/Stream/resource, G6.2 residual, and `AsyncLoweringUnavailable` boundaries remain explicit.

- [x] **Step 1: Update the status documents from observed results.**

Record the generated binding gate, exact tool versions, manifest schema 2
capability, pending/ready/cancel markers, and every remaining non-goal. Do not
mark unrestricted WIT lowering complete.

- [x] **Step 2: Run the focused and full verification matrix.**

Run:

```bash
cd src
zig test wit/manifest_test.zig
zig test build/import_resolution.zig
zig test build/codegen_generic_async_plan.zig
zig test build/codegen_component_async_plan.zig
cd ..
bash examples/wit-bindgen-do/run_differential.sh
bash examples/wit-bindgen-do/test_manifest_contract.sh
bash examples/wit-bindgen-do/test_generated_async_manifest.sh
bash examples/wit-bindgen-do/test_generated_async_lowering.sh
./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

- [x] **Step 3: Commit the closeout.**

```bash
git add doc/pending_blocked.md doc/roadmap_status.md doc/start_here.md \
  README.md docs/superpowers/specs/2026-08-06-generated-async-lowering-design.md
git commit -m "Close generated async manifest lowering gate"
```

## Dependencies and Review Points

- Task 1 must pass before Task 2 can parse or store schema 2 lowerings.
- Task 2 must pass before Task 3 can inspect generated metadata during codegen.
- Task 3 must pass before Task 4 can pass the positive runtime gate.
- Task 5 is allowed to update status only after the Rust/Wasmtime gate observes
  the real pending/ready/cancel behavior.
- No task changes the public ownership model or the existing P3 descriptor
  registry.
