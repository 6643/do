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
- Inspect: `src/build/codegen_emit_tuple.zig` (the existing ARC storage-pack path remains outside this restricted oracle)
- Test: `examples/gc-p3-runtime/managed-struct-*.do` plus new Tuple focused tests

**Consumes:** Task 4 byte-list allocation and Task 2 struct layouts.

**Produces:** Typed GC structs whose fields hold inline scalars or typed GC references. A struct field update rebuilds the outer struct and preserves every untouched field. A Tuple with a managed leaf uses a typed GC container rather than the ARC storage-pack ownership path.

- [x] **Step 1: Add preservation tests for nested managed values.**

Test the existing `Box.value`/`Box.tag` probe and a `Tuple<text, [u8]>` update. Both must prove that the input value remains readable after the returned value changes.

```zig
try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $Box") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $Box $tag") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "call $__arc_") == null);
```

- [x] **Step 2: Run failing focused tests.**

Run: `cd src && zig test build/codegen_gc_emit.zig --test-filter "managed struct"`

Expected: Fail until struct and Tuple paths use typed GC layouts.

- [x] **Step 3: Implement field-indexed typed layout and rebuild.**

Use `GcFieldLayout.field_index` to validate the admitted field order. Allocate the revised nested list first, load every unchanged field from the old struct, then issue one `struct.new` for the new value. Do not use `struct.set` on a published source value. For Tuple, represent only the admitted managed-leaf case as a GC struct and reject unsupported nested shape before emission.

- [x] **Step 4: Run the struct/Tuple gates.**

Run: `cd src && zig test build/codegen_gc_core.zig`

Run: `RUN_GC_CORE=1 WASMTIME_BIN="$(command -v wasmtime)" ./src/build/test/run_tests.sh`

Expected: All existing managed-struct probes return `27815`; new Tuple tests confirm immutable rebuild and typed local transfer.

- [x] **Step 5: Commit managed aggregate support.**

```bash
git add src/build/codegen_gc_layout.zig src/build/runtime_gc_wat.zig src/build/runtime_gc_prelude_wat.zig src/build/codegen_gc_emit.zig src/build/codegen_gc_emit_test.zig src/build/codegen_gc_facts_test.zig src/build/codegen_gc_core.zig src/build/diag.zig src/build/test/check_gc_core_oracles.sh examples/gc-p3-runtime
git commit -m "Add GC managed aggregate rebuild"
```

**G2 checkpoint (2026-08-12):** `Tuple<text, [u8]>` is admitted through a
typed GC struct and Wasmtime proves old-value preservation. Fixed-list and
managed-struct nested copies now use runtime `array.len`, and managed-struct
profiles retain source type/function/field bindings. The synchronous GC
prelude emits nested managed struct declarations in dependency order and
rejects invalid forward/cyclic/missing layouts before WAT emission. The
restricted oracle emitters still produce one standalone probe module per
call; a fragment-only composition API remains a follow-up before the normal
GC backend absorbs them.

### Task 6: G3 Synchronous Root Conversion

**Files:**
- Create: `src/build/codegen_gc_sync.zig`
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
- Modify: `src/build/codegen_api.zig`
- Test: new focused `compile_ok` fixtures for overwrite, branch, loop, defer, return, and call

**Consumes:** Tasks 2-5 and the existing reachability functions in `codegen_ownership.zig`.

**Produces:** A non-CLI `emit_gc_wat_for_supported_program` test entry that drives normal collection and body lowering with typed GC locals. It is not a public backend selector. Pure control-flow helpers move out of ARC ownership code before release emission is removed.

- [x] **Step 1: Add normal-pipeline GC fixtures and output assertions.**

Add focused pipeline tests covering a text local overwrite, branch join, loop-carried managed value, defer plus return, and a managed function call. The assertions require typed GC local declarations, root-point markers, and forbid `__arc_inc`, `__arc_dec`, and `__arc_payload`. Add a fail-closed unsupported-list test.

```text
(local $value (ref null $do_text))
!__arc_inc
!__arc_dec
```

- [x] **Step 2: Run the fixture target before the GC normal pipeline exists.**

Run: `cd src && zig test build/codegen_pipeline.zig --test-filter "synchronous GC"`

Expected: Fail because normal collection has no GC backend test entry.

- [x] **Step 3: Introduce the internal backend entry and root-plan use.**

Define the non-CLI entry point:

```zig
pub fn emit_gc_wat_for_supported_program(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, graph: ?*const imports.ModuleGraph) ![]u8;
```

Use `RootPlan` to keep admitted managed values in typed locals and emit explicit overwrite, branch-join, loop-join, and return-root markers. The restricted backend lowers only scalar, `text`, and `[u8]` values; aggregates, resources, async syntax, host calls, and module graphs fail closed. The default ARC pipeline is unchanged. Pure control-flow extraction to `codegen_control_flow.zig` remains a follow-up before the default backend switch.

- [x] **Step 4: Run synchronous conversion gates.**

Run: `cd src && zig test build/codegen_pipeline.zig`

Run: `./src/build/test/run_tests.sh`

Expected: New GC-only tests pass while default output still uses the current transition backend; full standard regression remains green.

**G3 restricted checkpoint (2026-08-12):** The internal entry now emits valid typed-GC WAT for the five synchronous shapes. All six focused tests pass; each generated module passes `wasm-tools parse`, `wasm-tools validate`, and `wasmtime run`. `zig build -Doptimize=ReleaseSmall`, the full pipeline unit suite (`81/81`), and the standard harness (`pass=1243 fail=0 skip=3`) are green. This does not admit aggregates, imported modules, host/WASI calls, or async lowering, and does not change the default ARC route.

- [x] **Step 5: Commit the synchronous conversion.**

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

- [x] **Step 1: Add negative terminal-state and boundary tests.**

Test that a suspended frame root survives until the terminal event, cancel and completion race through a single terminal decision, an owned resource has exactly one drop action, and ABI validation rejects a GC reference in a canonical argument/result slot.

```zig
try std.testing.expectError(error.DuplicateTerminalCleanup, build_resource_plan(allocator, duplicate_terminal_facts));
try std.testing.expectError(error.GcReferenceCannotCrossCanonicalAbi, validate_abi_plan(illegal_ref_plan));
```

- [x] **Step 2: Run the current bounded Component test modules before conversion.**

Run: `cd src && zig test build/codegen_component_async_call_plan_test.zig`

Run: `cd src && zig test build/codegen_component_future_owned_plan_test.zig`

Expected: Existing behavior passes; the new root/resource assertions fail until plans are consumed by the emitters.

- [x] **Step 3: Extend only the manifest facts needed by admitted resources.**

Add deterministic resource transfer entries with `kind`, `direction`, `drop_authority`, and `terminal_action`. Validate them on parse and emission. Use the new facts to build a `ResourcePlan`; reject a generated binding that lacks these facts rather than guessing ownership.

- [x] **Step 4: Convert bounded frames and preserve terminal cleanup order.**

At await/next/cancel boundaries, store only `GcManaged` values in GC frame fields. Marshal each canonical argument/result through `AbiPlan`. Apply `ResourcePlan` after the host terminal outcome, preserving the existing LIFO defer then resource-drop then frame-invalidation order. Do not admit a new producer expression or host operation shape in this task.

- [x] **Step 5: Run Component gates.**

Run: `cd src && zig test main.zig`

Run: `./src/build/test/run_tests.sh`

Run the current Rust/Wasmtime ready, pending, error, cancel, and early-drop runners recorded beside the admitted P3 fixtures.

Expected: All bounded shapes preserve their canonical WIT and terminal cleanup contracts; failures remain explicit capability errors.

**G4 suspended-root and Component-boundary checkpoint (2026-08-12):** Negative root, terminal-race, duplicate-drop, and canonical-ABI reference tests pass. Bounded async-call and future-owned plans/emitter suites pass (`124/124`, `120/120`, `122/122`, `117/117`); GC/resource plan tests pass (`12/12`), and WIT manifest tests pass (`23/23`). `zig test main.zig`, the standard harness, and the `RUN_GC_CORE=1` oracle gate are green (`383/383`; `pass=1243 fail=0 skip=3`; eight Core-GC probes each returned `27815`). The do and Rust resource-cancellation probes, async-call component probe, and future-owned ready/pending/cancel modes all pass. The bounded emitters carry explicit root, ABI, and resource-terminal markers; canonical Component slots reject GC references, and terminal cleanup is single-shot. G5 still retains the default ARC route and is intentionally out of scope.

- [x] **Step 6: Commit the suspension and ABI boundary conversion.**

```bash
git add src/build/codegen_gc_roots.zig src/build/codegen_component_abi_plan.zig src/build/codegen_component_resource_plan.zig src/build/codegen_component_async*.zig src/build/codegen_component_future_owned*.zig src/wit/manifest.zig src/wit/emit_manifest.zig src/wit/manifest_test.zig
git commit -m "Use GC roots for bounded component async"
```

### Task 8: G5a Complete-program GC Lowering Slices

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`
- Modify: `src/build/codegen_gc_sync_adapter.zig`
- Modify: `src/build/codegen_gc_model_adapter.zig`
- Modify: `src/build/codegen_gc_representation.zig`
- Modify: `src/build/codegen_gc_layout.zig`
- Modify: `src/build/codegen_gc_roots.zig`
- Modify: `src/build/codegen_gc_emit.zig`
- Modify: `src/build/runtime_gc_prelude_wat.zig`
- Create: `src/build/gc_sync_probe.zig`
- Test: focused Zig unit tests and new backend-neutral `.do` source fixtures

**Consumes:** G2-G4 shared representation/layout/root/ABI facts and the
restricted Core-GC oracle.

**Produces:** Parsed, complete-program GC lowering for one closed synchronous
slice at a time. An admitted GC program contains only GC-managed values; it
does not call or return ARC handles.

**G5 pre-switch checkpoint (2026-08-13):** Default `do build` still emits ARC.
`codegen_gc_sync.zig` rejects module graphs, generic functions, async,
resources, host calls, multi-result functions, and unsupported managed updates.
`codegen_gc_core.zig` is a token-profile emitter. The normal pipeline still
imports ARC layout/prelude types and nine emit modules import
`codegen_ownership.zig`. This is a P0 precondition gap for default switching,
not a reason to weaken the GC gate.

**Global invariant:** Never combine ARC handles and Wasm GC references in one
emitted module's source-value data flow. The ARC default and GC test entry may
compile the same fixture separately; they may not lower different halves of one
fixture together.

**Initial G5a slices:** Parsed fixed-index and parameterized persistent `[u8]`
updates: `update(input [u8]) -> [u8] { return @set(input, 0, 65) }` and
`set_at(input [u8], index usize, value u8) -> [u8] { return @set(input, index,
value) }`. They replace the corresponding `[u8] @set` token profiles, prove
runtime-length copy plus old-value preservation, and deliberately admit no
imports, generics, async, resources, host calls, or multi-result functions.
The next closed slice is a numeric inferred `[u8]` literal expression
(`.{7, 12, 17}` or `.{}`) in an otherwise admitted synchronous program. Its
focused zero-parameter producer probe verifies separate GC allocation,
root/liveness, and first-value preservation; it does not include `@put`,
non-literal elements, or new general producer admission.

- [x] **Step 1: Add a parsed GC-program admission test surface.**

Keep `emit_gc_wat_for_supported_program` as the test-only entry and add unit
tests that feed parsed source, not token signatures, for accepted and rejected
whole programs. The first test matrix must distinguish an admitted synchronous
program from rejected module graph, generic, async, resource, host-call, and
multi-result programs.

Run: `cd src && zig test build/codegen_pipeline.zig && zig test build/codegen_gc_sync.zig`

Expected: accepted cases contain GC type declarations and no `__arc_`; every
unadmitted program returns a specific `UnsupportedGcSync*` error before WAT is
emitted.

- [x] **Step 2: Replace one profile-only GC capability with parsed lowering.**

The fixed-index, parameterized `[u8] @set`, and numeric `[u8]` literal slices
above are closed. Choose the next smallest incomplete whole-program slice from
this fixed order:

```text
1. scalar/text/[u8] expression, call, and control-flow forms;
2. managed struct construction, nested managed fields, get/set/put;
3. Tuple/storage and union carriers with managed leaves;
4. generic call and return instantiations;
5. imports, canonical value marshalling, and already-admitted Component paths.
```

Implement only the selected slice in shared representation/layout/root/emit
modules. Remove its matching `codegen_gc_core.zig` token profile only after the
parsed path has a focused unit test and the GC WAT validates.

Run: `cd src && zig test build/codegen_gc_sync.zig`

Run: `WASM_TOOLS_BIN="$(command -v wasm-tools)" WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_list_literal.sh`

Expected: the selected literal fixture validates and executes under the current
tools; its first allocation remains observable and unchanged while the second
call produces a distinct array. `@put` remains outside this gate.

- [x] **Step 3: Implement root coverage for the selected value slice.**

Extend `codegen_gc_roots.zig` and the parsed emitter for local creation,
overwrite, branch and loop joins, call arguments, return values, and `defer`
as each becomes reachable in the selected slice. A GC root is a typed GC local
or traced field, never an ARC retain/release instruction. Use private
`struct.set`/`array.set` only after proving no old logical value shares that
backing; otherwise separate first and then mutate the new backing.

Run: `cd src && zig test build/codegen_gc_roots.zig && zig test build/codegen_gc_sync.zig`

Expected: emitted WAT contains typed GC roots at each admitted liveness point,
contains no `__arc_inc` or `__arc_dec`, and preserves old-value semantics.

- [x] **Step 4: Add a backend-neutral executable fixture for the slice.**

Add one focused `.do` fixture and a test-only GC probe that asserts source-value
contents without matching ARC or GC symbol names. The probe runs through the GC
entry plus Wasmtime; default-path equivalence remains a Task 9 concern. Keep
existing ARC-specific WAT golden fixtures unchanged as migration evidence until
G5c.

Run: `WASM_TOOLS_BIN="$(command -v wasm-tools)" WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_list_literal.sh`

Expected: the GC fixture exposes the expected Do-level contents and allocation
invariants; ARC/GC equivalence is not claimed until Task 9.

- [x] **Step 5: Run the slice regression and record its exact boundary.**

Run: `cd src && zig test main.zig`

Run: `./src/build/test/run_tests.sh`

Run: `RUN_GC_CORE=1 ./src/build/test/run_tests.sh`

Expected: all existing gates remain green. Record the newly admitted complete
program shape, rejected neighboring shapes, exact commands, and output in
`doc/roadmap_status.md` and `doc/host_abi_blockers.md`; do not call G5a
complete while a default ARC-only source path remains.

**G5a literal checkpoint (2026-08-13):** `.{7, 12, 17}` and `.{}` now lower
through the parsed GC entry to `array.new_fixed`/`array.new_default`. The
literal probe passes `wasm-tools parse`, Wasmtime GC compilation, and execution
with result `27815`; it proves distinct allocations and old-value liveness.
`256` and `-1` fail before WAT as `GcSyncTypeMismatch`. Non-`u8` elements,
nested expressions, and general producer calls remain unadmitted.

**G5a `@put` checkpoint (2026-08-13):** The parsed GC entry now lowers one
`@put(input, value)` for `[u8]` plus one `u8` value. It allocates a private
`length + 1` array, copies the runtime-length source, and appends the checked
value. The focused empty/non-empty allocation probe passes `wasm-tools parse`,
Wasmtime GC compilation, and execution with `27815`; it proves old-value
preservation and distinct results. `256` and `-1` fail before WAT as
`GcSyncTypeMismatch`. Multi-value, spread, non-`u8`, nested/general producer,
and default backend forms remain outside this gate.

**G5a managed-field payload checkpoint (2026-08-13):** The parsed GC entry now
admits direct replacement of one `[u8]` field from a `[u8]` local parameter.
The outer struct is rebuilt with `struct.new`; unchanged fields are read from
the old object, and the old object/payload remain observable. The focused unit
suite passed `102/102`; the managed-struct payload probes passed `wasm-tools
parse`, Wasmtime GC compilation, and execution with `27815`, including renamed
type/field/function bindings and reversed field order. Nested producers, text
payload replacement, resource fields, and default backend forms remain outside
this gate.

### Task 9: G5b ARC/GC Semantic Equivalence Matrix

**Files:**
- Modify: `src/build/test/ok/`
- Modify: `src/build/test/compiled_ok/`
- Modify: `src/build/test/check_gc_core_oracles.sh`
- Modify: `examples/gc-p3-runtime/test_do_gc_*.sh`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/host_abi_blockers.md`

**Consumes:** One or more complete-program slices admitted by G5a.

**Produces:** Executable evidence that ARC and GC separately preserve the same
source semantics for each admitted slice. It does not switch the default.

- [ ] **Step 1: Define the per-slice observable matrix.**

For each G5a slice, add backend-neutral fixtures covering read-only pass,
aliased old-value preservation after `@set`/`@put`, local overwrite, nested
field or list update, branch and loop join, return, `defer`, and the nearest
admitted error or trap boundary. Add host/Component cases only after G5a
admits their value marshalling path. Resource tests must continue to assert
exactly-once terminal cleanup; GC reachability is not resource drop authority.

Run: `./bin/do test src/build/test/ok/01_path_get_single.do`

Expected: each fixture asserts Do-level behavior rather than `__arc_*` or a
GC WAT spelling.

- [ ] **Step 2: Run each fixture through both separate lowering paths.**

Compile the fixture through normal `emit_wat` and the GC test entry. Validate
both generated WAT artifacts with the current `wasm-tools`, then run the GC
artifact with Wasmtime and compare the fixture's observable result to the
default compiled test result. Do not compare WAT text byte-for-byte.

Run: `WASM_TOOLS_BIN="$(command -v wasm-tools)" WASMTIME_BIN="$(command -v wasmtime)" bash src/build/test/check_gc_core_oracles.sh`

Expected: each admitted slice validates and executes. A GC-only validation
pass is insufficient; an ARC-only regression pass is insufficient.

- [ ] **Step 3: Preserve failure provenance and fail closed.**

When a GC fixture fails, record the source fixture, command, compiler error or
runtime output, affected slice, and retry condition in
`doc/host_abi_blockers.md`. Leave the default ARC path unchanged and block only
the dependent G5a slice. Do not add a hidden ARC fallback to the GC entry.

- [ ] **Step 4: Run the full equivalent gates.**

Run: `cd src && zig build -Doptimize=ReleaseSmall && zig test main.zig`

Run: `./src/build/test/run_tests.sh`

Run: `RUN_WASM=1 ./src/build/test/run_tests.sh`

Run current Component assembly, canonical ABI validation, and Rust/Wasmtime
ready, pending, error, cancel, and early-drop runners for every already
admitted async/resource shape.

Expected: all previous gates and every new slice matrix are green. Any failed
Component or host runtime gate blocks G5c.

### Task 10: G5c Default GC Cutover And ARC Removal

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
- Modify: ARC-specific output fixtures and active runtime documentation

**Consumes:** G5a complete coverage of every ordinary default managed path and
G5b green equivalence evidence for each path.

**Produces:** `do build` and `do test --compiled` emit only Wasm GC for every
admitted managed path. There is no `--gc-core`, ARC prelude, ARC release
lowering, or active ARC output assertion.

- [ ] **Step 1: Add the cutover residual tests before changing routing.**

Add a CLI test that `do build file.do --gc-core` reports
`error[UnexpectedCliArg]`. Add generated-output tests that require GC type
declarations for representative managed values and forbid every ARC symbol
family.

```bash
! rg -n --glob '*.zig' 'emit_arc_runtime_prelude|__arc_|codegen_ownership|runtime_arc_wat|runtime_prelude_wat' src/build
! rg -n --glob '*.expect' '__arc_' src/build/test
```

Expected before the cutover: the residual scans fail because ARC remains.
Expected after the cutover: both scans exit successfully with no output.

- [ ] **Step 2: Prove the cutover precondition from source and execution.**

Inventory all default managed source paths: text/list, managed structs/nested
fields, Tuple/storage, generics, union carriers, local/control/defer/calls,
and host/Component marshalling. For each path, link a G5a admitted-slice test
and a G5b executable equivalence case. A missing cell is a P0 blocker and
prevents routing default output to GC.

Run: `rg -n "G5a|G5b|default managed" doc/roadmap_status.md doc/host_abi_blockers.md`

Expected: every path has exact evidence; no path depends on a mixed backend.

- [ ] **Step 3: Route default output through shared GC lowering and remove ARC.**

Remove `gc_core` from `cli.Args`, parser state, `run.compile_program_wat`,
`EmitOptions`, special-target counting, and test scripts. Route ordinary
emission through the shared GC program lowering. Replace ARC layout aliases in
`codegen_model.zig` and ARC memory/prelude helpers with GC/canonical-ABI
helpers. Delete ARC modules and imports only after no compiler path reaches
them; delete the profile emitter because all its former cases are parsed GC
lowering cases.

- [ ] **Step 4: Convert only implementation-specific tests and documents.**

Rewrite ARC-symbol WAT assertions as GC representation/root assertions while
retaining the source-level behavior fixtures. Update `doc/memory.md`,
`doc/roadmap_status.md`, and `examples/gc-p3-runtime/README.md` to state that
the implementation migration is complete and the migration selector is gone.
Preserve ARC facts only in dated historical records.

- [ ] **Step 5: Run the one-backend release gates.**

Run: `cd src && zig build -Doptimize=ReleaseSmall && zig test main.zig`

Run: `./src/build/test/run_tests.sh`

Run: `RUN_WASM=1 ./src/build/test/run_tests.sh`

Run Core GC compile-and-run probes for text, list, struct, nested struct, and
Tuple using current `wasm-tools` and Wasmtime with `-W gc=y`.

Run current Component assembly, canonical ABI validation, and Rust/Wasmtime
ready, pending, error, cancel, and early-drop evidence for every admitted
async/resource shape.

Run the residual scans from Step 1 and an equivalent scan over generated WAT
artifacts.

Expected: all gates pass. A failure blocks the cutover; it does not restore or
retain ARC as a supported backend.

- [ ] **Step 6: Commit the one-backend switch.**

```bash
git diff --name-only -- src/build src/wit src/main.zig doc/memory.md doc/roadmap_status.md examples/gc-p3-runtime/README.md
git add src/build/cli.zig src/build/run.zig src/build/codegen_model.zig src/build/codegen_context.zig src/build/codegen_pipeline.zig src/build/codegen_control_flow.zig src/build/codegen_gc_representation.zig src/build/codegen_gc_layout.zig src/build/codegen_gc_roots.zig src/build/codegen_gc_emit.zig src/build/runtime_gc_wat.zig src/build/runtime_gc_prelude_wat.zig src/build/runtime_canonical_memory_wat.zig src/main.zig doc/memory.md doc/roadmap_status.md examples/gc-p3-runtime/README.md
git commit -m "Switch default runtime to Wasm GC"
```

### Task 11: Resume the Deferred Mainline

**Files:**
- Modify: `doc/roadmap_status.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Test: capability-specific plans and gates for each new admitted shape

**Consumes:** G5c completion evidence.

**Produces:** A correctly ordered continuation queue. Each item begins with its own design and pinned WIT/ABI probe; none inherits admission merely because the GC backend exists.

- [ ] **Step 1: Record the G5 evidence and unblock only dependent work.**

Move the GC backend item to completed only after every Task 10 gate passes. Keep any failed external runtime probe listed with command, failure, impact, and retry condition.

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
- Complete-program GC lowering and one-representation invariant: Task 8.
- ARC/GC executable equivalence: Task 9.
- ARC removal and residual evidence: Task 10.
- Deferred mainline order: Task 11.

### Placeholder scan

The implementation tasks specify paths, public interfaces, failure behavior, test commands, and exit criteria. The plan uses no unfinished implementation markers.

### Type consistency

`ValueRep` is produced by Task 2 and consumed by Tasks 3-10. `GcStructLayout` is produced by Task 2 and consumed by Tasks 4-10. `RootPlan`, `AbiPlan`, and `ResourcePlan` are produced by Task 3 and consumed by Tasks 6-10. No later task relies on a source-visible ownership type or combines ARC and GC representations in one program.

## Execution Handoff

Execute Tasks 1-11 serially because each phase changes shared compiler contracts and its gate determines whether the next phase is admissible. Tasks 2 and 3 may be developed in parallel only in isolated worktrees after agreeing on the `ValueRep` interface; merge Task 2 first. Tasks 8-10 are strictly serial: G5b depends on G5a's admitted slices, and G5c depends on the completed matrix rather than a partial GC probe.
