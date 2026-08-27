# G5c Mixed `text` + `list<u8>` Lift Implementation Plan

> **For agentic workers:** Execute this plan task-by-task in the current checkout. Preserve unrelated dirty changes; do not reset, clean, commit, or push unless explicitly requested.

**Goal:** Add one hash-pinned synchronous default GC/WIT lift route for `Reading { code: u32, label: text, payload: [u8] }`.

**Architecture:** Reuse the existing manifest-backed record-lift planner and emitter, which already has measured byte-list copy support. Add only a sibling descriptor, source-level admission, generated probe/runner, and default/residual gates. Keep all other list and aggregate shapes fail-closed or on the existing ARC fallback.

**Tech Stack:** Zig compiler and tests, `.do` fixtures, WIT/component descriptors, Rust 2024 Wasmtime runner, Bash gates, and pinned `wasm-tools 1.255.0`.

**Spec:** `doc/superpowers/specs/2026-08-25-g5c-mixed-text-byte-list-lift-design.md`

**Status:** Implemented and verified on 2026-08-25. The hash-pinned descriptor,
default route, Component/Rust/Wasmtime host and ARC/GC equivalence gates, eight
negative fixtures, 82-fixture default build gate, residual baseline, full
regression, and ReleaseSmall smoke are green. The ARC path is retained only as
the equivalence oracle; this plan does not close the 15-row GC migration ledger
or claim full G5c cutover.

## Global Constraints

- Keep the exact 20-byte result-area layout and canonical lift `(i32)` ABI.
- Accept only the hash-pinned `demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift` descriptor.
- Keep GC references out of the canonical import and free both linear spans exactly once.
- Use only `wasm-tools 1.255.0`.
- Do not add public syntax, `own<T>`, `borrow<T>`, `ref<T>`, `Option`, `Result`, async, resource, cancellation, or generic ownership behavior.
- Do not generalize list element inference or capacity inference; `[u32]` and other drifted payloads remain rejected for this descriptor.
- Keep GC-first v1 with ARC fallback for every unadmitted host/WIT shape.
- Preserve unrelated dirty-worktree changes; do not reset, clean, commit, or push.
- Keep migration inventory at `complete_rows=15 pending_rows=15` with deliberate exit `1`.

---

### Task 1: Add pinned sources, manifest entry, and RED boundary fixtures

**Files:**

- Create: `examples/gc-p3-runtime/marshal-record-mixed-text-byte-list-lift-manifest-source.wit`
- Create: `doc/wit/gc_marshal_record_mixed_text_byte_list_lift_imports.wit`
- Create: `examples/gc-p3-runtime/marshal-record-mixed-text-byte-list-lift-assembly.wit`
- Create: `examples/gc-p3-runtime/ordinary-host-record-mixed-text-byte-list-lift-call.do`
- Modify: `doc/wit/gc_descriptor_manifest.json`
- Create: `src/build/test/compile_ok/648_gc_wit_mixed_text_byte_list_lift_host_boundary.do`
- Create: `src/build/test/compile_err/649_gc_wit_mixed_text_byte_list_lift_async.do` and `.expect`
- Create: `src/build/test/compile_err/650_gc_wit_mixed_text_byte_list_lift_locator.do` and `.expect`
- Create: `src/build/test/compile_err/651_gc_wit_mixed_text_byte_list_lift_member.do` and `.expect`
- Create: `src/build/test/compile_err/652_gc_wit_mixed_text_byte_list_lift_reordered.do` and `.expect`
- Create: `src/build/test/compile_err/653_gc_wit_mixed_text_byte_list_lift_u32_payload.do` and `.expect`
- Create: `src/build/test/compile_err/654_gc_wit_mixed_text_byte_list_lift_text_payload.do` and `.expect`
- Create: `src/build/test/compile_err/655_gc_wit_mixed_text_byte_list_lift_extra_field.do` and `.expect`
- Create: `src/build/test/compile_err/656_gc_wit_mixed_text_byte_list_lift_record_name.do` and `.expect`

**Interfaces:**

- Consumes: the fixed source shape and descriptor contract in the spec.
- Produces: a hash-pinned manifest entry, one positive source fixture, and
  eight source-level fail-closed cases for Tasks 2–5.

- [x] **Step 1: Add the exact WIT and Do source mirrors.**

  Use this record and function without extra fields or parameters:

  ```wit
  package demo:marshal-record-mixed-text-byte-list-lift@1.0.0;

  interface api {
    record reading {
      code: u32,
      label: string,
      payload: list<u8>,
    }

    read: func() -> reading;
  }
  ```

  The positive Do boundary is:

  ```do
  read = @host_func("demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0", "read", () -> Reading)

  Reading {
      code u32
      label text
      payload [u8]
  }

  start() {
      read()
  }
  ```

- [x] **Step 2: Compute and record the manifest source hash.**

  ```bash
  { cat examples/gc-p3-runtime/marshal-record-mixed-text-byte-list-lift-manifest-source.wit; printf '\n'; cat doc/wit/gc_marshal_record_mixed_text_byte_list_lift_imports.wit; printf '\n'; } | sha256sum
  ```

  Add one entry with `direction: "lift"`, `params: []`, `result: "reading"`,
  `do_record_name: "Reading"`, a 20-byte root, text child, byte-list child
  (`capacity: 4`, accepted lengths `0..4`), and canonical import module/name.
  Do not change existing descriptor entries.

- [x] **Step 3: Add the positive and negative fixtures.**

  Keep the positive fixture host-first because the parser requires top-level
  imports before ordinary declarations. Each negative fixture must fail before
  WAT and leave no output artifact. The expected diagnostic classes are the
  same as the preceding mixed `text`/`u32-list` lift row: async marker is
  `UnknownP3AsyncHostDescriptor`; locator/member drift is the corresponding
  `GcWitHost*Mismatch`; structural drift is `GcWitHostRecordMismatch`.

### Task 2: Add exact boundary and typed-plan admission

**Files:**

- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/codegen_component_manifest_route_test.zig`
- Modify: `src/build/codegen_gc_plans_test.zig`

**Interfaces:**

- Consumes: Task 1 manifest and source fixtures.
- Produces: `mixed_text_byte_list_lift_descriptor`, exact `Reading` field
  validation, and a typed plan whose ordered operations are
  `canonical_call`, `validate_linear_range`, `copy_from_linear`,
  `construct_gc_value`, `publish_gc_root` plus emitter-owned frees.

- [x] **Step 1: Add the descriptor constants and field spec.**

  Add the locator/member/record/field shape beside the existing mixed
  `text`/`u32-list` lift constants. Dispatch must reject `[u32]`, `text`,
  reordered, extra, or renamed fields before WAT; it must not infer a sibling
  descriptor from structural similarity.

- [x] **Step 2: Add manifest measurement assertions.**

  Require root `byte_size=20`, `alignment=4`, field offsets `0/4/12`, text
  pointer/length offsets `0/4`, byte-list pointer/length offsets `0/4`,
  `element_byte_size=1`, `element_stride=1`, `element_alignment=1`,
  `capacity=4`, and accepted lengths `[0,1,2,3,4]`. Require canonical import
  signature `(i32)` and no reference type.

- [x] **Step 3: Run the focused RED/GREEN tests.**

  ```bash
  cd src
  zig test build/codegen_gc_wit_host_boundary.zig --test-filter 'mixed text byte-list lift'
  zig test build/codegen_gc_plans_test.zig --test-filter 'mixed text byte-list lift'
  zig test build/codegen_component_manifest_route_test.zig --test-filter 'mixed text byte-list lift'
  ```

  Before implementation these tests must fail for the missing descriptor; after
  the exact route is added they must pass without weakening any negative case.

### Task 3: Reuse the lift emitter and add the generated probe

**Files:**

- Modify: `src/build/codegen_gc_wit_marshal.zig`
- Modify: `src/build/run.zig`
- Create: `src/build/gc_marshal_record_mixed_text_byte_list_lift_probe.zig`
- Create: `src/gc_marshal_record_mixed_text_byte_list_lift_probe_main.zig`

**Interfaces:**

- Consumes: Task 2 descriptor and manifest-backed `SyncValuePlan`.
- Produces: explicit marshal dispatch, a generated Core module with `$do_bytes`
  for both text and payload, and a `$run`/`$stats` probe.

- [x] **Step 1: Add explicit descriptor dispatch.**

  Add the descriptor to `codegen_gc_wit_marshal.emit_module` and the ordinary
  `admitted_gc_host_descriptor` route in `run.zig`. Unknown descriptors must
  remain rejected; an unrelated ordinary host fixture must remain ARC-backed.

- [x] **Step 2: Verify the existing generic lift output before editing it.**

  Generate the module from the new descriptor and assert the WAT contains:

  ```text
  (type $canonical_lift (func (param i32)))
  array.new_default $do_bytes
  i32.load8_u
  array.set $do_bytes
  struct.new $do_record
  ```

  Assert exactly two `cabi_realloc` frees after the canonical call, no `(ref`
  in the canonical import, and the payload copy uses stride `1`. Only add
  emitter code if one of these exact assertions is missing.

- [x] **Step 3: Add the fixed probe wrapper.**

  Construct the manifest-owned route, export `run` returning `47`, export
  `stats` returning `34`, and make the wrapper validate the result area, both
  `$do_bytes` arrays, and exactly-once free order before emitting WAT.

- [x] **Step 4: Run focused WAT and parser verification.**

  ```bash
  cd src
  zig test build/codegen_gc_wit_marshal.zig --test-filter 'mixed text byte-list lift'
  zig run gc_marshal_record_mixed_text_byte_list_lift_probe_main.zig -- /tmp/mixed-text-byte-list-lift.wat ..
  wasm-tools parse /tmp/mixed-text-byte-list-lift.wat -o /tmp/mixed-text-byte-list-lift.wasm
  ```

### Task 4: Add host, equivalence, negative, and default-route gates

**Files:**

- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_mixed_text_byte_list_lift.rs`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_list_lift_manifest_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_list_lift_manifest_equivalence.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_list_lift_negative.sh`
- Create: `examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_byte_list_lift_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_byte_list_lift_equivalence.sh`
- Create: `examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_byte_list_lift_negative.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Modify: `src/build/test/check_gc_g5c_residual_gate.sh`
- Modify: `src/build/test/check_gc_g5c_residual_gate_test.sh`
- Modify: `src/build/test/check_gc_default_build_gate.sh`
- Modify: `src/build/test/check_gc_migration_inventory.sh`

**Interfaces:**

- Consumes: Task 3 compiler output and existing Rust/Wasmtime gate conventions.
- Produces: host execution, ARC/GC equivalence, eight negative fixtures, and
  ordinary default-route evidence.

- [x] **Step 1: Add the Rust host runner.**

  The host returns `Reading { code: 7, label: "hello", payload: [10,20,5] }`.
  The single-component mode requires `(47,34,1)`, two-component equivalence
  mode requires `(47,34,1)` on both paths, and output must report two
  allocations and two frees for the mixed route.

- [x] **Step 2: Add manifest and default shell gates.**

  Each gate pins and checks `wasm-tools 1.255.0`, builds Debug, parses WAT,
  rejects canonical imports containing `(ref`, checks no `__arc_`, assembles
  the same Component world, and invokes the Rust runner. The default gate must
  additionally prove an unrelated ordinary host remains on ARC fallback.

- [x] **Step 3: Add negative and residual wiring.**

  Run fixtures `649–656`, assert nonzero compiler status and no output WAT,
  and add all six new scripts to the residual static wiring test and baseline
  invocation. Add the positive fixture to the default expected manifest and
  keep the migration inventory’s deliberate `15/15` pending result.

### Task 5: Full verification and documentation handoff

**Files:**

- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/pending_blocked.md`
- Modify: `examples/gc-p3-runtime/README.md`

**Interfaces:**

- Consumes: all Task 1–4 evidence.
- Produces: current documentation, exact next-shape handoff, and a verified
  uncommitted worktree.

- [x] **Step 1: Run the complete verification sequence.**

  ```bash
  ROOT_DIR="$(pwd)"
  bash -n examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_list_lift_manifest_host.sh \
    examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_list_lift_manifest_equivalence.sh \
    examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_byte_list_lift_host.sh \
    examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_byte_list_lift_equivalence.sh \
    src/build/test/check_gc_g5c_residual_gate.sh \
    src/build/test/check_gc_g5c_residual_gate_test.sh
  (cd "$ROOT_DIR/src" && zig test main.zig)
  (cd "$ROOT_DIR" && NODE_BIN="$(command -v bun)" WASM_TOOLS="$(command -v wasm-tools)" ./src/build/test/run_tests.sh)
  (cd "$ROOT_DIR" && WASM_TOOLS_BIN="$(command -v wasm-tools)" bash src/build/test/check_gc_default_build_gate.sh)
  (cd "$ROOT_DIR" && WASM_TOOLS_BIN="$(command -v wasm-tools)" WASMTIME_BIN="$(command -v wasmtime)" bash src/build/test/check_gc_g5c_residual_gate.sh baseline)
  (cd "$ROOT_DIR" && NODE_BIN="$(command -v bun)" WASM_TOOLS="$(command -v wasm-tools)" bash src/build/test/run_release_smoke.sh)
  set +e
  (cd "$ROOT_DIR" && bash src/build/test/check_gc_migration_inventory.sh)
  inventory_status=$?
  set -e
  test "$inventory_status" -eq 1
  (cd "$ROOT_DIR" && git diff --check)
  ```

  Expected: all commands except the inventory check exit `0`; inventory emits
  `complete_rows=15 pending_rows=15` and exits `1` by design.

- [x] **Step 2: Record exact evidence in the four status documents.**

  Record the descriptor, 20-byte layout, byte-list capacity/stride, host
  outputs `47/34/1`, two allocations/frees, fixtures `649–656`, pinned tool
  version, actual default fixture count, and the fact that general aggregate,
  async/resource, ownership syntax, and full G5c cutover remain pending.

- [x] **Step 3: Re-audit scope.**

  Confirm no public syntax changed, no unadmitted descriptor was promoted, no
  unrelated dirty change was overwritten, and no new P0/P1 blocker exists.
  Leave the worktree uncommitted and unpushed unless separately requested.

## Self-review checklist

- The spec covers the fixed ABI/layout, byte-list lifetime, source admission,
  non-goals, and all evidence gates.
- Every plan task has concrete files, interfaces, commands, and expected
  results with no unspecified implementation step.
- Existing mixed `text` + `list<u32>` lift and all unrelated routes remain
  unchanged and provide the rollback baseline.
- The plan does not widen public ownership or async syntax and preserves the
  migration inventory’s intentional pending status.
