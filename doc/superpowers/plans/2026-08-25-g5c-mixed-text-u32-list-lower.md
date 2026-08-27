# G5c Mixed Text + `list<u32>` Record Lower Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote exactly one synchronous `Writing { code u32, label text, payload [u32] }` host/WIT lower descriptor through the existing GC-first route.

**Architecture:** Reuse the measured `ManagedTextField` and parameterized `ManagedScalarListField` facts already used by the mixed `[u8]` route. Extend only the exact three-field mixed-shape guard and its emitter branch; keep the canonical boundary scalar-only and preserve ARC fallback for every unadmitted shape.

**Tech Stack:** Zig compiler, `.do` fixtures, WIT/component descriptors, Rust 2024 Wasmtime runner, Bash gates, `wasm-tools 1.255.0`, and the existing full regression harness.

**Spec:** `doc/superpowers/specs/2026-08-25-g5c-mixed-text-u32-list-lower-design.md`

## Global Constraints

- Keep GC-first v1 and the existing ARC fallback for unsupported shapes.
- Accept only the exact descriptor and source shape in the spec.
- Reuse `ManagedScalarListField`; do not add a second list representation or manifest schema kind.
- Keep the canonical import `(i32, i32, i32, i32, i32)` with no GC reference.
- Keep synchronous allocation/copy/call/free semantics and release acquired spans exactly once.
- Do not add or change `own<T>`, `borrow<T>`, `ref<T>`, `Option`, `Result`, async, resource, cancellation, or public syntax.
- Use only `wasm-tools 1.255.0`.
- Preserve `complete_rows=15 pending_rows=15` and the 79-fixture baseline until the new fixture has passed every gate.
- Preserve all unrelated dirty-worktree changes; do not reset, clean, commit, or push in this phase.

---

### Task 1: Add RED typed-plan and WAT tests

**Files:**

- Modify: `src/build/codegen_component_marshal_ops.zig`
- Modify: `src/build/codegen_component_marshal_wat.zig`
- Modify: `src/build/codegen_gc_plans_test.zig` only if the manifest-backed helper needs a named fixture

**Interfaces:**

- Consumes: existing measured mixed `[u8]` plan builders and the parameterized `ManagedScalarListField`.
- Produces: failing tests that require the same mixed route to preserve `u32` kind, stride `4`, and capacity `3`.

- [ ] **Step 1: Add a measured mixed `[u32]` plan test before production changes.**

  Copy the existing mixed text/byte-list plan fixture and change only the
  package marker, payload element to `.u32`, child facts to byte size/alignment
  `4`, list element stride to `4`, and capacity/accepted lengths to `3` and
  `&.{ 0, 1, 2, 3 }`. Assert:

  ```zig
  try std.testing.expect(memory_plan.record_managed_mixed_scalar_list_lower);
  const mixed = memory_plan.managed_mixed_scalar_list_lower orelse unreachable;
  try std.testing.expectEqual(ScalarListElementKind.u32, mixed.scalar_list.element_kind);
  try std.testing.expectEqual(@as(u32, 4), mixed.scalar_list.element_stride);
  try std.testing.expectEqual(@as(u32, 4), mixed.scalar_list.element_byte_size);
  try std.testing.expectEqual(@as(u32, 4), mixed.scalar_list.element_alignment);
  try std.testing.expectEqual(@as(u32, 3), mixed.scalar_list.capacity);
  ```

  Assert the ten operations are exactly:

  ```zig
  const expected = [_]MemoryOperation{
      .read_gc_span, .validate_linear_range, .cabi_realloc_alloc,
      .copy_to_linear, .validate_linear_range, .cabi_realloc_alloc,
      .copy_to_linear, .canonical_call, .cabi_realloc_free,
      .cabi_realloc_free,
  };
  try std.testing.expectEqualSlices(MemoryOperation, &expected, memory_plan.operations);
  ```

- [ ] **Step 2: Add the WAT RED assertions.**

  Use the same measured plan with `emit_sync_marshal_function` and require
  `array.get $do_u32`, `i32.store` and four `call $cabi_realloc` occurrences;
  require one canonical call and assert that the canonical call precedes the
  payload free, which precedes the label free. Also assert that the generated
  import/call text contains no GC reference parameter.

- [ ] **Step 3: Run the RED tests and verify the failure cause.**

  ```bash
  cd src
  zig test build/codegen_component_marshal_ops.zig --test-filter 'mixed.*u32'
  zig test build/codegen_component_marshal_wat.zig --test-filter 'mixed.*u32'
  ```

  Expected result before implementation: the plan guard returns no mixed route
  or the emitter rejects the `u32` element. Fix only test setup errors; leave
  the failure caused by the missing behavior.

### Task 2: Extend the exact mixed memory-plan admission

**Files:**

- Modify: `src/build/codegen_component_marshal_ops.zig`
- Test: `src/build/codegen_component_marshal_ops.zig`

**Interfaces:**

- Consumes: `managed_mixed_scalar_list_lower_for_root` and measured child facts.
- Produces: `ManagedMixedScalarListLower.scalar_list` with either the already
  admitted byte facts or the exact measured `u32` facts.

- [ ] **Step 1: Parameterize the payload guard by measured element kind.**

  Keep the root checks unchanged: direct three-field record, 20-byte root,
  `code@0`, text at `4`, payload at `12`, and text pointer/length `0/4`.
  Accept only these two payload cases:

  ```text
  u8:  element_kind=byte, element size/alignment/stride=1, capacity=4
  u32: element_kind=u32, element size/alignment/stride=4, capacity=3,
       measured core type=i32
  ```

  Return `null` for every other list element, capacity, allocation/free pair,
  root size, field order, or indirect layout. Keep the existing `[u8]` result
  unchanged.

- [ ] **Step 2: Run typed-plan tests.**

  ```bash
  cd src
  zig test build/codegen_component_marshal_ops.zig --test-filter mixed
  zig test build/codegen_gc_plans_test.zig --test-filter 'mixed|descriptor.*u32'
  ```

  Expected: both byte and u32 mixed plans pass, with their distinct kind,
  stride, element facts, and capacity.

### Task 3: Parameterize the mixed WAT lowerer

**Files:**

- Modify: `src/build/codegen_component_marshal_wat.zig`
- Test: `src/build/codegen_component_marshal_wat.zig`

**Interfaces:**

- Consumes: `ManagedMixedScalarListLower.scalar_list` from Task 2.
- Produces: one mixed emitter that selects `$do_bytes`/`array.get_s`/`i32.store8`
  for byte lists and `$do_u32`/`array.get`/`i32.store` for u32 lists.

- [ ] **Step 1: Remove the mixed emitter's byte-only guards and locals.**

  Replace fixed payload checks (`.byte`, stride `1`, size `1`, alignment `1`)
  with the measured `ManagedScalarListField` facts. Keep pointer/length offsets
  `0/4`, positive capacity, and exact root field checks.

- [ ] **Step 2: Select the payload GC type, load, store, stride, and allocation size.**

  Reuse the existing helpers `scalar_list_gc_type`,
  `scalar_list_load_instruction`, and `scalar_list_store_instruction`. Compute
  `copy_bytes = length * element_stride` with the existing checked i64/u32
  arithmetic before `cabi_realloc`; do not hard-code payload allocation size
  `1` for the u32 branch. Keep the capacity guard before allocation.

- [ ] **Step 3: Preserve cleanup order and test both variants.**

  Keep payload free before label free and keep the cleanup mask behavior for a
  trap after either allocation. Run:

  ```bash
  cd src
  zig test build/codegen_component_marshal_wat.zig --test-filter mixed
  ```

  Expected: existing mixed byte tests and the new u32 test are green.

### Task 4: Add the hash-pinned descriptor and fail-closed source boundaries

**Files:**

- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/run.zig`
- Modify: `doc/wit/gc_descriptor_manifest.json`
- Add: `examples/gc-p3-runtime/marshal-record-mixed-text-u32-list-lower-manifest-source.wit`
- Add: `examples/gc-p3-runtime/marshal-record-mixed-text-u32-list-lower-assembly.wit`
- Add: `doc/wit/gc_marshal_record_mixed_text_u32_list_lower_imports.wit`
- Add: `src/build/test/compile_ok/630_gc_wit_mixed_text_u32_list_lower_host_boundary.do`
- Add: `src/build/test/compile_err/631_gc_wit_mixed_text_u32_list_lower_async.do` and `.expect`
- Add: `src/build/test/compile_err/632_gc_wit_mixed_text_u32_list_lower_locator.do` and `.expect`
- Add: `src/build/test/compile_err/633_gc_wit_mixed_text_u32_list_lower_member.do` and `.expect`
- Add: `src/build/test/compile_err/634_gc_wit_mixed_text_u32_list_lower_reordered.do` and `.expect`
- Add: `src/build/test/compile_err/635_gc_wit_mixed_text_u32_list_lower_u8_payload.do` and `.expect`
- Add: `src/build/test/compile_err/636_gc_wit_mixed_text_u32_list_lower_text_payload.do` and `.expect`
- Add: `src/build/test/compile_err/637_gc_wit_mixed_text_u32_list_lower_extra_field.do` and `.expect`
- Add: `src/build/test/compile_err/638_gc_wit_mixed_text_u32_list_lower_record_name.do` and `.expect`

**Interfaces:**

- Consumes: the exact WIT/Do source in the spec and the measured descriptor loader.
- Produces: one descriptor id, one ordinary route, and source validation that
  fails before WAT on contract drift.

- [ ] **Step 1: Add the exact WIT sources and calculate the concatenated source/world hash.**

  Use the package/interface/record/function text from the spec. The loader
  hashes `source + "\\n" + world + "\\n"`, so verify the checked-in pair with:

  ```bash
  { cat examples/gc-p3-runtime/marshal-record-mixed-text-u32-list-lower-manifest-source.wit; printf '\\n'; cat doc/wit/gc_marshal_record_mixed_text_u32_list_lower_imports.wit; printf '\\n'; } | sha256sum
  ```

  Record that hash in the single new manifest entry; do not alter existing
  descriptor hashes or schema fields.

- [ ] **Step 2: Add boundary constants and route admission.**

  Add the descriptor id and expected field sequence `code u32`, `label text`,
  `payload [u32]` to `codegen_gc_wit_host_boundary.zig`; add the manifest-backed
  route in `run.zig` and a unit test that resolves the descriptor. Preserve
  exact synchronous `@host_func` validation.

- [ ] **Step 3: Add source-level positive and negative fixtures.**

  The positive fixture uses the exact Do declaration from the spec. Negative
  fixtures must cover async host marker, locator drift, member drift, reordered
  fields, `[u8]` payload, `text` payload, extra field, and a measured descriptor
  mismatch. Every `.expect` file names the fail-closed diagnostic and descriptor
  id; each failed build must leave no output artifact.

### Task 5: Prove Component, host behavior, and ARC/GC equivalence

**Files:**

- Add: `examples/gc-p3-runtime/ordinary-host-mixed-text-u32-list-lower-call.do`
- Add: fixed linear-memory ARC oracle under `examples/p3-runtime/rust-host-runner/src/bin/`
- Add: Rust 2024 Wasmtime host and equivalence runners
- Add: `examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lower_host.sh`
- Add: `examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lower_equivalence.sh`
- Add: `examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lower_negative.sh`
- Add: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_mixed_text_u32_list_lower.rs`
- Add: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_mixed_text_u32_list_lower_equivalence.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` only if a new bin needs an explicit target entry

**Interfaces:**

- Consumes: the manifest-backed Component and canonical five-word import.
- Produces: runtime evidence for values, callback count, allocation/free count,
  and equality between GC-generated and ARC oracle paths.

- [ ] **Step 1: Add the positive host call and runner assertions.**

  Construct `Writing{code = 7, label = "hello", payload = [10, 20, 5]}`.
  Assert one callback, exact values, two allocations, and two frees. Reject any
  canonical import containing a GC reference.

- [ ] **Step 2: Add the ARC oracle and equivalence runner.**

  Use the same WIT and five scalar import signature. Compare callback fields and
  cleanup/result counters from the compiler-generated GC Component and oracle;
  do not compare implementation-specific WAT text beyond ABI invariants.

- [ ] **Step 3: Run pinned Component validation and focused gates.**

  ```bash
  wasm-tools --version
  wasm-tools parse <core.wat> -o <core.wasm>
  wasm-tools component embed <wit-dir> <core.wasm> -o <embedded.wasm>
  wasm-tools component new <embedded.wasm> -o <component.wasm>
  wasm-tools validate <component.wasm>
  bash -n examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lower_host.sh
  bash -n examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lower_equivalence.sh
  bash -n examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lower_negative.sh
  ```

  The reported tool version must be `1.255.0`.

### Task 6: Promote the default route and complete the phase audit

**Files:**

- Modify: `src/build/test/check_gc_default_build_gate.sh`
- Modify: `src/build/test/check_gc_g5c_residual_gate.sh` only for fixture enumeration
- Modify: `src/build/test/check_gc_semantic_equivalence.sh` only for the new row
- Modify: `src/build/test/run_release_smoke.sh` only for fixture enumeration
- Modify: `doc/start_here.md`, `doc/roadmap_status.md`, `doc/pending_blocked.md`, `examples/gc-p3-runtime/README.md`

**Interfaces:**

- Consumes: all positive/negative/runtime evidence from Tasks 1–5.
- Produces: a 80-fixture default GC gate and a documented bounded promotion,
  while the migration inventory remains explicitly incomplete.

- [ ] **Step 1: Add the positive fixture only after focused gates pass.**

  Increase the default expected count from 79 to 80, require the GC marker and
  absence of `__arc_` for the new fixture, and leave all existing assertions
  unchanged.

- [ ] **Step 2: Synchronize docs without widening the claim.**

  Document the exact descriptor, fixed measurements, pinned toolchain, and
  rejection boundary. State explicitly that arbitrary aggregate lowering,
  async/resource, ownership syntax, and full G5c cutover remain pending.

- [ ] **Step 3: Run the complete verification set.**

  ```bash
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  cd src && zig build -Doptimize=ReleaseSmall
  ./src/build/test/run_release_smoke.sh
  bash src/build/test/check_gc_default_build_gate.sh
  bash src/build/test/check_gc_g5c_residual_gate.sh
  bash src/build/test/check_gc_semantic_equivalence.sh
  bash src/build/test/check_gc_migration_inventory.sh
  git diff --check
  ```

  The migration inventory is expected to retain its documented nonzero status
  with `complete_rows=15 pending_rows=15`. Inspect `git diff --stat` and
  `git status --short` before handoff; do not commit or push automatically.
