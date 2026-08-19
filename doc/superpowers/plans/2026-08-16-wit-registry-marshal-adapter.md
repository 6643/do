# WIT Registry Marshal Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Resolve one real WIT source member into the bounded synchronous GC marshal plan without accepting caller-supplied or drifted descriptor facts.

**Architecture:** Reuse `src/wit/parser.zig` and `src/wit/resolve.zig` to produce a WIT-owned resolved-member record. A build-side adapter converts that record into `wit_abi_types.AbiType` and the existing `DescriptorIdentity`; it then calls the measured-layout marshal-plan entry point. For a one-value plan, `lower` selects the member's single parameter and records a canonical argument slot; `lift` selects the member result and records a canonical result slot. The WIT layer does not import compiler/codegen modules, and the adapter does not emit Component or Core-WAT output.

**Tech Stack:** Zig 0.16, existing WIT model/parser/resolver, `wit_abi_types`, `wit_abi_layout`, canonical marshal plan tests, pinned `wasm-tools 1.255.0` for existing gates.

**Spec:** `doc/superpowers/specs/2026-08-16-gc-canonical-marshal-plan-design.md`

## Global Constraints

- Only synchronous value-only scalar, `string`, `list<scalar|string>`, and bounded record members are admitted.
- `option`, `result`, `variant`, `tuple`, resource, `future`, `stream`, and async functions fail closed before WAT emission.
- Descriptor identity is derived from resolved WIT package/world/interface/member and the resolver's content hash; callers cannot provide an independent registry entry.
- `wit_abi_layout` remains the only measured layout source; the provisional type-tree offsets are never used by this adapter.
- No `(ref null $do_*)` crosses a canonical Component/WIT boundary.
- The existing ARC-backed `274_wasi_preopens` route and the G5c selector remain unchanged.

---

### Task 1: Add the WIT resolved-member boundary

**Files:**
- Create: `src/wit/marshal_registry.zig`
- Modify: `src/wit/tests.zig`
- Test: `src/wit/tests.zig`

**Interfaces:**
- Consumes: `model.BindingModel`, `model.InterfaceDecl`, `model.FunctionDecl`.
- Produces: `ResolvedValueMember`, `find_value_member(binding, interface_name, member_name)` and a stable `descriptor_hash` view.

- [x] **Step 1: Write the failing tests.**

  Add inline WIT fixtures asserting that `find_value_member` returns the selected interface/function and rejects an unknown interface, unknown member, async function, and resource-containing parameter/result.

- [x] **Step 2: Run the focused WIT tests.**

  ```bash
  cd src && zig test wit/tests.zig
  ```

  Expected: the new tests fail because `marshal_registry.zig` and `find_value_member` do not exist.

- [x] **Step 3: Implement the minimal resolver boundary.**

  Define `ResolvedValueMember` with borrowed WIT model references, package/world/interface/member names, and the resolver `content_hash`. Search only `binding.interfaces` and require exactly one matching member. Reject `FunctionDecl.is_async`, any `effects.has_future`, `effects.has_stream`, `effects.has_resource`, and any type tree containing `own`, `borrow`, `future`, `stream`, `option`, `result`, `variant`, or `tuple`.

- [x] **Step 4: Run the focused WIT tests again.**

  ```bash
  cd src && zig test wit/tests.zig
  ```

  Expected: all existing and new WIT resolver tests pass.

### Task 2: Convert bounded WIT types into ABI types

**Files:**
- Create: `src/build/codegen_component_marshal_registry.zig`
- Modify: `src/build/codegen_gc_plans_test.zig`
- Test: `src/build/codegen_gc_plans_test.zig`

**Interfaces:**
- Consumes: `wit.marshal_registry.ResolvedValueMember` and `wit.model` declarations.
- Produces: `resolve_member_abi_type(allocator, member)`, returning an owned `wit_abi_types.AbiType` or a named capability error.

- [x] **Step 1: Write the failing conversion tests.**

  Add tests for `u32`, `string`, `list<u8>`, and a record with scalar/string/list fields. Add negative tests for named resource, `option`, `result`, `variant`, `tuple`, unknown type alias, and a record cycle.

- [x] **Step 2: Run the focused marshal-plan tests.**

  ```bash
  cd src && zig test main.zig --test-filter 'WIT registry'
  ```

  Expected: the new tests fail because the build-side adapter does not exist. The aggregate `main.zig` root is required because a standalone `src/build` test module cannot import `src/wit` outside its module path.

- [x] **Step 3: Implement recursive type conversion with guards.**

  Map WIT scalar kinds to `wit_abi_types.ScalarKind`, map `string` to `AbiType.text`, construct lists and records through their owned constructors, resolve aliases and record declarations from the selected interface, and maintain a recursion stack keyed by declaration name. Return `UnsupportedWitMarshalShape` for all non-bounded kinds and `UnresolvedWitType` for missing declarations.

- [x] **Step 4: Run the focused tests.**

  ```bash
  cd src && zig test main.zig --test-filter 'WIT registry'
  ```

  Expected: conversion tests pass, including cleanup on failed recursive conversion.

### Task 3: Bind the resolved descriptor to the measured marshal plan

**Files:**
- Modify: `src/build/codegen_component_marshal_plan.zig`
- Modify: `src/build/codegen_component_marshal_registry.zig`
- Modify: `src/build/codegen_gc_plans_test.zig`

**Interfaces:**
- Consumes: WIT source text and caller-provided measured `MeasuredNode` facts.
- Produces: `build_sync_value_plan_from_wit_source(allocator, source, world_name, interface_name, member_name, direction, measured)` returning an owned `SyncValuePlan`.

- [x] **Step 1: Add the red drift and provenance tests.**

  Assert that the plan uses the resolver's package/world/member/hash, rejects a caller descriptor that differs from the resolved member, rejects a measured scalar/record/list mismatch, and leaves the existing manual `build_sync_value_plan_with_registry` API unchanged for its unit tests.

- [x] **Step 2: Run the focused tests and confirm failure.**

  ```bash
  cd src && zig test main.zig --test-filter 'resolved WIT'
  ```

  Expected: the new helper is unavailable or the provenance assertions fail.

- [x] **Step 3: Implement the adapter entry point.**

  Expose `build_sync_value_plan_from_wit_source(allocator, source, world_name, interface_name, member_name, direction, measured)`. Resolve the source with `wit.resolve.resolve_source`, compute `sha256:<64 lowercase hex>` from `BindingModel.content_hash`, construct the build-side `DescriptorIdentity` from the resolved WIT member, convert the selected function's bounded value type, and call `build_sync_value_plan_with_layout`. Keep the binding-based helper private so callers cannot bypass parser provenance or provide a second registry identity argument.

- [x] **Step 4: Run focused and existing marshal tests.**

  ```bash
  cd src && zig test build/codegen_gc_plans_test.zig
  ```

  Expected: the complete marshal-plan suite passes and no GC reference can enter the ABI slot.

### Task 4: Record the gate and verify the unchanged residual route

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/roadmap_status.md`
- Test: existing full harness and G5c residual gate

- [x] **Step 1: Run the complete verification set.**

  ```bash
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  bash src/build/test/check_gc_g5c_residual_gate.sh baseline
  ```

- [x] **Step 2: Record exact evidence.**

  Document the new parser-backed adapter as a design-gate increment only. Keep `host_wit_marshalling` pending until Component assembly, host-driven execution, and ARC/GC equivalence exist. Record any failed command verbatim with its retry condition.

- [ ] **Step 3: Commit only this task's files.**

  ```bash
  git add src/wit/marshal_registry.zig src/wit/tests.zig \
    src/build/codegen_component_marshal_registry.zig \
    src/build/codegen_component_marshal_plan.zig \
    src/build/codegen_gc_plans_test.zig doc/host_abi_blockers.md \
    doc/roadmap_status.md doc/superpowers/plans/2026-08-16-wit-registry-marshal-adapter.md
  git commit -m "Bind bounded marshal plans to resolved WIT members"
  ```

## Completion Criteria

1. A real WIT source member, not a caller-supplied registry struct or public `BindingModel`, is required to build the bounded plan.
2. Package/world/interface/member/hash drift and unsupported WIT shapes fail before WAT emission.
3. Measured layout facts still come from `wit_abi_layout`.
4. Existing compiler, WIT, and residual ARC route tests remain green.
5. The host/WIT inventory row remains pending until Component assembly, host execution, and equivalence gates are implemented.

## Deferred Work

This plan does not implement canonical Component assembly, host execution, `list<text>`/arbitrary layouts, option/result/variant lowering, async frames, resources, or G5c default backend cutover.
