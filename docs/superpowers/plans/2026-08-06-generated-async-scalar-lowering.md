# Generated Async Scalar Lowering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended; fresh task agent plus review) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admit one generated WIT `completion() -> Future<u32>` binding through a pinned Component async probe with exact pending, ready, cancel, payload, and cleanup evidence.

**Architecture:** Add a new private schema-2 capability instead of widening the existing unit capability. A hand-authored WIT/Core-WAT/Rust probe measures the scalar payload ABI first; the generated manifest then carries the measured facts to a descriptor-specific analyzer and emitter. The public source remains colorless ordinary functions with explicit `@await` and `@cancel`; only one `Future<u32>` await followed by one terminal cancel is admitted.

**Tech Stack:** Zig 0.16.0, Do compiler, WIT manifest generator, WAT, `wasm-tools` 1.254.0, Wasmtime 47.0.2, Rust/Cargo 1.97.1, existing `examples/p3-runtime/rust-host-runner`.

## Global Constraints

- Admit exactly one private capability named `component-async-scalar-u32-v1`.
- Pin the new private package/world, WIT source hash, canonical async import names, completion operation, and measured scalar payload layout.
- The positive Do root is ordinary `run() -> nil` with one generated `Future<u32>` `@await` and one separate generated `Future<u32>` `@cancel`.
- Existing `Future<nil>` unit lowering remains a separate mode and its no-payload task-return contract is unchanged.
- Do not admit generic `Future<T>`, text/list/record/resource payloads, `Stream<T>`, aggregate await, timeout, branch/loop scheduling, multiple roots, or concurrent cancellation.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Do not infer canonical ABI facts from a locator or function name; every accepted fact comes from the validated descriptor.
- Cancellation ends the task and drops the subtask exactly once; it does not roll back external effects.
- Preserve the current public Result policy `T | E`; private tagged WIT/ABI probes remain private.
- Preserve unrelated dirty worktree changes; stage only files belonging to the current task.
- Every task uses test-first red/green verification and ends with a focused command before the next task.

---

### Task 1: Measure the private scalar Component ABI

**Files:**
- Create: `examples/p3-runtime/wit/generic-async-scalar-probe.wit`
- Create: `examples/p3-runtime/generic-async-scalar-probe.core.wat`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/generic_async_scalar_probe.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/test_generic_async_scalar_probe.sh`

**Interfaces:**
- Consumes: Wasmtime 47.0.2 Component async builtins and the existing single-Store runner patterns.
- Produces: package `do:generic-async-scalar-probe@0.1.0`, world `probe`, operation `host.completion`, exact async import/completion names, and payload layout constants for Task 2.

- [x] **Step 1: Add the WIT probe source and exact-shape guard.**

Use this source:

```wit
package do:generic-async-scalar-probe@0.1.0;

interface host {
  completion: func() -> future<u32>;
}

world probe {
  import host;
  export run: async func();
}
```

The shell gate must reject a changed package, world, member, or result type before assembly.

- [x] **Step 2: Write red ABI assertions before the runner.**

Require the exact source import module, `[async-lower]completion`, `[task-return]run`, `[async-lift]run`, and callback symbols. Require structured markers with `mode`, `value`, `polls`, `wakes`, `completions`, `future-drops`, `frame-drops`, and `table-empty`. Before implementation the script must fail at the missing component artifact, never substitute the unit-payload template.

- [x] **Step 3: Implement the three Rust host modes.**

Implement `ready`, `pending`, and `cancel` with one Component and one Wasmtime Store per invocation. `ready` returns `42`; `pending` wakes once then returns `42`; `cancel` stays pending until the guest cancels. Reject duplicate polls after terminal completion, duplicate completion callbacks, drop-before-cancel, and a non-empty resource table.

- [x] **Step 4: Assemble and measure the payload ABI.**

Use `wasm-tools parse`, `component embed`, `component new`, and `wasm-tools validate --features cm-async,cm-more-async-builtins`. Record the observed payload offset, width, alignment, encoding, completion import, and callback words in the script. Fail if the payload is not exactly one scalar `u32` word or the toolchain cannot establish a stable layout.

- [x] **Step 5: Run green probe and commit only Task 1.**

```bash
bash examples/p3-runtime/test_generic_async_scalar_probe.sh
cd src && zig test main.zig
git add examples/p3-runtime/wit/generic-async-scalar-probe.wit examples/p3-runtime/generic-async-scalar-probe.core.wat examples/p3-runtime/rust-host-runner/Cargo.toml examples/p3-runtime/rust-host-runner/src/bin/generic_async_scalar_probe.rs examples/p3-runtime/test_generic_async_scalar_probe.sh
git commit -m "Probe generated async scalar payload ABI"
```

The gate must print exact `value=42` and cleanup markers in all three modes before the commit.

---

### Task 2: Add and validate the schema-2 scalar capability

**Files:**
- Modify: `src/wit/async_lowering.zig`
- Modify: `src/wit/emit_manifest.zig`
- Modify: `src/wit/manifest.zig`
- Modify: `src/wit/manifest_test.zig`
- Modify: `src/build/generated_wit_manifest.zig`
- Modify: `src/build/import_resolution.zig` only where validated metadata is threaded

**Interfaces:**
- Consumes: Task 1 package identity, WIT hash, async import names, completion name, and measured payload facts.
- Produces: `GeneratedAsyncLowering` with scalar metadata and capability `component-async-scalar-u32-v1`.

Use one payload field schema in both WIT and build-side validators. The WIT
capability may carry an optional payload object; the compiler build domain owns
its own copy and does not import `src/wit` implementation types:

```zig
pub const ScalarPayload = struct {
    core_type: []const u8,
    offset: u32,
    byte_size: u32,
    alignment: u32,
    encoding: []const u8,
};
```

`src/build/generated_wit_manifest.zig` exposes the corresponding
`GeneratedScalarPayload` and stores it as `?GeneratedScalarPayload` on
`GeneratedAsyncLowering`; the existing unit capability uses `null`.

- [x] **Step 1: Add failing schema-2 tests.**

Test schema 1 byte compatibility and no scalar capability; schema 2 acceptance;
and rejection of changed capability name, source signature, WIT hash, async
import, completion name, offset, byte size, alignment, or encoding with
`error.ManifestLoweringMismatch`. Build-side generated-module mutations must
return `error.GeneratedWitManifestMismatch`.

- [x] **Step 2: Run red WIT/build tests.**

```bash
cd src
zig test wit/manifest_test.zig
zig test build/generated_wit_manifest.zig
```

Expected: new scalar tests fail because the capability and payload fields are not admitted; existing schema-1 and unit schema-2 tests still pass.

- [x] **Step 3: Implement exact capability detection.**

Match package `do:generic-async-scalar-probe@0.1.0`, world `probe`, one imported interface `host`, one synchronous WIT function `completion`, zero parameters, and exactly `future<u32>` result. Copy `binding.content_hash` and Task 1 payload facts; return no capability for every other model.

- [x] **Step 4: Implement emission and build-side validation.**

Emit schema 2 only for this capability and preserve schema 1 for every other binding. Validate generated member signature `() -> Future<u32>`, WIT hash, async import, completion operation, and exact payload metadata before sema admission.

- [x] **Step 5: Run focused tests and commit Task 2.**

```bash
cd src && zig test wit/manifest_test.zig
cd src && zig test build/generated_wit_manifest.zig
cd src && zig test main.zig
git diff --check
git add src/wit src/build/generated_wit_manifest.zig src/build/import_resolution.zig
git commit -m "Admit generated async scalar manifest capability"
```

---

### Task 3: Add scalar async source admission

**Files:**
- Create: `src/build/codegen_generated_async_scalar_plan.zig`
- Modify: `src/build/codegen_component_async_plan.zig` only for shared dispatch
- Modify: `src/build/codegen_component_async.zig`
- Create: positive and negative fixtures under `src/build/test/check` and `src/build/test/compile_err`

**Interfaces:**
- Consumes: `GeneratedAsyncLowering` from Task 2 and the generated-module lookup in `ModuleGraph`.
- Produces:

```zig
const generated_wit_manifest = @import("generated_wit_manifest.zig");

pub const GeneratedAsyncScalarPlan = struct {
    root_name: []const u8,
    host_locator: []const u8,
    host_member: []const u8,
    async_import_module: []const u8,
    async_import_name: []const u8,
    completion: []const u8,
    payload: generated_wit_manifest.GeneratedScalarPayload,
    await_token_index: usize,
    cancel_token_index: usize,
};
```

- [x] **Step 1: Add positive and negative fixtures.**

The positive fixture imports generated `completion` and contains one `Future<u32> = completion()`, one `u32 = @await(...)`, a second `Future<u32> = completion()`, and `@cancel(...)`. Add negatives for `Future<i64>`, `Future<text>`, a second await, timeout, `async run`, implicit `@async(completion())`, an unregistered locator, and generated resource/Stream members.

- [x] **Step 2: Run red plan/checker tests.**

```bash
cd src && zig test build/codegen_generated_async_scalar_plan.zig
./bin/do check src/build/test/check/430_generated_async_scalar.do
```

Expected: positive admission is unavailable while all negative fixtures retain named unsupported diagnostics.

- [x] **Step 3: Implement guarded scalar analysis.**

Require the validated generated descriptor, ordinary unit-returning root, exactly one await followed by one terminal cancel, and both futures with `u32` payload. Reject every extra operation before WAT emission. Do not accept a hand-written host declaration that copies the locator/signature.

- [x] **Step 4: Route the target without weakening unit lowering.**

Add a `generated_async_scalar` target and select it only when the module graph supplies the scalar capability. Keep the unit target and descriptor-specific WASI branches unchanged; map unsupported shapes to existing explicit diagnostics rather than synchronous WAT.

The generated-module admission accepts the stable generated basename under a
project `./wit/` directory, while retaining the nested compiler-test fixture
path; it does not key admission to a fixture-only directory name.

- [x] **Step 5: Verify and commit Task 3.**

```bash
cd src && zig test build/codegen_generated_async_scalar_plan.zig
cd src && zig test build/codegen_component_async.zig
./src/build/test/run_tests.sh
git diff --check
git add src/build/codegen_generated_async_scalar_plan.zig src/build/codegen_component_async_plan.zig src/build/codegen_component_async.zig src/build/test
git commit -m "Admit generated async scalar source shape"
```

---

### Task 4: Emit the scalar Component state machine

**Files:**
- Create: `src/build/codegen_component_generated_async_scalar.zig`
- Create: `src/build/generated_async_scalar_component_template.wat`
- Create: `src/build/generated_async_scalar_component.wit`
- Modify: `src/build/codegen_component_async.zig`

**Interfaces:**
- Consumes: `GeneratedAsyncScalarPlan`, Task 1 measured template, and source tokens.
- Produces:

```zig
pub fn emit_component_wat(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph) ![]u8;
pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8;
```

- [x] **Step 1: Write structural emitter tests.**

Assert generated WAT contains the descriptor async module/name, measured payload type/offset/width/alignment markers, one payload store and one await payload load, explicit pending/ready/cancel callbacks, `[subtask-drop]`, `[waitable-set-drop]`, and `[task-return]run`. Assert the unit template is not selected.

- [x] **Step 2: Run red emitter tests.**

```bash
cd src && zig test build/codegen_component_generated_async_scalar.zig
```

Expected: failure because no scalar emitter/template exists.

- [x] **Step 3: Implement measured scalar template.**

Copy only Task 1 ABI facts. Add a frame payload field, store the callback `u32` before resuming, load it exactly once for the await expression, and preserve terminal cleanup order. Trap unexpected callback states and keep ready delivery distinct from cancellation.

- [x] **Step 4: Emit private WIT and route the target.**

Render only the pinned package/world and `completion` member. Replace generated module/member values from the validated plan; never derive canonical imports from the source locator. Wire both WAT and WIT emission through the scalar target.

- [x] **Step 5: Parse and verify generated Core WAT.**

```bash
cd src && zig test build/codegen_component_generated_async_scalar.zig
wasm-tools parse /tmp/generated-async-scalar.wat -o /tmp/generated-async-scalar.core.wasm
```

The parser must accept the WAT with `cm-async,cm-more-async-builtins`; malformed payload metadata must fail the tests.

- [x] **Step 6: Commit Task 4.**

```bash
git add src/build/codegen_component_generated_async_scalar.zig src/build/generated_async_scalar_component_template.wat src/build/generated_async_scalar_component.wit src/build/codegen_component_async.zig
git commit -m "Lower generated async scalar Component"
```

---

### Task 5: Add generated Component/Rust/Wasmtime gate

**Files:**
- Reuse: `examples/p3-runtime/wit/generic-async-scalar-probe.wit`
- Create: `examples/wit-bindgen-do/project/scalar_async_main.do`
- Create: `examples/wit-bindgen-do/test_generated_async_scalar_lowering.sh`
- Modify: `examples/wit-bindgen-do/project/wit/README.md`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/generated_async_scalar.rs`

**Interfaces:**
- Consumes: Task 2 metadata, Task 3 admission, and Task 4 emitter.
- Produces: generated Component evidence with payload `42` and exact cleanup.

- [x] **Step 1: Generate binding and caller.**

Run `do wit bind` using the Task 1 pinned WIT source into a temporary project `wit/` directory, assert schema 2 and the scalar capability, and compile the generated caller with `--p3-async-component` and `--p3-wit-output`. The caller must not contain a second hand-written `@host` declaration.

- [x] **Step 2: Add drift mutations.**

Mutate temporary generated module, manifest payload offset, WIT hash, completion import, and source signature. Require every mutation to fail before WAT emission with the named manifest mismatch diagnostic.

- [x] **Step 3: Assemble the generated Component.**

Use `wasm-tools parse`, `component embed`, `component new`, and `wasm-tools validate --features cm-async,cm-more-async-builtins`. Assert generated WIT identity and canonical imports match the pinned probe.

- [x] **Step 4: Run the three-mode matrix.**

Require exact markers:

```text
mode=ready value=42 polls=2 wakes=0 completions=2 future-drops=2 pending-future-drops=0 frame-drops=1 table-empty=true
mode=pending value=42 polls=3 wakes=1 completions=2 future-drops=2 pending-future-drops=0 frame-drops=1 table-empty=true
mode=cancel value=42 polls=3 wakes=0 completions=1 future-drops=2 pending-future-drops=1 frame-drops=1 table-empty=true
```

Reject duplicate completion, duplicate drop, wrong payload value, and a non-empty table.

- [x] **Step 5: Commit the generated runtime gate.**

```bash
bash examples/wit-bindgen-do/test_generated_async_scalar_lowering.sh
git add examples/wit-bindgen-do examples/p3-runtime/rust-host-runner/Cargo.toml examples/p3-runtime/rust-host-runner/src/bin/generated_async_scalar.rs
git commit -m "Gate generated async scalar runtime"
```

---

### Task 6: Preserve boundaries and close the checkpoint

**Files:**
- Create/modify: negative fixtures under `src/build/test/compile_err`
- Modify: `doc/pending_blocked.md`, `doc/start_here.md`, `doc/roadmap_status.md`, `doc/master_plan.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: Tasks 1-5 evidence.
- Produces: a truthful bounded checkpoint; generic payload/resource lowering remains pending.

- [x] **Step 1: Add negative cases to the normal matrix.**

Cover unregistered scalar locators, `Future<i64>`, `Future<text>`, Stream/resource payloads, implicit `@async`, a second await, timeout, and legacy `async` declaration. Each expected diagnostic must be checked before WAT emission.

- [x] **Step 2: Synchronize observed documentation.**

Record package/hash, measured payload layout, exact runtime markers, and remaining non-goals. Do not mark generic `Future<T>` or full generated WIT lowering complete.

- [x] **Step 3: Run complete verification.**

```bash
cd src && zig test main.zig
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

Also rerun Result, G6.2, Task 8, unit async, and generated unit-async gates. Any unrelated failure blocks closeout.

- [x] **Step 4: Commit closeout.**

```bash
git add src/build/test/compile_err doc/pending_blocked.md doc/start_here.md doc/roadmap_status.md doc/master_plan.md CHANGELOG.md
git commit -m "Close generated async scalar lowering checkpoint"
```

## Verification Matrix

The capability is complete only when every task has green evidence. A passing
scalar probe alone does not admit compiler lowering; passing compiler tests alone
does not prove Component payload semantics. An unstable or mismatched payload ABI
leaves the capability unregistered and the existing unsupported diagnostic
unchanged.
