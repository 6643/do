# G5c Manifest-Driven Bounded Compiler Route Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Status (2026-08-22):** Completed for the four private synchronous
managed-record compiler routes. The follow-on default-route design now admits
only the separately gated C15-B lower and C16-C lift descriptors; this plan's
default-ARC constraint applies to all unadmitted descriptors, including
C15-D/C16-D.

**Goal:** Make the four private synchronous managed-record GC/WIT compiler routes derive their measured layout and host boundary from one validated descriptor manifest request, while preserving explicit opt-in behavior for the private route, the canonical no-GC-reference boundary, and the existing migration inventory.

**Architecture:** Keep schema 1 and add an optional `measured_layout` object to the existing descriptor entry. The manifest loader owns JSON shape validation and constructs an owned measured tree; the build-side adapter continues to verify source/hash/WIT identity and derives the host boundary from the resolved WIT member and Do tokens. The canonical marshal emitter consumes the validated request and no longer chooses measurement or field tables by descriptor-id; standalone probe wrappers retain their compatibility API and remain test scaffolding.

**Tech Stack:** Zig compiler and unit tests, checked-in JSON/WIT manifest, Core Wasm GC WAT generation, `wasm-tools 1.255.0`, shell integration gates, and existing Rust host/equivalence runners.

**Spec:** `doc/superpowers/specs/2026-08-21-g5c-manifest-driven-bounded-compiler-route-design.md`

## Global Constraints

- The route remains available only through explicit `--gc-wit-marshal <descriptor-id>` selection.
- Ordinary `@host_func` compilation remains ARC-backed for unadmitted shapes; the follow-on default route separately admits only the verified C15-B/C16-C descriptors.
- Only the four managed-record descriptors are migrated in this slice.
- Async functions, `future`, `stream`, resources, `own`, `borrow`, `option`, `result`, variants, tuples, producer expressions, and unmeasured aggregates remain fail-closed.
- The canonical boundary may contain core scalar words and linear-memory pointer/length pairs only; GC references are rejected.
- No `own<T>`, `borrow<T>`, `ref<T>`, `Option`, `Result`, or new source syntax is introduced.
- The 15-row migration inventory is not edited and must still report `complete_rows=15 pending_rows=15` with its documented non-zero status.
- Existing standalone probe functions that accept a caller-supplied `marshal.MeasuredNode` remain source-compatible.
- Existing user dirty changes are preserved; this slice is not committed or pushed without explicit authorization.
- The only accepted toolchain baseline is `wasm-tools 1.255.0`.

---

### Task 1: Add Manifest `measured_layout` Model and Decoder

**Files:**
- Modify: `src/wit/descriptor_manifest.zig`
- Modify: `src/wit/descriptor_manifest_test.zig`
- Modify: `src/build/codegen_component_descriptor_manifest.zig`
- Modify: `src/build/codegen_gc_plans_test.zig`
- Modify: `doc/wit/gc_descriptor_manifest.json`

**Interfaces:**
- `descriptor_manifest.Descriptor.measured_layout: ?MeasuredLayout` is optional so existing descriptors remain parseable.
- `descriptor_manifest.MeasuredLayout` owns a recursively allocated `MeasuredNode`-shaped tree with root kind, byte size, alignment, ordered fields, ordered children, scalar core type, text pointer/length offsets, and allocation/free names.
- `descriptor_manifest.parse` rejects malformed or inconsistent measurement data before returning `Parsed`.
- `codegen_component_descriptor_manifest.load_request` obtains the measured tree from the descriptor and no longer requires a measurement argument for the real compiler route; the existing explicit-measurement wrapper remains available for standalone probes until Task 3.

- [x] **Step 1: Write the failing parser tests.** Add tests to `src/wit/descriptor_manifest_test.zig` for one valid three-field record measurement, a missing measurement on an admitted descriptor, an invalid kind/field object, child-count drift, field-order/offset drift, and an invalid allocation/free name. Assert the named manifest error rather than a generic JSON error.

```zig
test "descriptor manifest decodes measured record layout" {
    var parsed = try manifest.parse(std.testing.allocator, valid_source_with_measured_layout);
    defer parsed.deinit(std.testing.allocator);
    const layout = parsed.document.descriptors[0].measured_layout.?;
    try std.testing.expectEqualStrings("record", layout.kind);
    try std.testing.expectEqual(@as(usize, 3), layout.fields.len);
    try std.testing.expectEqualStrings("note", layout.fields[2].name);
}

test "descriptor manifest rejects measured child count drift" {
    try std.testing.expectError(error.DescriptorMeasurementInvalid,
        manifest.parse(std.testing.allocator, measured_layout_with_missing_child));
}
```

- [x] **Step 2: Run the focused tests and verify RED.** Run `cd src && zig test wit/descriptor_manifest_test.zig`. Expected result: the new tests fail because the optional model, parser, and validation error are not implemented; existing manifest tests remain green.

- [x] **Step 3: Implement the minimal owned model and parser.** Add explicit enums/records for the bounded kinds and numeric fields, parse optional `measured_layout`, allocate every dynamic slice through the parser allocator, and extend `Parsed.deinit` to release nested fields/children. Validate kind-specific fields, ordered field offsets and sizes, child count, scalar `core_type`, text pointer/length offsets, and exact `cabi_realloc` allocation/free names. Return `DescriptorMeasurementMissing` for an admitted descriptor without the field and `DescriptorMeasurementInvalid` for malformed or inconsistent values.

- [x] **Step 4: Decode into the existing marshal shape and run GREEN.** Add a single adapter in `codegen_component_descriptor_manifest.zig` that converts the owned manifest model to `marshal.MeasuredNode`, then run `cd src && zig test wit/descriptor_manifest_test.zig` and the descriptor-loader tests in `build/codegen_gc_plans_test.zig`. Expected result: valid data is structurally identical to the current four hand-built measurements; all malformed cases fail before plan construction.

- [x] **Step 5: Add measurements to the four manifest entries and re-run focused tests.** Serialize the existing hand-built layouts without changing any source hash, WIT identity, or non-migrated descriptor. Verify JSON parsing and `git diff --check`; do not edit the 15-row inventory.

### Task 2: Derive the Host Boundary from Resolved WIT and Do Tokens

**Files:**
- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/codegen_component_descriptor_manifest.zig`
- Modify: `src/build/codegen_component_manifest_route.zig`
- Modify: `src/build/codegen_component_manifest_route_test.zig`
- Modify: `src/build/codegen_gc_plans_test.zig`
- Add or modify: `src/build/test/compile_ok/564_gc_wit_managed_record_host_boundary.do`, `565_gc_wit_managed_record_host_boundary.do`, `566_gc_wit_managed_record_lift_host_boundary.do`, and `581_gc_wit_managed_record_lift_multi_host_boundary.do` only where the current boundary validator requires updated diagnostics.

**Interfaces:**
- Add a validator entry point that consumes the loaded manifest descriptor, resolved `wit_registry.ValueMember`, measured tree, and token slice; it returns a bounded `HostBoundary`/marshal request or a named error.
- The validator derives field count/order/name and Do scalar/text shapes from the resolved WIT member and the actual `@host_func` declaration.
- `codegen_gc_wit_host_boundary` no longer switches on descriptor ids to select C15/C16 field tables.

- [x] **Step 1: Write RED tests for data-driven boundary validation.** Add focused tests for accepting local Do names `Reading` and `Writing` against the same WIT record, rejecting a reordered field, rejecting a changed field type, rejecting an async marker, rejecting locator/member drift, rejecting duplicate/extra host declarations, and rejecting a measured GC reference.

```zig
test "managed record boundary accepts a local Do name from WIT shape" {
    const boundary = try validate_manifest_host_boundary(valid_tokens, loaded_request);
    try std.testing.expectEqual(@as(usize, 3), boundary.fields.len);
}
```

- [x] **Step 2: Run the focused boundary tests and verify RED.** Run `cd src && zig test build/codegen_component_manifest_route_test.zig` with the new tests selected by the existing test filter. Expected result: the new tests fail against the descriptor-id field-table implementation.

- [x] **Step 3: Implement WIT-derived validation with guards.** Read the resolved member direction and function shape first, require exactly one synchronous declaration with the expected parameter/result arity, compare each field in order against the resolved WIT record, and validate measured root/child offsets before constructing the request. Reject unsupported WIT kinds and any canonical reference before calling an emitter.

- [x] **Step 4: Remove compiler-route fixed field tables.** Delete only the real-route descriptor-id field-table branches and pass the validated field descriptors into existing marshal operations. Keep named compatibility helpers used solely by standalone probes until Task 3, with comments identifying them as test scaffolding rather than ABI authority.

- [x] **Step 5: Run GREEN boundary and loader tests.** Run `cd src && zig test build/codegen_component_manifest_route_test.zig` and the relevant `build/codegen_gc_plans_test.zig` tests. Confirm all existing negative diagnostics remain fail-closed before WAT emission.

### Task 3: Migrate the Four Compiler Routes and Keep Probe Compatibility

**Files:**
- Modify: `src/build/codegen_component_descriptor_manifest.zig`
- Modify: `src/build/codegen_component_manifest_route.zig`
- Modify: `src/build/codegen_gc_wit_marshal.zig`
- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/codegen_component_marshal_plan.zig` only if the decoded tree needs a narrow conversion helper
- Add or modify: the four `src/build/test/compile_ok` fixtures and their matching `compile_err` fixtures
- Preserve: standalone `src/build/gc_marshal_*_probe.zig` APIs that explicitly pass `marshal.MeasuredNode`

**Interfaces:**
- Real compiler path: `emit_sync_marshal_module_from_manifest_with_options(io, allocator, root, manifest, descriptor_id, canonical_u64_arg, emit_realloc_counters)` loads measurement from the manifest and validates host boundary from tokens.
- Standalone probe path: existing `emit_sync_marshal_module_from_manifest(..., measured, canonical_u64_arg)` remains available under a clearly separate name or adapter and is not used as the compiler source of truth.
- Emitter receives one validated `marshal_route.Request`; no descriptor-id measurement switch remains in the real path.

- [x] **Step 1: Add route-level RED assertions.** Extend route tests to call the real compiler entry with each of the four descriptor ids and no caller-supplied measurement. Assert that the route refuses a missing `measured_layout` and that malformed manifest data fails before output allocation.

- [x] **Step 2: Run route tests and capture RED.** Run `cd src && zig test build/codegen_component_manifest_route_test.zig`; expected failure is the old required measurement argument or the old descriptor switch, not a parser or test typo.

- [x] **Step 3: Wire the decoded measurement and validated boundary.** Change only the real route call chain to use the descriptor-owned measurement and boundary result. Preserve canonical imports, GC-owned result/lower operations, realloc counter behavior, and the existing `canonical_u64_arg` test hook.

- [x] **Step 4: Update the four compiler fixtures and negative fixtures.** Ensure the four positive fixtures select the explicit GC route, while async, locator mismatch, field-order mismatch, and field-type mismatch fixtures still fail before WAT generation. Do not broaden accepted types.

- [x] **Step 5: Run GREEN route and compiler tests.** Run the focused route tests, the four compiler test cases, and each negative fixture. Compare emitted canonical signatures and key WAT fragments against the pre-migration expectations.

### Task 4: Migrate Behavioral Gates Without Changing the Contract

**Files:**
- Modify: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_compiler_host.sh`
- Modify: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_compiler_equivalence.sh`
- Modify: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_compiler_host.sh`
- Modify: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_compiler_equivalence.sh`
- Modify: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_host.sh`
- Modify: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_equivalence.sh`
- Modify: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_multi_compiler_host.sh`
- Modify: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_multi_compiler_equivalence.sh`
- Modify: matching negative/default scripts and `examples/gc-p3-runtime/README.md`

**Interfaces:**
- Host gates continue to observe the current pinned values, including C16-D `value=17`.
- Equivalence gates continue to report ARC/GC `17/17` where already specified.
- Negative gates require no WAT artifact on rejection.
- Default gate proves ordinary compilation without `--gc-wit-marshal` still emits the ARC route for unadmitted descriptors; the separately gated follow-on default route covers only C15-B lower and C16-C lift.

- [x] **Step 1: Add a gate assertion for manifest-owned measurement.** Make one compiler host gate inspect the generated route invocation and fail if an independent measurement constructor is still passed through the compiler path.

- [x] **Step 2: Run that gate and verify RED against the old route.** Execute the focused managed-record host gate; expected failure identifies the old caller-supplied measurement path.

- [x] **Step 3: Update all four host/equivalence gates.** Replace only route setup and artifact paths as required by the new entry point; preserve host values, counters, canonical imports, and runner commands.

- [x] **Step 4: Preserve rejection/default gates.** Verify each rejected input fails before WAT output, ordinary host compilation remains ARC-backed for unadmitted descriptors, and the follow-on C15-B/C16-C default gates retain their GC route. Keep async/resource/unsupported-shape failures unchanged.

- [x] **Step 5: Run all C15/C16 compiler gates.** Run the focused scripts and record expected output, including `value=17`, `17/17`, no-GC-reference checks, and no generated artifact on failure.

### Task 5: Full Verification, Documentation, and Inventory Audit

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `examples/gc-p3-runtime/README.md`
- Preserve: `doc/wit/gc_descriptor_manifest.json` measurements and all migration inventory rows

**Interfaces:**
- Documentation states that this route is opt-in, synchronous, bounded to four managed-record descriptors, manifest-measured, and not the full default ARC cutover; the separately gated C15-B/C16-C promotion is called out as the only current default exception.
- Verification records the exact toolchain `wasm-tools 1.255.0` and the expected migration inventory result.

- [x] **Step 1: Run focused Zig verification.** Run descriptor manifest tests, route tests, GC plan tests, and the compiler's focused boundary tests. Expected result: all focused tests pass.

- [x] **Step 2: Run all behavioral gates.** Run all C15/C16 host, equivalence, negative, and default scripts with `wasm-tools --version` first; expected version is `1.255.0` and every required gate passes.

- [x] **Step 3: Run the repository verification commands.** Run `cd src && zig build -Doptimize=ReleaseSmall`, `./src/build/test/run_tests.sh`, release smoke, and `git diff --check`. Record exact pass/fail/skip counts and preserve any documented expected non-zero command.

- [x] **Step 4: Run the migration inventory audit.** Run `bash ./src/build/test/check_gc_migration_inventory.sh` and verify `complete_rows=15 pending_rows=15`; retain its documented exit status and do not edit the inventory to make the command green.

- [x] **Step 5: Synchronize documentation and perform completion audit.** Update only the listed docs with verified results, search the real route for descriptor-id measurement/field-table switches, verify standalone probe compatibility, and inspect `git diff --check` plus relevant source diffs. Do not commit or push in this slice without explicit user authorization.

## Verification closeout (2026-08-21)

- `wasm-tools --version`: `wasm-tools 1.255.0 (76e20611d 2026-07-30)`.
- The four compiler host/equivalence pairs passed: managed lower, managed
  lower multi, managed lift, and managed lift multi. Observed values were
  `code=7`, `label=hello`, `note=world`, lift `12`, and multi-lift `17`;
  equivalence remained `17/17` where applicable.
- The four compiler boundary negative/default gates passed. Async and locator
  mismatch inputs were rejected before WAT output; ordinary host compilation
  remained ARC-backed.
- `cd src && zig test main.zig`: `598/598`; `cd src && zig build
  -Doptimize=ReleaseSmall`: passed; `./src/build/test/run_tests.sh`:
  `pass=1279 fail=0 skip=3`; release smoke: all 8 checks passed; and
  `git diff --check`: passed.
- `bash ./src/build/test/check_gc_migration_inventory.sh` intentionally exits
  1 and reports `complete_rows=15 pending_rows=15`. The inventory was not
  edited. The executable bit is not present, so the documented `bash` form is
  the reproducible invocation.
- The route remains explicit opt-in, synchronous, bounded to four descriptors,
  manifest-measured, WIT-derived at the host boundary, and not a default ARC
  cutover. Async, resource, general aggregate, ownership syntax, and full G5c
  migration remain fail-closed or pending.
