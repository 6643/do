# Bounded Marshal Component Assembly Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Assemble one parser-backed, synchronous text marshal plan into a valid Wasm Component artifact without admitting host execution or arbitrary WIT shapes.

**Architecture:** Keep the existing source-backed `SyncValuePlan` and bounded marshal WAT emitter as the only sources of type and copy facts. Add a core-module wrapper that supplies the explicitly measured GC declarations, linear memory, realloc helper, canonical call import, and one exported probe function. A fixture-level assembly script embeds the pinned WIT package and validates the resulting Component; the compiler's normal ARC host/WIT route is unchanged.

**Tech Stack:** Zig 0.16, existing `codegen_component_marshal_plan` / `codegen_component_marshal_wat`, WIT parser/resolver, `wasm-tools 1.255.0`, Wasm GC and Component Model validation.

**Spec:** `doc/superpowers/specs/2026-08-16-gc-canonical-marshal-plan-design.md`

## Global Constraints

- Admit only one synchronous `string` parameter for lower or one synchronous `string` result for lift.
- Keep `option`, `result`, `variant`, `tuple`, resources, `future`, `stream`, and arbitrary producers rejected before module emission.
- No `(ref null $do_*)` may occur in a canonical Component import or export signature; GC references stay inside the core wrapper.
- Use the exact `wasm-tools 1.255.0 (76e20611d 2026-07-30)` executable and existing assembly validation flow.
- Do not change `274_wasi_preopens`, the default ARC route, the GC migration inventory, or G5c status.
- This plan does not add a CLI flag or claim a host-driven runtime.

---

### Task 1: Emit a bounded core-module wrapper

**Files:**
- Create: `src/build/codegen_component_marshal_module.zig`
- Modify: `src/build/codegen_gc_plans_test.zig`
- Test: `src/build/codegen_component_marshal_module.zig`

**Interfaces:**
- Consumes: `marshal.SyncValuePlan` and `codegen_component_marshal_wat.emit_sync_marshal_function`.
- Produces: `emit_sync_marshal_module(allocator, plan, config) ![]u8`, where `config` contains only validated WAT names and the pinned canonical import identity.

- [x] **Step 1: Add a failing structural test.**

  Build a parser-backed lower text plan and assert that the emitted module contains the `$do_bytes` and `$do_text` GC types, exported memory, a typed `cabi_realloc`, the descriptor-derived canonical import, and no canonical parameter containing `(ref`.

- [x] **Step 2: Run the focused test and capture the missing-entry failure.**

  ```bash
  cd src && zig test main.zig --test-filter 'marshal module wrapper'
  ```

  Expected: failure because `codegen_component_marshal_module.zig` does not exist.

- [x] **Step 3: Implement the wrapper with explicit shape guards.**

  Reject any plan whose root is not `text`, whose direction is not the requested direction, or whose canonical ABI slot is not exactly one argument for lower or one result for lift. Emit only declarations needed by the selected fragment and append the existing function body unchanged. Keep the canonical call and realloc identities explicit; do not infer import names from arbitrary source tokens.

- [x] **Step 4: Run the focused test and the module string checks.**

  ```bash
  cd src && zig test main.zig --test-filter 'marshal module wrapper'
  ```

  Expected: all wrapper tests pass and unsupported list/record/GC-boundary cases fail with named errors.

### Task 2: Assemble and validate the pinned Component fixture

**Files:**
- Create: `examples/gc-p3-runtime/marshal-text-assembly.wit`
- Create: `examples/gc-p3-runtime/test_gc_marshal_text_component.sh`
- Create: `examples/gc-p3-runtime/marshal-text-core.wat`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/roadmap_status.md`

**Interfaces:**
- Consumes: the Task 1 wrapper output and the exact package/world/member identity from the WIT source adapter.
- Produces: a parsed core module and a validated Component artifact for the bounded text shape; no host execution claim.

- [x] **Step 1: Write the failing assembly gate.**

  The script must pin the tool version, parse the checked-in core WAT, embed the checked-in WIT world, run `wasm-tools component new`, validate the Component, and assert that the Component WIT contains the declared text operation. It must reject an altered package/member identity and reject a core import containing a GC reference.

- [x] **Step 2: Run the gate before implementation.**

  ```bash
  bash examples/gc-p3-runtime/test_gc_marshal_text_component.sh
  ```

  Expected: failure until the wrapper, WIT fixture, and exact canonical import names are present.

- [x] **Step 3: Add the pinned WIT/core fixture and script.**

  Use the same package/world/member/hash facts as the parser-backed source adapter. Keep lower and lift fixtures separate if their canonical signatures differ. Require `wasm-tools parse`, `component embed`, `component new`, and `validate` to succeed; preserve stderr on every failure.

- [x] **Step 4: Run the assembly gate and residual gates.**

  ```bash
  bash examples/gc-p3-runtime/test_gc_marshal_text_component.sh
  bash src/build/test/check_gc_g5c_residual_gate.sh baseline
  ```

  Expected: the bounded Component fixture passes while `host_wit_marshalling` and G5c remain pending.

## Deferred Work

- Host-driven Wasmtime execution and Rust `wit-bindgen` runner.
- ARC/GC semantic-equivalence and cleanup matrix.
- General records, lists, `option`, `result`, variants, resources, async frames, and arbitrary producers.
- Wiring the wrapper into `do build` or changing the ARC-backed WIT route.
