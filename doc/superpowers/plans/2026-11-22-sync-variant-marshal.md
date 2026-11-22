# Synchronous Recursive Variant Marshal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement measured recursive synchronous Component lowering and lifting for `option<T>`, `result<T, E>`, and general `variant` values without allowing Wasm GC references across the canonical ABI.

**Architecture:** Extend the existing `SyncValuePlan` tree with variant nodes and a structured canonical signature. The planner validates source types and measured layouts recursively; the module and WAT emitters consume the same validated tree for canonical import types, active-case dispatch, payload conversion, and cleanup. Existing scalar/text/list/map/record routes remain the implementation primitives.

**Tech Stack:** Zig compiler sources, WIT parser/model, Wasm GC WAT emission, `wasm-tools` Component validation, existing Zig integration harness.

**Spec:** `doc/superpowers/specs/2026-11-22-sync-variant-marshal-design.md`

## Global Constraints

- No canonical import parameter or result may contain a Wasm GC reference.
- Descriptor identity and measured layout are mandatory; source-name or string-only ABI inference is forbidden.
- Only synchronous value shapes are in scope; tuple, resource, future, stream, async, and unmeasured aggregates remain fail-closed.
- An inactive variant case must not be read, allocated, copied, or freed.
- Invalid discriminants must trap before the canonical call on lower and before publishing a lifted GC value.
- Every temporary linear allocation is freed exactly once in reverse allocation order.
- Existing scalar/list/map/record tests and the full integration suite must remain green.

## Review Focus

- A variant with a no-payload case must not access stale payload bytes. Test in Task 3.
- Nested payload layout must use the case payload offset, not the parent offset. Test in Task 2 and Task 4.
- A text/list payload must be cleaned up when another case is active or when a guard traps. Test in Task 4.
- Case names and tags can drift independently in a descriptor. Test both mismatches in Task 1.
- A flat canonical variant and an indirect canonical variant have different import signatures. Test both in Task 2.

### Task 1: Recursive variant model and measured validation

**Files:**
- Modify: `src/build/codegen_component_marshal_plan.zig`
- Modify: `src/build/wit_abi_layout.zig`
- Modify: `src/build/wit_abi_types.zig`
- Modify: `src/build/codegen_component_marshal_ops.zig`
- Modify: `src/build/codegen_component_marshal_module.zig`
- Modify: `src/build/codegen_component_marshal_wat.zig`
- Test: `src/build/codegen_component_marshal_plan.zig`

**Interfaces:**
- Consumes: existing `wit_types.AbiType`, `MeasuredNode`, `wit_layout.LayoutPlan`, and `SyncValuePlan`.
- Produces: `NodeKind.option`, `NodeKind.result`, `NodeKind.variant`; owned case metadata; recursive variant binding through `build_node` and `bind_measured_node`.

- [ ] **Step 1: Write failing planner tests.**

Add tests for `option<u32>`, `result<text,u32>`, a three-case scalar/text/unit variant, and nested `result<option<u32>,text>`. Assert node kind, case count, tags, payload child mapping, and recursive child kinds. Add negative tests for duplicate tags, case-name drift, missing payload, invalid payload region, and unsupported resource/tuple/future/stream payloads.

- [ ] **Step 2: Run the planner tests and verify RED.**

Run: `cd src && zig test build/codegen_component_marshal_plan.zig`

Expected: FAIL because option/result/variant still return `UnsupportedMarshalShape` and the measured variant layout is not bound recursively.

- [ ] **Step 3: Implement the recursive model and validation.**

Add variant node metadata and the variant branch to `build_node`, `canonical_alignment`, `bind_measured_node`, and `deinit_node`. Normalize option/result to measured two-case variants while retaining source kind. Keep measured variant children case-aligned; a no-payload case uses an explicit unit sentinel and never invokes payload binding. Extend `wit_abi_layout` validation only for facts that are independent of the marshal tree, such as discriminant alignment, duplicate case tags/names, and payload bounds.

- [ ] **Step 4: Run planner tests and verify GREEN.**

Run: `cd src && zig test build/codegen_component_marshal_plan.zig`

Expected: all planner tests pass, including existing map and descriptor tests.

- [ ] **Step 5: Commit.**

```bash
git add src/build/codegen_component_marshal_plan.zig src/build/wit_abi_layout.zig src/build/wit_abi_types.zig src/build/codegen_component_marshal_ops.zig src/build/codegen_component_marshal_module.zig src/build/codegen_component_marshal_wat.zig
git commit -m "feat: model recursive component variants"
```

### Task 2: Structured canonical signature and import type emission

**Files:**
- Modify: `src/build/codegen_component_abi_plan.zig`
- Modify: `src/build/codegen_component_marshal_plan.zig`
- Modify: `src/build/codegen_component_marshal_module.zig`
- Test: `src/build/codegen_component_marshal_module.zig`

**Interfaces:**
- Consumes: Task 1 variant nodes and measured layout facts.
- Produces: structured canonical core signature owned by `SyncValuePlan`; module import types derived from that signature.

- [ ] **Step 1: Write failing signature tests.**

Add tests for a flat `option<u32>`/`result<u32,u32>` signature and an indirect variant with a result-area pointer. Assert exact core parameter/result words, discriminant position, payload regions, and absence of `(ref` in the emitted import type. Add a nested payload test proving the signature is derived from the child measurement.

- [ ] **Step 2: Run the focused module tests and verify RED.**

Run: `cd src && zig test build/codegen_component_marshal_module.zig`

Expected: FAIL because variant plans cannot currently be built and import emission switches only on scalar/text/list/map/record copy shapes.

- [ ] **Step 3: Implement structured signature derivation.**

Add the minimum ABI records needed to represent flat core words, indirect pointer/result-area use, discriminant placement, and case payload slots. Derive the signature recursively from the measured tree. Replace variant admission decisions based on `canonical_type_name`; retain string formatting only at the WAT boundary. Validate that no signature slot is a GC reference.

- [ ] **Step 4: Update module emission and verify GREEN.**

Make `emit_canonical_import_type` consume the structured signature. Keep the existing scalar/list/map/record output byte-for-byte compatible where their signature is unchanged.

Run: `cd src && zig test build/codegen_component_marshal_module.zig`

Expected: all focused module tests pass and existing canonical import snapshots remain unchanged.

- [ ] **Step 5: Commit.**

```bash
git add src/build/codegen_component_abi_plan.zig src/build/codegen_component_marshal_plan.zig src/build/codegen_component_marshal_module.zig
git commit -m "feat: derive canonical signatures for variants"
```

### Task 3: Scalar and no-payload variant WAT dispatch

**Files:**
- Modify: `src/build/codegen_component_marshal_ops.zig`
- Modify: `src/build/codegen_component_marshal_wat.zig`
- Test: `src/build/codegen_component_marshal_wat.zig`

**Interfaces:**
- Consumes: Task 1 variant tree and Task 2 canonical signature.
- Produces: lower/lift WAT dispatch for scalar and unit variant cases, with invalid-tag traps.

- [ ] **Step 1: Write failing WAT tests.**

Add a lower test for `variant { none, value: u32 }` that asserts tag dispatch, canonical call ordering, and no payload load in the `none` branch. Add a lift test for the same shape that asserts canonical tag dispatch and GC value construction. Add an invalid-tag test that expects a trap marker before any canonical call.

- [ ] **Step 2: Run the focused WAT tests and verify RED.**

Run: `cd src && zig test build/codegen_component_marshal_wat.zig`

Expected: FAIL because `MemoryPlan.copy_shape` and the WAT emitter have no variant path.

- [ ] **Step 3: Implement dispatch and tag guards.**

Add a variant memory/copy shape and emit structured WAT blocks for lower and lift. Use the measured tag offset and case tags. Emit a trap for unknown tags. Keep inactive payload branches free of payload reads or allocation calls.

- [ ] **Step 4: Run focused WAT tests and verify GREEN.**

Run: `cd src && zig test build/codegen_component_marshal_wat.zig`

Expected: all existing and new WAT tests pass.

- [ ] **Step 5: Commit.**

```bash
git add src/build/codegen_component_marshal_ops.zig src/build/codegen_component_marshal_wat.zig
git commit -m "feat: emit scalar variant dispatch"
```

### Task 4: Recursive text/list payload conversion and cleanup

**Files:**
- Modify: `src/build/codegen_component_marshal_wat.zig`
- Modify: `src/build/codegen_component_marshal_module.zig`
- Test: `src/build/codegen_component_marshal_wat.zig`

**Interfaces:**
- Consumes: Task 3 dispatch blocks and Task 2 structured signature.
- Produces: active-case recursive copy for text/list/record payloads and reverse exactly-once cleanup for lower and lift.

- [ ] **Step 1: Write failing payload tests.**

Add tests for `result<text,u32>` lower and lift, plus nested `result<option<u32>,text>`. Assert the active text branch emits allocation, copy, canonical call, and one reverse free; the scalar branch emits no text allocation. Add a list payload case using an already admitted scalar list measurement and assert stride and length guards come from the child measurement.

- [ ] **Step 2: Run focused tests and verify RED.**

Run: `cd src && zig test build/codegen_component_marshal_wat.zig`

Expected: FAIL because payload conversion currently only dispatches at the root copy-shape level and does not construct nested GC variants.

- [ ] **Step 3: Implement recursive payload emitters.**

Introduce one recursive lower helper and one recursive lift helper that accept a node, a base offset, and an active-case context. Reuse existing text/list/record copy helpers. Register cleanup bindings at allocation sites and emit them in reverse order from the enclosing case cleanup block. Do not allocate inactive payloads.

- [ ] **Step 4: Run focused tests and verify GREEN.**

Run: `cd src && zig test build/codegen_component_marshal_wat.zig`

Expected: all WAT tests pass, with exact cleanup-count assertions for each active payload path.

- [ ] **Step 5: Commit.**

```bash
git add src/build/codegen_component_marshal_wat.zig src/build/codegen_component_marshal_module.zig
git commit -m "feat: lower recursive variant payloads"
```

### Task 5: Parser-backed Component route and negative admission

**Files:**
- Modify: `src/build/codegen_component_marshal_route.zig`
- Modify: `src/build/codegen_component_marshal_registry.zig`
- Modify: `src/build/codegen_component_manifest_route_test.zig`
- Create: `src/build/test/compile_ok/816_component_variant_marshal.do`
- Create: `src/build/test/compile_err/816_component_variant_marshal_unsupported.do`
- Test: `src/build/codegen_component_marshal_route.zig`

**Interfaces:**
- Consumes: Tasks 1-4 public planner/module/WAT APIs.
- Produces: parser-backed synchronous option/result/variant route with hash-bound measurements and fail-closed negatives.

- [ ] **Step 1: Write failing route tests and fixtures.**

Add parser-backed WIT members for scalar option, text/scalar result, and a no-payload variant. Add a negative fixture for tuple/resource/async payloads and a descriptor drift case. Assert unsupported shapes fail before WAT output.

- [ ] **Step 2: Run route tests and verify RED.**

Run: `cd src && zig test build/codegen_component_marshal_route.zig`

Expected: FAIL because registry admission currently rejects all option/result/variant roots.

- [ ] **Step 3: Implement measured registry admission.**

Extend only the synchronous value route. Require complete case metadata and measured variant facts from the descriptor. Preserve rejection for async/resource/future/stream and unmeasured nested layouts.

- [ ] **Step 4: Run route tests and verify GREEN.**

Run: `cd src && zig test build/codegen_component_marshal_route.zig`

Expected: positive parser-backed routes emit validated canonical modules; negatives fail before WAT emission.

- [ ] **Step 5: Commit.**

```bash
git add src/build/codegen_component_marshal_route.zig src/build/codegen_component_marshal_registry.zig src/build/codegen_component_manifest_route_test.zig src/build/test/compile_ok/816_component_variant_marshal.do src/build/test/compile_err/816_component_variant_marshal_unsupported.do
git commit -m "feat: admit measured synchronous variant routes"
```

### Task 6: Component validation, documentation, and full verification

**Files:**
- Create: focused WIT/host fixtures under `examples/gc-p3-runtime/`
- Modify: `src/build/test/test_harness.zig` only if a new gate is required
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`

**Interfaces:**
- Consumes: Task 5 parser-backed route.
- Produces: independent Component validation, host execution, cleanup/equivalence evidence, and synchronized status documentation.

- [ ] **Step 1: Add failing Component gate scripts.**

Create one positive option gate, one result gate with both active payload alternatives, one variant gate with a no-payload case, and negative drift/unsupported gates. Assert `wasm-tools` validation, host-observed active values, no canonical `(ref`, and exactly-once allocation/free counts.

- [ ] **Step 2: Run the new gates and verify RED.**

Run each new script directly. Expected: the positive cases fail until the route and Component fixtures are wired; negatives must continue to fail before WAT.

- [ ] **Step 3: Wire the gates and update documentation.**

Add the gates to the existing harness only after their standalone commands pass. Update `doc/roadmap_status.md` and `doc/start_here.md` to describe this as measured synchronous option/result/variant support, retaining tuple/async/resource/unmeasured aggregate pending language.

- [ ] **Step 4: Run all verification.**

Run:

```bash
cd src && zig build test --summary all
./src/build/test/run_release_smoke.sh
git diff --check
rg -n "do_bytes|emit_bytes_type" . --hidden --glob '!.git/**' --glob '!zig-out/**' --glob '!doc/superpowers/plans/2026-11-22-sync-variant-marshal.md'
```

Expected: `14/14` integration steps pass, release smoke passes, `git diff --check` exits 0, and the legacy `$do_bytes` names have no matches.

- [ ] **Step 5: Commit.**

```bash
git add src/build doc/roadmap_status.md doc/start_here.md examples/gc-p3-runtime
git commit -m "feat: support recursive synchronous variant marshal"
```
