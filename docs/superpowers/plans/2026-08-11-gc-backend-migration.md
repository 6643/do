# GC Backend Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the temporary ARC implementation with one default Wasm GC backend while preserving the current Do source contract and WIT resource lifecycle contract.

**Architecture:** The migration is deliberately layered. Pure value-representation, layout, root, ABI, and resource facts come first; GC WAT emission consumes only those facts. The current `--gc-core` profiles are migration oracles while the normal backend remains ARC, then are absorbed and removed in the final default switch. Component/WIT ABI values are marshaled at the boundary, while resource ownership and terminal cleanup remain separate plans.

**Tech Stack:** Zig 0.16 toolchain, Core Wasm GC WAT, current `wasm-tools`, Wasmtime GC execution probes, existing `do` compiler regression suite, existing Rust/Wasmtime Component probes.

## Global Constraints

- Preserve public Do value semantics: source remains pointer-free and reference-free; do not add `own<T>`, `borrow<T>`, `ref<T>`, `Result<T, E>`, or `Option<T>`.
- Preserve read-only internal sharing and immutable update semantics: a changed text, list, struct, or Tuple value must preserve the earlier logical value.
- GC traces only Do-managed allocations. It must never implicitly drop, close, cancel, or otherwise finalize a Component/WIT resource.
- Treat WIT `own`/`borrow`, resource drops, cancellation, and terminal cleanup as explicit ABI/resource-plan facts, not GC reachability.
- Do not expand general async lowering, arbitrary producer admission, filesystem async, HTTP, or WIT shape admission during G0-G5.
- Do not introduce an ARC/GC public backend selector. The existing `--gc-core` flag is a temporary restricted oracle and is removed in G5.
- Keep new compiler modules flat under `src/build/`; leaf modules must not import `codegen_pipeline.zig`.
- Preserve existing user changes in `doc/start_here.md` and `union.md`.
- Use `./src/build/test/run_tests.sh` as the full regression gate. Record tool or host-runtime availability failures rather than masking them.

## File Map

| File | Responsibility after migration |
| --- | --- |
| `src/build/codegen_gc_representation.zig` | Pure source-type to inline, GC-managed, or opaque-resource classification. |
| `src/build/codegen_gc_layout.zig` | Pure GC struct and array layout facts, field representation, and validation. |
| `src/build/codegen_gc_roots.zig` | Pure root/liveness plans for synchronous and suspendable code. |
| `src/build/codegen_gc_emit.zig` | Small GC WAT fragments for references, allocation, field access, and immutable rebuild. |
| `src/build/runtime_gc_wat.zig` | Typed GC runtime type declarations and allocation primitives. |
| `src/build/runtime_gc_prelude_wat.zig` | GC runtime prelude assembly. |
| `src/build/runtime_canonical_memory_wat.zig` | Linear-memory data and canonical ABI buffer emission only. |
| `src/build/codegen_component_abi_plan.zig` | Immutable canonical lift/lower plan derived from validated binding facts. |
| `src/build/codegen_component_resource_plan.zig` | Immutable resource transfer, terminal cleanup, and cancellation plan. |
| `src/build/codegen_control_flow.zig` | Pure reachability and loop-control helpers currently co-located with ARC release code. |
| `src/build/codegen_gc_core.zig` | Temporary adapter during G0-G4; removed after its fixtures exercise shared GC lowering. |

## Phase Gates

| Phase | Admission condition | Exit evidence |
| --- | --- | --- |
| G0 | Current default behavior is measured before output changes. | Full regression plus all eight restricted Core GC probes pass. |
| G1 | Pure facts reject impossible representations before any WAT is emitted. | Zig unit tests for representation, layout, roots, ABI, and resources pass. |
| G2 | Text/list/struct/Tuple immutable values use typed GC WAT through shared emitters. | Core WAT validates and Wasmtime proves read sharing plus old-value preservation. |
| G3 | Normal synchronous lowering has GC typed locals and no ARC release work. | Default-independent GC backend tests cover local overwrite, branch, loop, defer, return, and calls. |
| G4 | Suspended values and Component boundaries use separate root, ABI, and resource plans. | Current bounded async/resource ready, error, cancel, and early-drop matrices pass. |
| G5 | Every admitted path reaches the GC backend. | Full regression, Component validation, Rust/Wasmtime matrix, and residual scans pass. |

### Task 1: G0 Baseline and Oracle Harness

**Files:**
- Create: `src/build/test/check_gc_core_oracles.sh`
- Modify: `src/build/test/run_tests.sh`
- Modify: `examples/gc-p3-runtime/README.md`
- Test: all eight existing `examples/gc-p3-runtime/test_do_gc_*.sh` scripts

**Consumes:** Existing `--gc-core` parsing in `src/build/cli.zig`, the eight source fixtures, and their Wasmtime assertions.

**Produces:** An opt-in, deterministic G0 harness. `RUN_GC_CORE=1` runs the restricted oracle suite after the normal regression build; without that variable the standard test suite keeps its current host-dependency behavior.

- [x] **Step 1: Add the failing oracle-harness assertion.**

Add `check_gc_core_oracles.sh` with the fixed ordered fixture list and a guard for `WASMTIME_BIN`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${WASMTIME_BIN:?RUN_GC_CORE=1 requires WASMTIME_BIN}"
for probe in text_identity text_identity_renamed list_set parameterized_list_set parameterized_list_set_renamed managed_struct_set managed_struct_renamed managed_struct_preserve_field; do
    WASMTIME_BIN="$WASMTIME_BIN" bash "$ROOT/examples/gc-p3-runtime/test_do_gc_${probe}.sh"
done
```

- [x] **Step 2: Verify the standalone oracle before wiring it into the regression runner.**

Run: `RUN_GC_CORE=1 WASMTIME_BIN="$(command -v wasmtime)" bash src/build/test/check_gc_core_oracles.sh`

Expected: The command succeeds only when each existing probe returns `27815`; a missing Wasmtime executable is reported as an environment failure.

- [x] **Step 3: Wire the optional gate and document its exact scope.**

Add this guarded call near the existing optional WASM gates in `run_tests.sh`:

```bash
if [[ "${RUN_GC_CORE:-0}" == "1" ]]; then
    WASMTIME_BIN="${WASMTIME_BIN:-$(command -v wasmtime)}" "$TEST_DIR/check_gc_core_oracles.sh"
fi
```

Update the README to state that the suite is a G0 oracle, not a supported alternate compiler backend, and that no new profile-specific source shape may be added.

- [x] **Step 4: Run the G0 baseline.**

Run: `./src/build/test/run_tests.sh`

Run: `RUN_GC_CORE=1 WASMTIME_BIN="$(command -v wasmtime)" ./src/build/test/run_tests.sh`

Expected: Normal regression is unchanged. The opt-in run reports all eight GC probes as passing, or retains the host-tool failure as a G0 environment gap.

- [x] **Step 5: Commit the isolated baseline.**

```bash
git add src/build/test/check_gc_core_oracles.sh src/build/test/run_tests.sh examples/gc-p3-runtime/README.md
git commit -m "Add GC core migration baseline"
```

### Task 2: G1 Representation and Layout Facts

**Files:**
- Create: `src/build/codegen_gc_representation.zig`
- Create: `src/build/codegen_gc_layout.zig`
- Modify: `src/main.zig`
- Test: unit tests colocated in both new modules

**Consumes:** Type spelling helpers from `src/build/type_name.zig`; parser/model adapters are added only by later pipeline tasks.

**Produces:** Pure, allocator-owned facts that classify text/list/managed structs without emitting WAT or importing a WAT emitter.

- [x] **Step 1: Write representation and layout rejection tests.**

Cover scalar `i32` as inline, `text` and `[u8]` as `gc_managed`, a struct containing `[u8]` as `gc_managed`, an explicitly supplied resource name as `resource_handle`, and rejection of a resource nested in a GC-managed struct.

```zig
try std.testing.expectEqual(ValueRep.gc_managed, try classify_type("text", &.{}, &.{}));
try std.testing.expectError(error.ResourceInManagedAggregate, collect_struct_layout(allocator, resource_field_struct, &.{"File"}));
```

- [x] **Step 2: Run the focused tests to establish the missing-module failure.**

Run: `cd src && zig test build/codegen_gc_representation.zig`

Expected: Fail because the module does not yet exist.

- [x] **Step 3: Implement the facts with one-way dependencies.**

Define these public interfaces:

```zig
pub const ValueRep = enum { inline_value, gc_managed, resource_handle };
pub const StructFieldShape = struct { name: []const u8, ty: []const u8 };
pub const StructShape = struct { name: []const u8, fields: []const StructFieldShape };
pub const ClassifyError = error{ UnknownType, ResourceInManagedAggregate, UnsupportedGcAggregate };
pub fn classify_type(ty: []const u8, structs: []const StructShape, resources: []const []const u8) ClassifyError!ValueRep;

pub const GcFieldLayout = struct { name: []const u8, rep: ValueRep, field_index: u32 };
pub const GcStructLayout = struct { name: []const u8, fields: []const GcFieldLayout };
pub fn collect_struct_layout(allocator: std.mem.Allocator, shape: StructShape, structs: []const StructShape, resources: []const []const u8) !GcStructLayout;
pub fn deinit_struct_layout(allocator: std.mem.Allocator, layout: GcStructLayout) void;
```

Classifiers must return an error before constructing partial layout output. Layout must never contain `resource_handle` below a managed object.

- [x] **Step 4: Run focused and aggregate compiler tests.**

Run: `cd src && zig test build/codegen_gc_representation.zig`

Run: `cd src && zig test build/codegen_gc_layout.zig`

Run: `cd src && zig test main.zig`

Expected: All unit tests pass; default WAT remains byte-for-byte unchanged for existing regression fixtures.

- [x] **Step 5: Commit the pure representation layer.**

```bash
git add src/build/codegen_gc_representation.zig src/build/codegen_gc_layout.zig src/main.zig
git commit -m "Add pure GC representation facts"
```

### Task 3: G1 Root, ABI, and Resource Facts

**Files:**
- Create: `src/build/codegen_gc_roots.zig`
- Create: `src/build/codegen_component_abi_plan.zig`
- Create: `src/build/codegen_component_resource_plan.zig`
- Modify: `src/main.zig`
- Test: unit tests colocated in each new module

**Consumes:** `ValueRep` from Task 2 and validated manifest member facts from `src/wit/manifest.zig`.

**Produces:** Three immutable plans. A root plan only records Do GC references; an ABI plan only records canonical conversion; a resource plan only records own/borrow authority and terminal cleanup.

- [x] **Step 1: Add negative unit tests before plan implementation.**

Test that a scalar local gets no GC root slot, a text local does, a `resource_handle` is rejected as a GC root, a resource plan cannot omit terminal cleanup authority, and a canonical ABI plan cannot contain a GC reference crossing its boundary.

```zig
try std.testing.expectError(error.ResourceCannotBeGcRoot, build_root_plan(allocator, &.{ .{ .name = "file", .rep = .resource_handle } }, .synchronous));
try std.testing.expectError(error.GcReferenceCannotCrossCanonicalAbi, validate_abi_plan(.{ .contains_gc_reference = true }));
```

- [x] **Step 2: Run the missing-module tests.**

Run: `cd src && zig test build/codegen_gc_roots.zig`

Expected: Fail because the module does not yet exist.

- [x] **Step 3: Implement the exact plan boundaries.**

```zig
pub const RootPoint = enum { local_bind, overwrite, branch_join, loop_join, return_value, suspend_frame, resume_frame, cancel_frame, terminal };
pub const RootMode = enum { synchronous, suspendable };
pub const RootLocal = struct { name: []const u8, rep: ValueRep };
pub const RootSlot = struct { name: []const u8, point: RootPoint };
pub const RootPlan = struct { slots: []const RootSlot };
pub fn build_root_plan(allocator: std.mem.Allocator, locals: []const RootLocal, mode: RootMode) !RootPlan;

pub const SlotDirection = enum { lift, lower };
pub const CanonicalSlot = struct { source_type: []const u8, canonical_type: []const u8, direction: SlotDirection, contains_gc_reference: bool = false };
pub const AbiMemberShape = struct { package: []const u8, world: []const u8, member: []const u8, arguments: []const CanonicalSlot, results: []const CanonicalSlot };
pub const AbiPlan = struct { package: []const u8, world: []const u8, member: []const u8, arguments: []const CanonicalSlot, results: []const CanonicalSlot };
pub fn build_abi_plan(allocator: std.mem.Allocator, shape: AbiMemberShape) !AbiPlan;
pub fn validate_abi_plan(plan: AbiPlan) !void;

pub const TransferDirection = enum { own_in, own_out, borrow_in };
pub const ResourceTransfer = struct { type_name: []const u8, direction: TransferDirection, drop_authority: bool };
pub const TerminalAction = enum { no_resource, drop_owned, retain_for_host };
pub const ResourceFacts = struct { transfers: []const ResourceTransfer, terminal_actions: []const TerminalAction };
pub const ResourcePlan = struct { transfers: []const ResourceTransfer, terminal_action: TerminalAction };
pub fn build_resource_plan(allocator: std.mem.Allocator, facts: ResourceFacts) !ResourcePlan;
```

`build_root_plan` accepts only `.gc_managed` values. `build_abi_plan` models copied or marshaled canonical slots, never a `(ref null ...)` slot. `build_resource_plan` requires exactly one terminal action and does not call the GC-root API.

- [x] **Step 4: Run focused plan tests and the compiler aggregate test.**

Run: `cd src && zig test build/codegen_gc_roots.zig`

Run: `cd src && zig test build/codegen_component_abi_plan.zig`

Run: `cd src && zig test build/codegen_component_resource_plan.zig`

Run: `cd src && zig test main.zig`

Expected: Plan tests prove separation and rejection behavior; no CLI or generated WAT changes occur.

- [x] **Step 5: Commit the fact layer.**

```bash
git add src/build/codegen_gc_roots.zig src/build/codegen_component_abi_plan.zig src/build/codegen_component_resource_plan.zig src/main.zig
git commit -m "Add GC root and component plans"
```

### Task 4: G2 Shared GC Runtime for Text and Lists

**Files:**
- Create: `src/build/runtime_gc_wat.zig`
- Create: `src/build/runtime_gc_prelude_wat.zig`
- Create: `src/build/codegen_gc_emit.zig`
- Modify: `src/build/codegen_gc_core.zig`
- Modify: `src/main.zig`
- Test: unit tests in the new modules and current text/list oracle fixtures

**Consumes:** Tasks 2-3 facts and existing `text-identity*.do`, `list-set.do`, and `parameterized-list-set*.do` fixtures.

**Produces:** Shared typed-GC WAT definitions for `text` and byte arrays. `codegen_gc_core.zig` becomes a fixture adapter that builds shared plans and emits through the shared runtime rather than selecting literal complete modules.

- [x] **Step 1: Add output tests that fail against the profile templates.**

Assert that the shared emitter produces a `$do_bytes` array, `$do_text` struct, `array.copy` for immutable list update, and no `__arc_` symbol. Assert a read-only text pass emits only a typed reference transfer, not byte-copy instructions.

```zig
try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_bytes (array (mut i8)))") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_bytes $do_bytes") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
```

- [x] **Step 2: Run the focused tests to observe missing shared emitters.**

Run: `cd src && zig test build/codegen_gc_emit.zig`

Expected: Fail before the runtime and emitter exist.

- [x] **Step 3: Move text/list WAT construction behind shared plans.**

Implement these boundary functions:

```zig
pub fn emit_type_declarations(allocator: std.mem.Allocator, out: *std.ArrayList(u8), layouts: []const gc_layout.GcStructLayout) !void;
pub fn emit_text_identity(allocator: std.mem.Allocator, out: *std.ArrayList(u8), function_name: []const u8) !void;
pub const ListSetPlan = struct { function_name: []const u8, list_name: []const u8, index_name: []const u8, value_name: []const u8 };
pub fn emit_byte_list_set(allocator: std.mem.Allocator, out: *std.ArrayList(u8), plan: ListSetPlan) !void;
```

The adapter may parse only the existing five oracle data flows. It must construct representation/layout facts first, return `error.UnsupportedGcCoreLowering` for any other shape, and never embed a complete WAT module string.

- [x] **Step 4: Run module, parser, and engine gates.**

Run: `cd src && zig test build/codegen_gc_core.zig`

Run: `RUN_GC_CORE=1 WASMTIME_BIN="$(command -v wasmtime)" ./src/build/test/run_tests.sh`

Expected: Current text/list source probes still return `27815`; emitted GC oracle WAT has no ARC symbol.

- [x] **Step 5: Commit the text/list lowering.**

```bash
git add src/build/runtime_gc_wat.zig src/build/runtime_gc_prelude_wat.zig src/build/codegen_gc_emit.zig src/build/codegen_gc_core.zig src/main.zig
git commit -m "Refactor GC text and list lowering"
```

### Task 5: G2 Managed Struct and Tuple Rebuild

**Files:**
- Modify: `src/build/codegen_gc_layout.zig`
- Modify: `src/build/runtime_gc_wat.zig`
- Modify: `src/build/codegen_gc_emit.zig`
- Modify: `src/build/codegen_gc_core.zig`
- Modify: `src/build/codegen_emit_tuple.zig`
- Test: `examples/gc-p3-runtime/managed-struct-*.do` plus new Tuple focused tests

**Consumes:** Task 4 byte-list allocation and Task 2 struct layouts.

**Produces:** Typed GC structs whose fields hold inline scalars or typed GC references. A struct field update rebuilds the outer struct and preserves every untouched field. A Tuple with a managed leaf uses a typed GC container rather than the ARC storage-pack ownership path.

- [ ] **Step 1: Add preservation tests for nested managed values.**

Test the existing `Box.value`/`Box.tag` probe and a `Tuple<text, [u8]>` update. Both must prove that the input value remains readable after the returned value changes.

```zig
try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $Box") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $Box $tag") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "call $__arc_") == null);
```

- [ ] **Step 2: Run failing focused tests.**

Run: `cd src && zig test build/codegen_gc_emit.zig --test-filter "managed struct"`

Expected: Fail until struct and Tuple paths use typed GC layouts.

- [ ] **Step 3: Implement field-indexed typed layout and rebuild.**

Use `GcFieldLayout.field_index` for field selection. Allocate the revised nested list first, load every unchanged field from the old struct, then issue one `struct.new` for the new value. Do not use `struct.set` on a published source value. For Tuple, represent only the admitted managed-leaf case as a GC struct and reject unsupported nested shape before emission.

- [ ] **Step 4: Run the struct/Tuple gates.**

Run: `cd src && zig test build/codegen_gc_core.zig`

Run: `RUN_GC_CORE=1 WASMTIME_BIN="$(command -v wasmtime)" ./src/build/test/run_tests.sh`

Expected: All existing managed-struct probes return `27815`; new Tuple tests confirm immutable rebuild and typed local transfer.

- [ ] **Step 5: Commit managed aggregate support.**

```bash
git add src/build/codegen_gc_layout.zig src/build/runtime_gc_wat.zig src/build/codegen_gc_emit.zig src/build/codegen_gc_core.zig src/build/codegen_emit_tuple.zig
git commit -m "Add GC managed aggregate rebuild"
```

### Task 6: G3 Synchronous Root Conversion

**Files:**
- Create: `src/build/codegen_control_flow.zig`
- Modify: `src/build/codegen_context.zig`
- Modify: `src/build/codegen_body.zig`
- Modify: `src/build/codegen_emit_expression.zig`
- Modify: `src/build/codegen_emit_call.zig`
- Modify: `src/build/codegen_emit_control.zig`
- Modify: `src/build/codegen_emit_struct.zig`
- Modify: `src/build/codegen_emit_struct_fields.zig`
- Modify: `src/build/codegen_emit_storage_values.zig`
- Modify: `src/build/codegen_emit_storage_operations.zig`
- Modify: `src/build/codegen_emit_tuple.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Test: new focused `compile_ok` fixtures for overwrite, branch, loop, defer, return, and call

**Consumes:** Tasks 2-5 and the existing reachability functions in `codegen_ownership.zig`.

**Produces:** A non-CLI `emit_gc_wat_for_supported_program` test entry that drives normal collection and body lowering with typed GC locals. It is not a public backend selector. Pure control-flow helpers move out of ARC ownership code before release emission is removed.

- [ ] **Step 1: Add normal-pipeline GC fixtures and output assertions.**

Create fixtures covering a text/list local overwrite, branch join, loop-carried managed value, defer plus return, and a managed function call. Their `.expect` files must require typed GC local declarations and forbid `__arc_inc`, `__arc_dec`, and `__arc_payload`.

```text
(local $value (ref null $do_text))
!__arc_inc
!__arc_dec
```

- [ ] **Step 2: Run the fixture target before the GC normal pipeline exists.**

Run: `cd src && zig test build/codegen_pipeline.zig --test-filter "synchronous GC"`

Expected: Fail because normal collection has no GC backend test entry.

- [ ] **Step 3: Introduce the internal backend entry and root-plan use.**

Define an internal-only option and entry point:

```zig
const RuntimeBackend = enum { arc_transition, gc_test };
pub fn emit_gc_wat_for_supported_program(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, graph: ?*const imports.ModuleGraph) ![]u8;
```

Use `RootPlan` to keep managed values in typed locals at every listed root point. Replace ARC overwrite release with direct typed-local replacement. Move only pure reachability/loop-label functions to `codegen_control_flow.zig`; preserve their behavior and tests.

- [ ] **Step 4: Run synchronous conversion gates.**

Run: `cd src && zig test build/codegen_pipeline.zig`

Run: `./src/build/test/run_tests.sh`

Expected: New GC-only tests pass while default output still uses the current transition backend; full standard regression remains green.

- [ ] **Step 5: Commit the synchronous conversion.**

```bash
git add src/build/codegen_control_flow.zig src/build/codegen_context.zig src/build/codegen_body.zig src/build/codegen_emit_expression.zig src/build/codegen_emit_call.zig src/build/codegen_emit_control.zig src/build/codegen_emit_struct.zig src/build/codegen_emit_struct_fields.zig src/build/codegen_emit_storage_values.zig src/build/codegen_emit_storage_operations.zig src/build/codegen_emit_tuple.zig src/build/codegen_pipeline.zig src/build/test/compile_ok
git commit -m "Add synchronous GC root lowering"
```

### Task 7: G4 Suspended Roots and Component Resource Boundaries

**Files:**
- Modify: `src/build/codegen_gc_roots.zig`
- Modify: `src/build/codegen_component_abi_plan.zig`
- Modify: `src/build/codegen_component_resource_plan.zig`
- Modify: `src/build/codegen_component_async*.zig`
- Modify: `src/build/codegen_component_future_owned*.zig`
- Modify: `src/wit/manifest.zig`
- Modify: `src/wit/emit_manifest.zig`
- Modify: `src/wit/manifest_test.zig`
- Test: existing P3 async/resource fixtures and their Rust/Wasmtime runners

**Consumes:** G1 plan types and the existing bounded Component lowering set.

**Produces:** GC-managed Future/Stream frame fields for admitted bounded shapes, plus manifest resource facts sufficient to build a separate `ResourcePlan`. `AbiPlan` continues to lower to canonical buffers; no GC reference crosses the Component boundary.

- [ ] **Step 1: Add negative terminal-state and boundary tests.**

Test that a suspended frame root survives until the terminal event, cancel and completion race through a single terminal decision, an owned resource has exactly one drop action, and ABI validation rejects a GC reference in a canonical argument/result slot.

```zig
try std.testing.expectError(error.DuplicateTerminalCleanup, build_resource_plan(allocator, duplicate_terminal_facts));
try std.testing.expectError(error.GcReferenceCannotCrossCanonicalAbi, validate_abi_plan(illegal_ref_plan));
```

- [ ] **Step 2: Run the current bounded Component test modules before conversion.**

Run: `cd src && zig test build/codegen_component_async_call_plan_test.zig`

Run: `cd src && zig test build/codegen_component_future_owned_plan_test.zig`

Expected: Existing behavior passes; the new root/resource assertions fail until plans are consumed by the emitters.

- [ ] **Step 3: Extend only the manifest facts needed by admitted resources.**

Add deterministic resource transfer entries with `kind`, `direction`, `drop_authority`, and `terminal_action`. Validate them on parse and emission. Use the new facts to build a `ResourcePlan`; reject a generated binding that lacks these facts rather than guessing ownership.

- [ ] **Step 4: Convert bounded frames and preserve terminal cleanup order.**

At await/next/cancel boundaries, store only `GcManaged` values in GC frame fields. Marshal each canonical argument/result through `AbiPlan`. Apply `ResourcePlan` after the host terminal outcome, preserving the existing LIFO defer then resource-drop then frame-invalidation order. Do not admit a new producer expression or host operation shape in this task.

- [ ] **Step 5: Run Component gates.**

Run: `cd src && zig test main.zig`

Run: `./src/build/test/run_tests.sh`

Run the current Rust/Wasmtime ready, pending, error, cancel, and early-drop runners recorded beside the admitted P3 fixtures.

Expected: All bounded shapes preserve their canonical WIT and terminal cleanup contracts; failures remain explicit capability errors.

- [ ] **Step 6: Commit the suspension and ABI boundary conversion.**

```bash
git add src/build/codegen_gc_roots.zig src/build/codegen_component_abi_plan.zig src/build/codegen_component_resource_plan.zig src/build/codegen_component_async*.zig src/build/codegen_component_future_owned*.zig src/wit/manifest.zig src/wit/emit_manifest.zig src/wit/manifest_test.zig
git commit -m "Use GC roots for bounded component async"
```

### Task 8: G5 Default Switch and ARC Removal

**Files:**
- Modify: `src/build/cli.zig`
- Modify: `src/build/run.zig`
- Modify: `src/build/codegen_model.zig`
- Modify: `src/build/codegen_context.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: all remaining `codegen_emit_*.zig` modules importing `codegen_ownership.zig`
- Delete: `src/build/codegen_gc_core.zig`
- Delete: `src/build/runtime_arc_wat.zig`
- Delete: `src/build/runtime_prelude_wat.zig`
- Delete: `src/build/codegen_ownership.zig`
- Test: full regression, Core GC probes, Component validation, source and output residual scans

**Consumes:** G2-G4 equivalent output paths and gates.

**Produces:** `do build` and `do test --compiled` use the GC backend for every admitted managed path. There is no `--gc-core` CLI flag, no ARC prelude, no ARC retain/release lowering, and no ARC output assertion.

- [ ] **Step 1: Add final fail-closed CLI and residual tests.**

Add a CLI test that `do build file.do --gc-core` reports `error[UnexpectedCliArg]`. Add compiled output tests requiring GC type declarations for managed values and forbidding every ARC symbol family.

```bash
! rg -n --glob '*.zig' 'emit_arc_runtime_prelude|__arc_|codegen_ownership|runtime_arc_wat|runtime_prelude_wat' src/build
! rg -n --glob '*.expect' '__arc_' src/build/test
```

- [ ] **Step 2: Run the new tests before removing the transition backend.**

Run: `./src/build/test/run_tests.sh`

Expected: The new final residual assertions fail while ARC code and `--gc-core` remain.

- [ ] **Step 3: Route default emission through the GC backend and remove transition code.**

Remove `gc_core` from `cli.Args`, parser state, `run.compile_program_wat`, `EmitOptions`, and special-target counting. Replace `runtime_prelude_wat.emit_string_data_memory` with `runtime_canonical_memory_wat.emit_string_data_memory`. Replace ARC layout aliases in `codegen_model.zig` with GC layout facts. Delete only after every import reaches the GC modules and the pure control-flow functions live in `codegen_control_flow.zig`.

- [ ] **Step 4: Update expected output and active documentation.**

Rewrite only ARC-specific WAT expectations to assert GC semantics. Update `doc/memory.md`, `doc/roadmap_status.md`, and `examples/gc-p3-runtime/README.md` to state that GC is implemented and the restricted oracle has been removed. Preserve historical ARC evidence only in changelog/history documents.

- [ ] **Step 5: Run the final required gates.**

Run: `cd src && zig build -Doptimize=ReleaseSmall`

Run: `./src/build/test/run_tests.sh`

Run: `RUN_WASM=1 ./src/build/test/run_tests.sh`

Run: Core GC compile-and-run probes for text, list, struct, and Tuple using current `wasm-tools` and Wasmtime with `-W gc=y`.

Run: Current Component assembly, canonical ABI validation, and Rust/Wasmtime ready, pending, error, cancel, early-drop evidence for every admitted async/resource shape.

Run: the two residual scan commands from Step 1 and an equivalent scan over generated WAT artifacts.

Expected: All gates pass. Any failed Component or host-runtime gate blocks G5 and does not restore ARC.

- [ ] **Step 6: Commit the one-backend switch.**

```bash
git diff --name-only -- src/build src/wit src/main.zig doc/memory.md doc/roadmap_status.md examples/gc-p3-runtime/README.md
git add src/build/cli.zig src/build/run.zig src/build/codegen_model.zig src/build/codegen_context.zig src/build/codegen_pipeline.zig src/build/codegen_control_flow.zig src/build/codegen_gc_representation.zig src/build/codegen_gc_layout.zig src/build/codegen_gc_roots.zig src/build/codegen_gc_emit.zig src/build/runtime_gc_wat.zig src/build/runtime_gc_prelude_wat.zig src/build/runtime_canonical_memory_wat.zig src/main.zig doc/memory.md doc/roadmap_status.md examples/gc-p3-runtime/README.md
git commit -m "Switch default runtime to Wasm GC"
```

### Task 9: Resume the Deferred Mainline

**Files:**
- Modify: `doc/roadmap_status.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Test: capability-specific plans and gates for each new admitted shape

**Consumes:** G5 completion evidence.

**Produces:** A correctly ordered continuation queue. Each item begins with its own design and pinned WIT/ABI probe; none inherits admission merely because the GC backend exists.

- [ ] **Step 1: Record the G5 evidence and unblock only dependent work.**

Move the GC backend item to completed only after every Task 8 gate passes. Keep any failed external runtime probe listed with command, failure, impact, and retry condition.

- [ ] **Step 2: Restore work in the fixed order.**

```text
1. General async-call lowering.
2. Arbitrary producer expressions and generic resource/list shapes.
3. General filesystem async.
4. D2 true host I/O and external HTTP.
```

- [ ] **Step 3: Verify the queue does not overstate capability admission.**

Run: `rg -n -i 'general async|arbitrary producer|filesystem async|D2|GC migration' doc/roadmap_status.md doc/host_abi_blockers.md doc/pending_blocked.md`

Expected: Each item retains its own WIT, Component, and terminal-cleanup gate. None claims implementation from the GC migration alone.

- [ ] **Step 4: Commit the post-migration roadmap state.**

```bash
git add doc/roadmap_status.md doc/host_abi_blockers.md doc/pending_blocked.md
git commit -m "Resume post-GC capability roadmap"
```

## Plan Self-Review

### Specification coverage

- One GC backend and no long-lived selector: Tasks 1, 4, 6, and 8.
- Pointer-free Do source and preserved value semantics: Global Constraints; Tasks 2, 4, 5, and 8.
- COW/rebuild semantics and no read-only payload copy: Tasks 4 and 5 with engine probes.
- Separate Do GC, canonical ABI, and resource lifetimes: Tasks 3 and 7.
- Existing `--gc-core` absorbed rather than duplicated: Tasks 1, 4, 5, and 8.
- Sync roots, suspendable roots, and Component paths: Tasks 6 and 7.
- ARC removal and residual evidence: Task 8.
- Deferred mainline order: Task 9.

### Placeholder scan

The implementation tasks specify paths, public interfaces, failure behavior, test commands, and exit criteria. The plan uses no unfinished implementation markers.

### Type consistency

`ValueRep` is produced by Task 2 and consumed by Tasks 3-7. `GcStructLayout` is produced by Task 2 and consumed by Tasks 4-6. `RootPlan`, `AbiPlan`, and `ResourcePlan` are produced by Task 3 and consumed by Tasks 6-7. No later task relies on a source-visible ownership type.

## Execution Handoff

Execute Tasks 1-9 serially because each phase changes shared compiler contracts and its gate determines whether the next phase is admissible. Tasks 2 and 3 may be developed in parallel only in isolated worktrees after agreeing on the `ValueRep` interface; merge Task 2 first.
