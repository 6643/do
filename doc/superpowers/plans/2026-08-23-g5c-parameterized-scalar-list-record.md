# G5c Parameterized Scalar-List Record Lowering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with checkpoints.

**Goal:** Unify the existing synchronous record { u32, list<u8|u32> } lower routes behind one measured scalar-list specification without changing the external manifest schema or canonical ABI.

**Architecture:** Keep list and byte_list as strict manifest input kinds, normalize both into one internal ManagedScalarListField, and emit one WAT copy/alloc/call/free sequence driven by element kind and measured capacity. The route remains exact-descriptor based; unadmitted shapes retain their current rejection or ARC fallback.

**Tech Stack:** Zig compiler modules, WAT emission, checked-in manifest fixtures, zig test, shell gates, wasm-tools 1.255.0, Rust/Wasmtime runners.

**Spec:** doc/superpowers/specs/2026-08-23-g5c-parameterized-scalar-list-record-design.md

## Global Constraints

- Do not change the manifest JSON schema or canonical Component ABI.
- Admit only synchronous @host_func record lower with exactly u32 plus one scalar list.
- Allow only u8 and u32 list elements; capacity comes from validated measured facts.
- Do not add runtime-length generalization, list lift, async/resource/borrowed lowering, or ownership syntax.
- Preserve all existing uncommitted work; stage only files belonging to this plan.
- Use ./src/build/test/run_tests.sh for the full regression.

---

### Task 1: Lock the shared route with failing tests

Files:
- Modify: src/build/codegen_component_marshal_ops.zig
- Modify: src/build/codegen_component_marshal_wat.zig
- Modify: src/build/codegen_component_manifest_route_test.zig

Interfaces:
- Consumes the existing byte-list and u32-list record plan fixtures.
- Produces assertions for one route with kind, stride, and measured capacity.

Steps:

- [ ] Write tests that require MemoryPlan.record_managed_scalar_list_lower and managed_scalar_list_field. Assert u8 has kind byte, stride 1, capacity 4; assert u32 has kind u32, stride 4, capacity 3. Assert both operation arrays are read_gc_span, validate_linear_range, cabi_realloc_alloc, copy_to_linear, canonical_call, cabi_realloc_free.
- [ ] Assert byte WAT contains exactly array.get_s $do_bytes and i32.store8, while u32 WAT contains array.get $do_u32 and i32.store. Assert each has one canonical call and alloc/free ordering.
- [ ] Run:
~~~~bash
cd src && zig test build/codegen_component_marshal_ops.zig
cd src && zig test build/codegen_component_manifest_route_test.zig
~~~~
Expected result before implementation: compile failure because the shared type and fields do not exist. Do not write production code before observing this intended failure.
- [ ] Commit only the red-test changes with subject: test: specify shared scalar-list record route.

### Task 2: Normalize manifest measurements and retain scalar-list facts

Files:
- Modify: src/build/codegen_component_marshal_plan.zig
- Modify: src/build/codegen_component_descriptor_manifest.zig
- Test: src/wit/descriptor_manifest_test.zig
- Test: src/build/codegen_gc_plans_test.zig

Interfaces:
- Consumes descriptor_manifest.MeasuredNode from both external kinds list and byte_list.
- Produces marshal.MeasuredFacts element_byte_size, element_alignment, and capacity for both kinds.

Steps:

- [ ] Add nullable element_byte_size, element_alignment, and capacity to marshal.MeasuredFacts. Populate them in both list and byte_list branches of bind_measured_node; leave scalar/text/record facts unchanged.
- [ ] Extract one private scalar-list conversion helper in codegen_component_descriptor_manifest.zig. Keep the external JSON kinds and strict u8/u32 validation, but materialize exactly one scalar child for each kind and return one internal measured shape.
- [ ] Add tests for capacities 4 and 3 and for malformed stride/alignment/capacity rejection before WAT.
- [ ] Run:
~~~~bash
cd src && zig test build/codegen_gc_plans_test.zig
cd src && zig test wit/descriptor_manifest_test.zig
~~~~
- [ ] Commit only these files with subject: refactor: normalize scalar-list measured facts.

### Task 3: Replace duplicate operation-plan state

Files:
- Modify: src/build/codegen_component_marshal_ops.zig
- Modify: src/build/codegen_component_marshal_module.zig
- Test: src/build/codegen_gc_plans_test.zig

Interfaces:
- Consumes measured scalar-list facts from Task 2.
- Produces ScalarListElementKind, ManagedScalarListField, and one optional field in MemoryPlan.

Required interface:
~~~~zig
pub const ScalarListElementKind = enum { byte, u32 };

pub const ManagedScalarListField = struct {
    field_index: u32,
    pointer_offset: u32,
    length_offset: u32,
    element_kind: ScalarListElementKind,
    element_byte_size: u32,
    element_alignment: u32,
    element_stride: u32,
    capacity: u32,
};
~~~~

Steps:

- [ ] Replace ManagedByteListField and ManagedU32ListField and their flags with the shared types above.
- [ ] Implement managed_scalar_list_field_for_root. Require a two-field direct record, field 0 u32, field 1 one-element scalar list, pointer/length 0/4, container 8 bytes with alignment 4, matching element facts, cabi_realloc actions, and positive capacity. Return null for all other shapes.
- [ ] Replace duplicate operation constants with one record_managed_scalar_list_lower_operations array preserving read, validation, allocation, copy, call, free order.
- [ ] Update marshal_module.zig to use the one flag. Emit $do_u32 only when the spec element kind is u32; retain $do_bytes and existing lift behavior.
- [ ] Run:
~~~~bash
cd src && zig test build/codegen_component_marshal_ops.zig
cd src && zig test build/codegen_gc_plans_test.zig
~~~~
Expected result: Task 1 tests pass and invalid shapes remain rejected.
- [ ] Commit only implementation and focused tests with subject: refactor: parameterize scalar-list record operations.

### Task 4: Emit one parameterized WAT lowerer

Files:
- Modify: src/build/codegen_component_marshal_wat.zig
- Modify: src/build/codegen_component_manifest_route_test.zig
- Test: src/build/codegen_component_marshal_wat.zig

Interfaces:
- Consumes ManagedScalarListField.
- Produces emit_record_lower_managed_scalar_list with unchanged ABI and lifetime order.

Mapping:
~~~~text
byte -> $do_bytes, array.get_s $do_bytes, i32.store8, stride 1
u32  -> $do_u32,   array.get $do_u32,   i32.store,  stride 4
~~~~

Steps:

- [ ] Add small mapping helpers for GC array type, load instruction, store instruction, and use the measured stride/capacity from the field spec.
- [ ] Implement emit_record_lower_managed_scalar_list. Keep record field paths and canonical arguments code, payload pointer, payload length. Guard length and multiplication, allocate, guard linear span, copy, call, and free exactly once.
- [ ] Delete only the two duplicate managed byte/u32 emitters and update emit_record_lower dispatch. Do not alter generic top-level list emitters or record lift.
- [ ] Run:
~~~~bash
cd src && zig test build/codegen_component_marshal_wat.zig
cd src && zig test build/codegen_component_manifest_route_test.zig
~~~~
- [ ] Commit only emitter and route-test changes with subject: refactor: share scalar-list record WAT emitter.

### Task 5: Synchronize gates and phase documentation

Files:
- Modify: src/build/test/check_gc_default_build_gate.sh
- Modify: src/build/test/check_gc_g5c_residual_gate.sh
- Modify: src/build/test/check_gc_semantic_equivalence.sh
- Modify: CHANGELOG.md
- Modify: doc/start_here.md
- Modify: doc/roadmap_status.md
- Modify: doc/pending_blocked.md
- Modify: doc/host_abi_blockers.md

Steps:

- [ ] Replace references to removed duplicate flags with the shared route marker where generated WAT is inspected. Keep default fixture count 75 and residual inventory complete_rows=15 pending_rows=15.
- [ ] Record the shared route, capacities u8=4/u32=3, synchronous-only boundary, and remaining non-goals. Do not add a descriptor.
- [ ] Run the existing focused host, equivalence, negative, default, and residual gates using the repository paths already called by run_tests.sh. Preserve any nonzero gate output.
- [ ] Commit only gate and documentation changes with subject: docs: record shared scalar-list route.

### Task 6: Full verification and completion audit

Files:
- Inspect all files changed by Tasks 1-5 and git status --short.

Steps:

- [ ] Run focused Zig tests:
~~~~bash
cd src && zig test build/codegen_component_marshal_ops.zig
cd src && zig test build/codegen_component_marshal_wat.zig
cd src && zig test build/codegen_component_manifest_route_test.zig
cd src && zig test build/codegen_gc_plans_test.zig
~~~~
- [ ] Run:
~~~~bash
./src/build/test/run_tests.sh
cd src && zig build -Doptimize=ReleaseSmall
./src/build/test/run_release_smoke.sh
git diff --check
~~~~
- [ ] Record exact pass/fail/skip counts and wasm-tools --version used by gates. A focused green test does not prove full regression.
- [ ] Audit that no old duplicate type/flag references remain in active code, manifest/default counts are unchanged, and no unrelated file was staged.
- [ ] Commit only verified implementation files if all checks pass. Do not push without separate user authorization.
