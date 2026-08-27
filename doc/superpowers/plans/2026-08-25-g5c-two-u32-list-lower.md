# G5c Two-`list<u32>` Record Lower Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one manifest-backed synchronous host/WIT descriptor for `Writing { code: u32, first: [u32], second: [u32] }` with measured two-span lower/call/reverse-free behavior.

**Architecture:** Extend the existing `SyncValuePlan` operation boundary with a two-field scalar-list fact and a dedicated WAT emitter branch. Keep `LoadedRequest` as the only manifest/source/WIT ownership boundary and route the new exact descriptor through the existing default host/WIT lease; unknown or drifted shapes retain the current fallback or fail-closed diagnostics.

**Tech Stack:** Zig compiler, `.do`/WIT fixtures, WAT, `wasm-tools 1.255.0`, Wasmtime 47.0.2, Rust host runners, Bash gates, and the existing full regression harness.

**Spec:** `doc/superpowers/specs/2026-08-25-g5c-two-u32-list-lower-design.md`

## Global Constraints

- Keep the GC-first v1 contract and the existing ARC fallback.
- Keep canonical imports free of Wasm GC reference types.
- Keep `LoadedRequest`, descriptor registry, source/WIT hashes, and `SyncValuePlan` as the single ownership/provenance path.
- Admit only the exact three-field record and synchronous `@host_func` descriptor in the spec.
- Validate both list spans before the first load/copy and free the second span before the first exactly once.
- Do not add list element kinds, public syntax, `own<T>`, `borrow<T>`, `ref<T>`, Option, Result, Variant, async, resource, or generic aggregate semantics.
- Preserve `complete_rows=15 pending_rows=15`; this slice does not close an inventory row.
- Preserve unrelated dirty-worktree changes; do not reset, clean, commit, or push in this plan.

### Task 1: Lock the exact source/WIT and RED descriptor tests

**Files:**
- Create: `examples/gc-p3-runtime/marshal-record-two-u32-lists-lower-manifest-source.wit`
- Create: `examples/gc-p3-runtime/marshal-record-two-u32-lists-lower-assembly.wit`
- Create: `doc/wit/gc_marshal_record_two_u32_lists_lower_imports.wit`
- Create: `examples/gc-p3-runtime/ordinary-host-record-two-u32-lists-lower-call.do`
- Test: `src/build/codegen_component_descriptor_manifest.zig`
- Test: `src/build/codegen_component_marshal_ops.zig`

**Interfaces:**
- Consumes: the existing descriptor parser and `build_sync_memory_plan`.
- Produces: a source/WIT pair with one exact descriptor id and a RED assertion that two list children are currently rejected by the single-list admission predicate.

- [x] **Step 1: Add the exact fixtures.**

  Use the package/interface/record and Do source from the design document. The
  imports world must export `run: func() -> u32` and contain no host-specific
  extra imports.

- [x] **Step 2: Confirm the current RED behavior.**

  Run:

  ```bash
  cd src
  zig test build/codegen_component_marshal_ops.zig --test-filter 'two u32 list'
  ```

  Expected before implementation: the new test reports
  `error.UnsupportedMarshalShape` because the current single-list root matcher
  requires exactly two record children.

- [x] **Step 3: Add the descriptor-loader RED assertion.**

  Add a test that loads the descriptor id from `doc/wit/gc_descriptor_manifest.json`
  after its manifest entry is added in Task 2, then calls
  `validate_loaded_host_boundary` on the positive compile fixture. Keep the test
  failing until the measured two-list plan is implemented; do not weaken the
  existing one-list tests.

- [x] **Step 4: Run the RED tests and capture the failure.**

  ```bash
  cd src
  zig test build/codegen_component_descriptor_manifest.zig --test-filter 'two u32 list'
  zig test build/codegen_component_marshal_ops.zig --test-filter 'two u32 list'
  ```

  Expected: both tests fail only at the new two-list admission point, with all
  existing focused tests untouched.

### Task 2: Add the measured manifest and registry boundary

**Files:**
- Modify: `doc/wit/gc_descriptor_manifest.json`
- Modify: `src/build/codegen_component_descriptor_manifest.zig` only if a focused test proves the existing list conversion cannot represent two `list<u32>` children
- Test: `src/wit/descriptor_manifest_test.zig`
- Test: `src/build/codegen_component_descriptor_manifest.zig`

**Interfaces:**
- Consumes: the exact WIT/source files from Task 1.
- Produces: `LoadedRequest.plan` with two independently measured `list<u32>` children and canonical import `(i32,i32,i32,i32,i32)`.

- [x] **Step 1: Compute and record hashes.**

  Run:

  ```bash
  sha256sum examples/gc-p3-runtime/marshal-record-two-u32-lists-lower-manifest-source.wit
  sha256sum doc/wit/gc_marshal_record_two_u32_lists_lower_imports.wit
  ```

  Copy the exact 64-hex source hash into the descriptor's `source_sha256` and
  use the measured WIT hash in the descriptor metadata where the existing
  manifest convention requires it.

- [x] **Step 2: Add the measured descriptor entry.**

  Add id `demo:marshal-record-two-u32-lists-lower/api.write@1.0.0/lower` with
  `params: ["writing"]`, `result: "_"`, root `byte_size=20`, `alignment=4`,
  fields at offsets `0`, `4`, and `12`, and child list facts exactly as the spec:
  first capacity `3`, second capacity `2`, both stride/alignment/element size `4`,
  allocation/free `cabi_realloc`. Set the canonical module to
  `demo:marshal-record-two-u32-lists-lower/api@1.0.0` and name `write`.

- [x] **Step 3: Add parser and loaded-request assertions.**

  Assert the descriptor is found by id, the two list child measurements survive
  conversion, the root offsets remain `0/4/12`, and the loaded request owns the
  canonical identity. Run:

  ```bash
  cd src
  zig test wit/descriptor_manifest_test.zig
  zig test build/codegen_component_descriptor_manifest.zig
  ```

- [x] **Step 4: Verify the descriptor is still fail-closed on hash drift.**

  Add one source-hash drift assertion using the existing loader test helper and
  require `error.SourceHashMismatch` (or the repository's exact equivalent).

### Task 3: Extend the pure operation plan for two scalar-list fields

**Files:**
- Modify: `src/build/codegen_component_marshal_ops.zig`
- Test: `src/build/codegen_component_marshal_ops.zig`

**Interfaces:**
- Consumes: `marshal.SyncValuePlan` with the measured descriptor from Task 2.
- Produces: `ManagedScalarListPairLower`, `MemoryPlan.managed_scalar_list_pair_lower`, and the operation sequence `read_gc_span -> validate/alloc/copy x2 -> canonical_call -> free(second) -> free(first)`.

- [x] **Step 1: Add the RED operation-plan assertion.**

  Build a synthetic root with children `u32`, `list<u32>`, `list<u32>` and the
  exact measured facts. Assert the current implementation returns
  `error.UnsupportedMarshalShape` before changing the matcher.

- [x] **Step 2: Add the pair fact type and pure matcher.**

  Add:

  ```zig
  pub const ManagedScalarListPairLower = struct {
      first: ManagedScalarListField,
      second: ManagedScalarListField,
  };
  ```

  Add `managed_scalar_list_pair_lower_for_root` that requires exactly three
  children, a `u32` first field, two `list<u32>` children at field indexes `1`
  and `2`, root size/alignment `20/4`, pointer/length offsets `0/4` for both
  lists, and non-zero capacities. Keep the existing single-list and mixed
  matchers unchanged.

- [x] **Step 3: Wire the pair fact before the single-list branches.**

  Extend `MemoryPlan` with `record_managed_scalar_list_pair_lower` and
  `managed_scalar_list_pair_lower`. Select the pair matcher before
  `managed_mixed_scalar_list_lower_for_root` and
  `managed_scalar_list_field_for_root`; select the pair operation array before
  the existing single-list array.

- [x] **Step 4: Add and verify the operation sequence.**

  Add `record_managed_scalar_list_pair_lower_operations` with exactly ten
  operations:

  ```text
  read_gc_span,
  validate_linear_range, cabi_realloc_alloc, copy_to_linear,
  validate_linear_range, cabi_realloc_alloc, copy_to_linear,
  canonical_call,
  cabi_realloc_free, cabi_realloc_free
  ```

  Assert the last two frees are in reverse field order and that the existing
  one-list/mixed operation tests remain unchanged.

- [x] **Step 5: Run the focused operation tests.**

  ```bash
  cd src
  zig test build/codegen_component_marshal_ops.zig
  ```

  Expected: the new pair test and all existing operation tests pass.

### Task 4: Emit two guarded copies and reverse cleanup

**Files:**
- Modify: `src/build/codegen_component_marshal_wat.zig`
- Test: `src/build/codegen_component_marshal_wat.zig`

**Interfaces:**
- Consumes: `MemoryPlan.managed_scalar_list_pair_lower` and the existing record input-path emitter.
- Produces: a canonical lower WAT function with two GC array locals, two span guards, one host call, and conditional frees in second/first order.

- [x] **Step 1: Add the RED WAT assertions.**

  Assert that the exact synthetic plan currently rejects or lacks two independent
  `array.get $do_u32` loops and two distinct linear spans. Do not assert against
  hard-coded line numbers.

- [x] **Step 2: Add the pair emitter.**

  Implement `emit_record_lower_managed_scalar_list_pair` with distinct locals
  `__gc_values_0`, `__gc_values_1`, `__gc_length_0`, `__gc_length_1`,
  `__gc_copy_bytes_0`, `__gc_copy_bytes_1`, `__cabi_ptr_0`, and
  `__cabi_ptr_1`. Use the existing `append_copy_byte_count_for_locals`,
  `emit_span_guard_branch_to_cleanup`, `emit_conditional_cleanup`, and
  `emit_record_lower_input_path` helpers. The canonical call must load
  `code`, pointer/length pair 0, and pointer/length pair 1 in that order.

- [x] **Step 3: Preserve cleanup on partial failure.**

  Use an allocation mask with one bit per span. A failed second allocation or
  guard may free only span 0; a successful call frees span 1 then span 0. The
  cleanup trap path must remain explicit and must not call `cabi_realloc` for a
  zero/unallocated span.

- [x] **Step 4: Add WAT order assertions.**

  Assert two `array.get $do_u32` copies, two allocation calls before the
  canonical call, no `(ref` in the canonical import, and the free call order
  after the canonical call. Assert the first guard occurs before the first
  `i32.load`/copy of that span and the second guard before the second span copy.

- [x] **Step 5: Run focused WAT tests.**

  ```bash
  cd src
  zig test build/codegen_component_marshal_wat.zig --test-filter 'two u32 list'
  zig test build/codegen_component_marshal_wat.zig
  ```

### Task 5: Add positive host and ARC/GC equivalence artifacts

**Files:**
- Create: `examples/gc-p3-runtime/marshal-record-two-u32-lists-lower-arc.core.wat`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_two_u32_lists_lower.rs`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_two_u32_lists_lower_equivalence.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/gc-p3-runtime/test_gc_two_u32_lists_lower_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_two_u32_lists_lower_equivalence.sh`

**Interfaces:**
- Consumes: the generated WAT and assembly world from Tasks 1–4.
- Produces: host observation for `code=7`, `first=[10,20,5]`, `second=[3,4]`, one callback, two allocations/frees, and matching ARC/GC outcomes.

- [x] **Step 1: Add the linear ARC oracle.**

  Use the same five-word canonical import, copy both arrays from fixed linear
  data, call the host once, and return the existing cleanup oracle value `34`
  after two allocations and two frees.

- [x] **Step 2: Add the Wasmtime host runner.**

  Require one record parameter with fields `code`, `first`, and `second`; decode
  `Val::List` elements as `Val::U32`; reject any other type or field count; and
  require exactly one callback and cleanup value `34`.

- [x] **Step 3: Add the equivalence runner.**

  Run GC and ARC components with the same host callback and compare cleanup and
  callback counts. Fail on any mismatch and print one deterministic summary.

- [x] **Step 4: Add host and equivalence shell gates.**

  Require the pinned `wasm-tools 1.255.0`, build the compiler with Debug Zig,
  assert `;; gc-sync`, reject `__arc_`, parse/embed/new/validate the component,
  and invoke the matching Cargo binaries. Keep all temporary files in a
  per-script `mktemp -d` directory with a trap.

### Task 6: Add compiler boundary positives and negatives

**Files:**
- Create: `src/build/test/compile_ok/657_gc_wit_two_u32_lists_lower_host_boundary.do`
- Create: `src/build/test/compile_err/658_gc_wit_two_u32_lists_lower_host_boundary_async.do` and matching `.expect`
- Create: `src/build/test/compile_err/659_gc_wit_two_u32_lists_lower_host_boundary_locator.do` and matching `.expect`
- Create: `src/build/test/compile_err/660_gc_wit_two_u32_lists_lower_host_boundary_member.do` and matching `.expect`
- Create: `src/build/test/compile_err/661_gc_wit_two_u32_lists_lower_host_boundary_reordered.do` and matching `.expect`
- Create: `src/build/test/compile_err/662_gc_wit_two_u32_lists_lower_host_boundary_first_byte_list.do` and matching `.expect`
- Create: `src/build/test/compile_err/663_gc_wit_two_u32_lists_lower_host_boundary_second_byte_list.do` and matching `.expect`
- Create: `src/build/test/compile_err/664_gc_wit_two_u32_lists_lower_host_boundary_extra_field.do` and matching `.expect`
- Create: `examples/gc-p3-runtime/test_gc_two_u32_lists_lower_negative.sh`

**Interfaces:**
- Consumes: the exact descriptor id and compiler diagnostic names from the existing host/WIT boundary validator.
- Produces: one positive admission and seven fail-closed cases before WAT emission.

- [x] **Step 1: Add the positive fixture.**

  Bind the exact descriptor with synchronous `@host_func`, declare the exact
  `Writing` record, call it once, and assert the generated output has the
  descriptor-specific GC route.

- [x] **Step 2: Add the seven drift fixtures.**

  Change only one fact per fixture: async marker, locator, member, field order,
  first payload type, second payload type, or extra field. Each `.expect` file
  must contain the exact diagnostic substring emitted by the existing validator.

- [x] **Step 3: Add the negative gate.**

  Invoke each fixture with `--gc-wit-marshal
  demo:marshal-record-two-u32-lists-lower/api.write@1.0.0/lower`, require a
  non-zero compiler status, require no WAT artifact, and check the expected
  diagnostic.

### Task 7: Integrate default/residual gates without closing inventory

**Files:**
- Modify: `src/build/test/check_gc_default_build_gate.sh`
- Modify: `src/build/test/check_gc_g5c_residual_gate.sh`
- Modify: `src/build/test/check_gc_g5c_residual_gate_test.sh`
- Modify: `examples/gc-p3-runtime/README.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`

**Interfaces:**
- Consumes: positive/negative/host/equivalence scripts from Tasks 5–6.
- Produces: default route and residual gate evidence for the new descriptor while retaining `complete_rows=15 pending_rows=15`.

- [x] **Step 1: Add the positive fixture to the default GC manifest.**

  Insert `657_gc_wit_two_u32_lists_lower_host_boundary.do` in numeric order and
  update the expected fixture count only after the standalone gate passes.
  Assert `;; gc-sync`, no `__arc_`, the five-word canonical type, and no GC
  reference on the import.

- [x] **Step 2: Add all three new route phases to the residual gate.**

  Run host, equivalence, and negative scripts; require each to pass; do not add
  a completion row or change the inventory summary.

- [x] **Step 3: Record verified facts only.**

  Document the exact record, ABI, two-span cleanup order, toolchain, host
  counters, and explicit non-goals. State that this is another fixed descriptor
  promotion, not general record/list lowering or full GC cutover.

### Task 8: Run phase-wide verification and hand off

**Files:**
- Test: `src/build/codegen_component_marshal_ops.zig`
- Test: `src/build/codegen_component_marshal_wat.zig`
- Test: `src/build/test/run_tests.sh`
- Test: `src/build/test/run_release_smoke.sh`
- Test: `src/build/test/check_gc_default_build_gate.sh`
- Test: `src/build/test/check_gc_g5c_residual_gate.sh`
- Test: `src/build/test/check_gc_semantic_equivalence.sh`
- Test: `src/build/test/check_gc_migration_inventory.sh`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: a verified bounded route or a reproducible failure with rollback scope.

- [x] **Step 1: Run focused and full compiler tests.**

  ```bash
  (cd src && zig test build/codegen_component_marshal_ops.zig)
  (cd src && zig test build/codegen_component_marshal_wat.zig)
  ./src/build/test/run_tests.sh
  ```

- [x] **Step 2: Run release and GC gates.**

  ```bash
  ./src/build/test/run_release_smoke.sh
  bash src/build/test/check_gc_default_build_gate.sh
  bash src/build/test/check_gc_g5c_residual_gate.sh
  bash src/build/test/check_gc_semantic_equivalence.sh
  ```

- [x] **Step 3: Verify the intentional migration result.**

  ```bash
  set +e
  bash src/build/test/check_gc_migration_inventory.sh
  status=$?
  set -e
  test "$status" -eq 1
  ```

  Require exact output `summary complete_rows=15 pending_rows=15`.

- [x] **Step 4: Run documentation and worktree checks.**

  ```bash
  git diff --check
  git status --short --branch
  ```

  Do not commit or push without a separate delivery instruction; preserve all
  unrelated dirty changes.

## Exit Criteria

The slice is complete only when the exact two-list descriptor has fresh WAT,
Component, Rust/Wasmtime host, negative, and ARC/GC equivalence evidence; all
full gates are green; the canonical boundary is GC-reference-free; and the
inventory remains intentionally `complete_rows=15 pending_rows=15`. It does
not close G5c or authorize the next shape automatically.
