# Synchronous `map<u32,u32>` Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the first real manifest-backed Component/WIT map gate for the exact synchronous `map<u32,u32>` lower and lift shapes, without claiming support for other map values, async calls, or Stream buffering.

**Architecture:** Keep WIT `map` as a distinct model type and use the existing pair-list canonical representation. Manifest measurement facts are parsed into the existing `MapLayoutMeasurement`, the existing marshal registry and WAT emitter produce the GC map value, and a narrow host-boundary admission validates generated `HashMap<u32, u32>` declarations before emission. A Rust/Wasmtime runner verifies the assembled Component's synchronous lower/lift calls and cleanup markers.

**Tech Stack:** Zig 0.16.0, Do compiler, WIT parser/manifest loader, WAT/WIT Component fixtures, `wasm-tools 1.258.0`, Wasmtime CLI 48.0.1, Rust Wasmtime 48.0.1.

**Descriptor provenance:** `doc/wit/gc_descriptor_manifest.json` intentionally retains its top-level `wasm-tools 1.255.0` value as historical measurement provenance. The current-only toolchain lock is 1.258.0; the manifest value is not rewritten without remeasuring every descriptor.

**Spec:** `doc/superpowers/specs/2026-08-30-map-toolchain-zig-harness-design.md`; `doc/superpowers/specs/2026-08-30-canonical-abi-operation-lifetime-design.md`

## Global Constraints

- Only the exact synchronous `map<u32,u32>` lower and lift paths are admitted in this plan.
- Keep `map<K,V>` distinct from `list<tuple<K,V>>`; do not rewrite one into the other in the WIT model.
- Map keys remain scalar WIT keys; resource and composite keys stay rejected.
- Pair-list `ptr,len` data is copied within the operation frame and is never retained across an async suspension or Stream poll.
- Do not change Do GC, value semantics, public ownership syntax, or the current-only toolchain policy.
- Preserve unrelated dirty worktree changes; do not run reset, checkout, clean, or broad formatting.

---

### Task 1: Add the manifest map measurement contract

**Files:**
- Modify: `src/wit/descriptor_manifest.zig`
- Modify: `src/wit/descriptor_manifest_test.zig`

**Interfaces:**
- Consumes: existing `MeasuredNode`, `MeasurementKind`, and `MapLayoutMeasurement` field names.
- Produces: parsed `MeasurementKind.map`, `MeasuredNode.map_key`, and `MeasuredNode.map_value` facts for a pair-list map.

- [x] **Step 1: Write the failing parser test.**

  Add a JSON descriptor containing:

  ```json
  "measured_layout": {
    "kind": "map", "byte_size": 8, "alignment": 4,
    "pointer_offset": 0, "length_offset": 4,
    "element_byte_size": 8, "element_stride": 8, "element_alignment": 4,
    "key": {"offset": 0, "byte_size": 4, "alignment": 4},
    "value": {"offset": 4, "byte_size": 4, "alignment": 4},
    "capacity": 2, "accepted_lengths": [0, 1, 2],
    "allocation": "cabi_realloc", "free": "cabi_realloc"
  }
  ```

  Assert that parsing returns `MeasurementKind.map` and preserves both field offsets. Add a malformed case with a missing `value` object and expect `DescriptorMeasurementInvalid`.

- [x] **Step 2: Run the focused test to verify the expected red failure.**

  Run: `cd src && zig test wit/descriptor_manifest_test.zig --test-filter 'map measurement'`

  Expected: FAIL because `map` is not yet a manifest measurement kind.

- [x] **Step 3: Implement the smallest parser change.**

  Add a manifest-owned `MeasuredMapField` containing `offset`, `byte_size`, and `alignment`; add optional `map_key` and `map_value` fields to `MeasuredNode`; recognize `"map"`; parse and validate the map container and both fields against the container size. Require pair-list storage actions, non-empty accepted capacity, `element_byte_size == element_stride == 8`, and `element_alignment == 4` for this first shape.

- [x] **Step 4: Run the focused parser tests.**

  Run: `cd src && zig test wit/descriptor_manifest_test.zig --test-filter 'map measurement'`

  Expected: PASS for the valid map and the malformed field case.

### Task 2: Convert manifest map facts into the existing marshal plan

**Files:**
- Modify: `src/build/codegen_component_descriptor_manifest.zig`
- Modify: `src/build/codegen_component_manifest_route_test.zig`
- Modify: `src/build/codegen_gc_plans_test.zig`

**Interfaces:**
- Consumes: `descriptor_manifest.MeasuredNode.map_key/map_value` and `wit_abi_layout.MapLayoutMeasurement`.
- Produces: manifest-owned `marshal.MeasuredNode.layout.map` with two measured children and a usable `SyncValuePlan`.

- [x] **Step 1: Write the failing manifest conversion test.**

  Add a unit test beside `convert_manifest_measurement` that constructs a manifest map node and asserts conversion produces a `marshal.MeasuredLayout.map` with two children and key/value offsets. Keep the manifest-owned route assertion in Task 4 after the checked-in descriptor exists.

- [x] **Step 2: Run the conversion test to verify the expected red failure.**

  Run: `cd src && zig test build/codegen_component_descriptor_manifest.zig --test-filter 'manifest.*map'`

  Expected: FAIL with `DescriptorMeasurementInvalid` or `UnsupportedMarshalShape` because the manifest converter has no map branch.

- [x] **Step 3: Implement the map conversion branch.**

  In `convert_manifest_measurement`, require exactly two children, map key/value facts, and convert them into `wit_layout.MapFieldMeasurement`; emit `marshal.MeasuredLayout.map` with the parsed pointer/length, pair size/stride/alignment, key/value offsets, capacity, accepted lengths, and allocation/free actions. Keep ownership of all allocated children consistent with the existing `deinit_marshal_measured_node` path.

- [x] **Step 4: Run focused marshal plan tests.**

  Run: `cd src && zig test build/codegen_component_descriptor_manifest.zig --test-filter 'manifest.*map' && zig test build/codegen_gc_plans_test.zig --test-filter 'map'`

  Expected: PASS for both directions and no regression in existing record/list manifest tests.

### Task 3: Admit the exact Do map host boundary

**Files:**
- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/codegen_component_descriptor_manifest.zig`
- Modify: `src/build/codegen_gc_plans_test.zig`
- Create: `src/build/test/compile_ok/746_gc_wit_map_u32_u32_host_boundary.do`

**Interfaces:**
- Consumes: WIT root map type and the existing host declaration scanner.
- Produces: fail-closed validation for `HashMap<u32, u32>` as a single synchronous host parameter/result.

- [x] **Step 1: Write the failing host-boundary acceptance test.**

  Use a Do source with `HashMap = @lib("hash_map.do", HashMap)` and `write = @host_func("demo:marshal-map-u32-u32/api@1.0.0", "write", (HashMap<u32, u32>) -> nil)`. Assert that manifest-backed validation accepts it; add a lift declaration returning `HashMap<u32, u32>` and assert acceptance as well.

- [x] **Step 2: Run the focused host test to verify the expected red failure.**

  Run: `cd src && zig test build/codegen_gc_plans_test.zig --test-filter 'map host boundary'`

  Expected: FAIL with `UnsupportedGcWitHostDescriptor`, `GcWitHostRecordMismatch`, or `GcWitHostSignatureMismatch` because map roots are not currently admitted.

- [x] **Step 3: Implement narrow map shape matching.**

  Add `lower_map` and `lift_map` host boundary shapes with an owned expected type string. Match exactly `HashMap<u32, u32>` at the parameter or result position, require one parameter for lower and zero for lift, and require `nil` for lower results. Add the map descriptor to the explicit admission table; leave all other map key/value combinations rejected.

- [x] **Step 4: Run focused positive and negative tests.**

  Run: `cd src && zig test build/codegen_gc_wit_host_boundary.zig --test-filter 'map' && zig test build/codegen_gc_plans_test.zig --test-filter 'map host boundary'`

  Expected: valid lower/lift declarations pass; wrong key, wrong value, async marker, extra declaration, and wrong locator fail before WAT emission.

### Task 4: Add checked-in map WIT/manifest and Component fixtures

**Files:**
- Create: `examples/gc-p3-runtime/marshal-map-u32-u32-lower-manifest-source.wit`
- Create: `examples/gc-p3-runtime/marshal-map-u32-u32-lift-manifest-source.wit`
- Create: `doc/wit/gc_marshal_map_u32_u32_lower_imports.wit`
- Create: `doc/wit/gc_marshal_map_u32_u32_lift_imports.wit`
- Modify: `doc/wit/gc_descriptor_manifest.json`
- Create: `src/build/test/compile_err/747_gc_wit_map_wrong_value.do`
- Create: `src/build/test/compile_err/747_gc_wit_map_wrong_value.expect`

**Interfaces:**
- Consumes: Tasks 1-3 descriptor and host-boundary contracts.
- Produces: two hash-pinned descriptor entries (one lower `write` member and one lift `read` member) and deterministic negative drift coverage.

- [x] **Step 1: Add the exact WIT sources and worlds.**

  Use package `demo:marshal-map-u32-u32@1.0.0`, interface `api`, and two single-direction members: lower `write: func(value: map<u32, u32>);` and lift `read: func() -> map<u32, u32>;`. Each world imports `api` and exports `run`/`stats` for the assembled probe. Compute each SHA-256 from its concatenated source/world bytes using the repository's existing manifest convention.

- [x] **Step 2: Add measured lower/lift descriptor entries.**

  Add lower and lift ids, `map_abi` `{ "key": "u32", "value": "u32", "representation": "pair-list" }`, the 8-byte map layout, canonical import module `demo:marshal-map-u32-u32/api@1.0.0`, and the exact source hash for each source/world pair.

- [x] **Step 3: Add the wrong-value negative fixture.**

  Keep the same locator but declare `HashMap<u32, text>`; its expected diagnostic must identify the map host signature mismatch and the fixture must be rejected before WAT output.

- [x] **Step 4: Run manifest integrity checks.**

  Run: `cd src && zig test wit/descriptor_manifest_test.zig --test-filter 'map' && zig test main.zig --test-filter 'map'`; then run the single negative fixture with `./bin/do build src/build/test/compile_err/747_gc_wit_map_wrong_value.do -o /tmp/do-map-negative.wat` and verify the command exits non-zero with the expected diagnostic substring. `main.zig` is the supported aggregate test entrypoint under Zig 0.16; direct tests that import outside their module path are not valid invocations.

  Expected: descriptor parsing, source-hash verification, and negative compiler admission pass with the current toolchain.

### Task 5: Execute the synchronous map Component gate

**Files:**
- Create: `examples/gc-p3-runtime/map-u32-u32-lower.do`
- Create: `examples/gc-p3-runtime/map-u32-u32-lift.do`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_map_u32_u32.rs`
- Create: `examples/gc-p3-runtime/test_gc_marshal_map_u32_u32_manifest_host.sh`
- Modify: `src/build/test/test_cases.zig`
- Modify: `src/build/test/test_harness.zig`

**Interfaces:**
- Consumes: manifest-owned map marshal route and current-only Toolchain Adapter commands.
- Produces: Rust/Wasmtime evidence for synchronous lower/lift map values, one host call per operation, and exactly-once temporary span cleanup.

- [x] **Step 1: Add the Do entry fixtures and Rust host oracle.**

  The lower fixture constructs a two-entry `HashMap<u32,u32>` and calls the admitted host once. The lift fixture calls the admitted host and reads the two returned entries. The Rust runner must assert keys `7, 9`, values `70, 90`, one lower/lift call, and equal allocation/free counters.

- [x] **Step 2: Run the gate red if assembly is incomplete.**

  Run: `bash examples/gc-p3-runtime/test_gc_marshal_map_u32_u32_manifest_host.sh`

  Expected before the completed route: failure at descriptor admission or Component assembly, never a silent pass.

- [x] **Step 3: Wire the gate through the Zig harness.**

  Add a table-driven `map_sync_component` case that invokes the same typed toolchain adapter and Rust runner, captures stdout/stderr/exit status, and cleans its temporary directory on success or failure.

- [x] **Step 4: Run focused and full verification.**

  Run: `cd src && zig test main.zig --test-filter 'map'`; `bash examples/gc-p3-runtime/test_gc_marshal_map_u32_u32_manifest_host.sh`; `cd src && zig build test --summary all`.

  Expected: focused map tests and the full current harness pass; existing map Core probe remains green; no async/Stream capability is claimed.
