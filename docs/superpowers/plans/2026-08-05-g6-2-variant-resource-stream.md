# G6.2 Variant Resource Stream Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Register and lower the already-proven private `variant-resource-stream` shape without opening public variant or ownership syntax.

**Architecture:** Extend the pinned async manifest with one descriptor-specific variant stream shape, add a dedicated emitter module, and dispatch only an exact source fixture to it. The emitter consumes measured tag/payload/drop facts from the manifest; the existing hand-written canonical WAT/Rust probe remains the ABI oracle.

**Tech Stack:** Zig 0.16.0 compiler, Do fixtures, JSON manifest, WAT templates, `wasm-tools` 1.254.0, Rust/Wasmtime 47.0.2.

## Global Constraints

- Keep the descriptor private: `do:variant-resource-stream-canonical@0.1.0`.
- Admit exactly one stream read, one event, one completion future, and one owned ticket.
- Preserve measured event facts: tag offset 0, payload offset 4, size 8, alignment 4, and tag mapping ticket=0/idle=1/failed=2.
- Invalid tags must trap before ownership transfer; idle/failed branches must not drop a ticket.
- Do not add `own<T>`, `borrow<T>`, `ref<T>`, public variant declarations, arbitrary producer expressions, sixth forwarding, or seventh-level nesting.
- Preserve unrelated dirty worktree changes; do not stage, commit, reset, clean, or push.

### Task 1: Add the Red Source and Compiler Boundary Fixtures

**Files:**
- Create: `examples/p3-runtime/variant-resource-stream.do`
- Create: `examples/p3-runtime/test_do_variant_resource_stream_lowering.sh`
- Create: `src/build/test/compile_ok/414_variant_resource_stream_component.do`
- Create: `src/build/test/compile_err/414_variant_resource_stream_unknown_descriptor.do`
- Create: `src/build/test/compile_err/414_variant_resource_stream_unknown_descriptor.expect`

**Interfaces:**
- Consumes: existing `variant-resource-stream-canonical.wit` and `variant_resource_stream_abi.rs`.
- Produces: a source form that must be rejected before registry admission and a stable positive fixture for the new target.

- [ ] **Step 1: Write the source fixture using ordinary union arms.**

Use the private resource and source union shape:

```do
probe_read = @host_func("do:variant-resource-stream-canonical@0.1.0", "read-via-stream", () -> Tuple<Stream<Ticket | nil | EventError>, Future<Result<nil, EventError>>>)
Ticket = @wasi_resource("do:variant-resource-stream-canonical/source/ticket", { .id i64 })
EventError error = Io

async run() -> Result<nil, EventError> {
    handles Tuple<Stream<Ticket | nil | EventError>, Future<Result<nil, EventError>>> = probe_read()
    reader Stream<Ticket | nil | EventError> = @get(handles, 0)
    completion Future<Result<nil, EventError>> = @get(handles, 1)
    pending Future<Result<Ticket | nil | EventError, nil>> = @next(reader)
    event Result<Ticket | nil | EventError, nil> = await(pending)
    _ = event
    return await(completion)
}
```

The source remains private and uses `Result` only where the async probe needs its internal tag.

- [ ] **Step 2: Add the failing lowering script.**

The script must compile the fixture with `--p3-async-component`, assert the current `UnsupportedP3AsyncComponent` failure, and run the existing `test_variant_resource_stream_abi.sh` as the canonical runtime baseline.

- [ ] **Step 3: Run the red test.**

```bash
bash examples/p3-runtime/test_do_variant_resource_stream_lowering.sh
```

Expected before implementation: source validation recognizes the private signature, but component lowering fails with the explicit unsupported-target error.

### Task 2: Extend the Manifest with a Measured Variant Shape

**Files:**
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/p3_async_manifest.zig`
- Test: `src/build/p3_async_manifest.zig`

**Interfaces:**
- Consumes: the exact imports and markers from `examples/p3-runtime/variant-resource-stream-canonical.wat`.
- Produces: `lowering_shape(descriptor) == .variant_resource_stream_reader` with explicit event layout and cleanup imports.

- [ ] **Step 1: Add the descriptor record.**

Use this registry identity and result shape:

```json
{
  "locator": "do:variant-resource-stream-canonical@0.1.0",
  "member": "read-via-stream",
  "effect": "variant-resource-stream-reader",
  "params": [],
  "result": "tuple<stream<event>,future<result<_,error-code>>>",
  "resource": null,
  "canonical": {
    "core_params": [],
    "core_results": [],
    "completion": "result-area",
    "stream": {
      "element": "event",
      "read": {"core_params": ["i32", "i32", "i32"], "core_results": ["i32"]},
      "drop_readable": {"core_params": ["i32"], "core_results": []}
    },
    "future": {
      "read": {"core_params": ["i32", "i32"], "core_results": ["i32"]},
      "drop_readable": {"core_params": ["i32"], "core_results": []}
    },
    "event_layout": {
      "tag_offset": 0,
      "payload_offset": 4,
      "byte_size": 8,
      "alignment": 4,
      "variants": [
        {"name": "ticket", "tag": 0, "payload": "own<ticket>"},
        {"name": "idle", "tag": 1, "payload": null},
        {"name": "failed", "tag": 2, "payload": "error-code"}
      ]
    }
  }
}
```

Use the exact import names from the canonical WAT; do not derive names from the locator.

- [ ] **Step 2: Add typed manifest structs and validation.**

Add `VariantEventLayout`, `VariantEventBranch`, and `VariantResourceStreamShape` alongside the existing record/list shape types. Reject missing branches, duplicate tags, non-4-byte alignment, wrong offsets, wrong stream/future operation types, or any descriptor with a different locator/member.

- [ ] **Step 3: Add unit tests for positive and drifted descriptors.**

The positive test must assert all three branch names/tags and all five layout facts. The drift tests must reject a changed tag, changed payload offset, changed drop import, and changed WIT result shape.

```bash
cd src && zig test build/p3_async_manifest.zig
```

Expected: all manifest tests pass and drifted descriptors return the existing invalid/unsupported error.

### Task 3: Add Sema Admission and Target Dispatch

**Files:**
- Modify: `src/build/sema_imports.zig`
- Modify: `src/build/codegen_component_async.zig`
- Create/modify: `src/build/test/check/414_variant_resource_stream_component.do`
- Create/modify: `src/build/test/check/415_variant_resource_stream_unknown.do`
- Test: `src/build/test/check/415_variant_resource_stream_unknown.expect`

**Interfaces:**
- Consumes: `.variant_resource_stream_reader` from Task 2.
- Produces: only the exact `@host_func` signature admits the target; unknown locator, wrong union element, wrong completion type, or wrong ownership shape remains rejected.

- [ ] **Step 1: Add the target enum and dispatcher import.**

Add `variant_resource_stream` to `Target`, import `codegen_component_variant_resource_stream.zig`, and route both `emit_component_wat` and `emit_component_wit` through it. Map its emitter error to `UnsupportedP3AsyncComponent`.

- [ ] **Step 2: Add exact signature matching.**

Add `variant_resource_stream_reader_signature_matches` to `sema_imports.zig`. It must require `Tuple<Stream<Ticket | nil | EventError>, Future<Result<nil, EventError>>>` and the exact private resource locator; it must not accept a generic `Stream<T>` union.

- [ ] **Step 3: Add target selection tests.**

```bash
cd src && zig test build/codegen_component_async.zig --test-filter 'variant resource stream'
cd src && zig test build/sema_imports.zig --test-filter 'variant resource stream'
```

Expected: the positive fixture selects `Target.variant_resource_stream`; the unknown and drifted fixtures return the existing explicit unsupported diagnostic.

### Task 4: Implement the Descriptor-Specific Emitter

**Files:**
- Create: `src/build/codegen_component_variant_resource_stream.zig`
- Modify: `src/build/codegen_component_async.zig`
- Test: `src/build/codegen_component_variant_resource_stream.zig`

**Interfaces:**
- Consumes: `VariantResourceStreamShape`, parsed source tokens, and the canonical WAT behavior.
- Produces: `emit_component_wat` and `emit_component_wit` with the private package/world and measured event layout.

- [ ] **Step 1: Define the emitter API.**

Implement:

```zig
pub const VariantResourceStreamPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    event: p3_async_manifest.VariantEventLayout,
    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !VariantResourceStreamPlan;
};

pub fn emit_component_wat(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph) ![]u8;
pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8;
```

- [ ] **Step 2: Emit only the measured branches and cleanup.**

The generated WAT must decode tag 0/1/2, transfer the ticket only for tag 0, call the ticket drop exactly once after frame ownership, and drop stream/future on every terminal path. Tag 3 must `unreachable` before payload load. Do not copy offsets from another emitter; read them from `plan.event`.

- [ ] **Step 3: Add emitter unit tests.**

Assert the generated WAT contains the private source imports, branch markers, `[resource-drop]ticket`, exactly-once cleanup helper, and invalid-tag trap. Assert generated WIT contains the three event branches and no public ownership declarations outside the private world.

```bash
cd src && zig test build/codegen_component_variant_resource_stream.zig
```

### Task 5: Green Do/Component/Rust Gate

**Files:**
- Modify: `examples/p3-runtime/test_do_variant_resource_stream_lowering.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` only if a new binary name is required
- Preserve: `examples/p3-runtime/test_variant_resource_stream_abi.sh`
- Test: generated Component and Rust/Wasmtime matrix

**Interfaces:**
- Consumes: Task 4 generated WAT/WIT and Task 2 manifest.
- Produces: compiler-generated Component evidence equivalent to the canonical probe.

- [ ] **Step 1: Compile and inspect markers.**

```bash
./bin/do build examples/p3-runtime/variant-resource-stream.do \
  --p3-async-component --p3-wit-output "$tmp_dir/variant.wit" \
  -o "$tmp_dir/variant.wat"
grep -Fq '[variant-event-tag-offset] 0' "$tmp_dir/variant.wat"
grep -Fq '[variant-event-payload-offset] 4' "$tmp_dir/variant.wat"
```

- [ ] **Step 2: Assemble and validate the generated Component.**

Run `wasm-tools parse`, `component embed`, `component new`, and `wasm-tools validate --features cm-async,cm-more-async-builtins` using the generated WIT world.

- [ ] **Step 3: Run the Rust matrix.**

Run ticket-ready, idle-ready, failed-ready, ticket-pending, completion-error, early-drop, malformed-tag, and duplicate-release. Require the same event observations, resource counts, table state, and trap behavior as `test_variant_resource_stream_abi.sh`.

- [ ] **Step 4: Run full regression and document the bounded closeout.**

```bash
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
```

Update `doc/pending_blocked.md`, `doc/start_here.md`, `doc/roadmap_status.md`, and `doc/master_plan.md` only after all gates pass. Keep generic variant/list/borrowed shapes pending.
