# G5c C10 Nested Scalar-Record Lift Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Add a private, parser-backed, manifest-pinned two-level scalar-record `lift` Component gate whose GC and linear-memory paths both return `37`.

**Architecture:** Reuse the existing descriptor manifest and measured `MarshalNode` tree. Extend only the record-lift WAT/type emitter to recursively construct `$do_header` and `$do_recording`; keep the existing canonical `(i32)` result-area boundary and fail-closed route. Add separate host and ARC/GC equivalence scripts, without changing normal `do build` host/WIT routing.

**Tech Stack:** Zig 0.16 compiler/test modules, WIT parser/resolver, `wasm-tools 1.255.0`, Wasm GC Core WAT, Rust/Wasmtime component runner, Bash gates.

**Spec:** `doc/superpowers/specs/2026-08-20-g5c-nested-scalar-record-lift-design.md`

## Global Constraints

- Keep the private descriptor route separate from the default ARC-backed host/WIT route.
- Use only `wasm-tools 1.255.0 (76e20611d 2026-07-30)` for Component assembly and validation.
- Do not emit a Wasm GC reference in any canonical import parameter or result.
- Admit exactly one nested `header` record inside `reading`; reject shape, signature, hash, and depth drift before WAT.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, `Option`, or `Result` syntax.
- Every code change gets focused tests first, then the full regression and residual gate.

### Task 1: Add the pinned nested WIT descriptor and route-level tests

**Files:**
- Create: `examples/gc-p3-runtime/marshal-record-nested-lift-manifest-source.wit`
- Create: `doc/wit/gc_marshal_record_nested_lift_imports.wit`
- Modify: `doc/wit/gc_descriptor_manifest.json`
- Modify: `src/build/codegen_component_manifest_route_test.zig`
- Test: `src/build/codegen_component_manifest_route_test.zig`

**Interfaces:**
- Consumes: `descriptor_manifest.load_request`, `marshal_registry.build_sync_value_plan_from_wit_source`.
- Produces: descriptor id `demo:marshal-record-nested-host/api.read@1.0.0/lift` and a measured nested `MarshalNode` accepted by the private route.

- [x] **Step 1: Write the failing route tests**

Add a `nested_record_lift_measurement()` fixture with root `reading` size 32/alignment 8, fields `header@0` size 16/alignment 8 and `status@16` size 8/alignment 8; give `header` children `code@0` (`i32`) and `count@8` (`i64`). Add tests that the route emits `$do_header`, `$do_record`, canonical `(i32)`, and rejects a mutated source hash and a fourth-level/extra-child measurement.

- [x] **Step 2: Run the focused unit test and verify failure**

Run `cd src && zig test main.zig --test-filter "nested scalar record"`.
Expected: FAIL because the descriptor id, source files, and recursive WAT emission are not present.

- [x] **Step 3: Add the exact WIT fragments and manifest entry**

Use:

```wit
package demo:marshal-record-nested-host@1.0.0;

interface api {
  record header { code: u32, count: u64 }
  record reading { header: header, status: s64 }
  read: func() -> reading;
}
```

The world fragment is:

```wit
world probe {
  import api;
  export run: func() -> u32;
}
```

Compute the manifest `source_sha256` over the source and world fragments joined by one newline and ending with one newline, then set `direction` to `lift`, `params` to `[]`, `result` to `reading`, and canonical import to `demo:marshal-record-nested-host/api@1.0.0` / `read`.

- [x] **Step 4: Implement route tests for parser-backed nested binding**

Call `manifest_route.emit_sync_marshal_module_from_manifest` with the descriptor id and the nested measurement. Assert the generated request contains canonical `(i32)`, both record type names, and the nested field offsets. Mutate a temporary source copy and assert `error.SourceHashMismatch`; change a child name/type or add a child and assert `error.MeasuredFieldMismatch` or `error.MeasuredChildCountMismatch` before WAT.

- [x] **Step 5: Run the focused route tests**

Run `cd src && zig test main.zig --test-filter "nested scalar record"`.
Expected: PASS for valid binding and all negative cases.

### Task 2: Extend measured record-lift emission recursively

**Files:**
- Modify: `src/build/codegen_component_marshal_module.zig`
- Modify: `src/build/codegen_component_marshal_wat.zig`
- Modify: `src/build/codegen_component_marshal_ops.zig` only if the memory-plan assertion needs a bounded nested-record flag
- Test: unit tests in the two modified Zig modules

**Interfaces:**
- Consumes: `SyncValuePlan.root`, each child `MarshalNode.measured`, and `MeasuredNode` offsets from Task 1.
- Produces: Core WAT containing `(type $do_header (struct ...))`, `(type $do_record (struct ...))`, a canonical `(param i32)` import, and a `marshal` function returning `(ref null $do_record)`.

- [x] **Step 1: Add RED unit tests for recursive type and value construction**

Construct the exact nested plan in unit tests and assert `emit_sync_marshal_module` includes `$do_header`, `$do_record`, `struct.new $do_header`, `struct.new $do_record`, `i32.load`, `i64.load`, and offsets `8` and `16`. Add a negative test with a nested non-scalar child and expect `error.UnsupportedMarshalShape`.

- [x] **Step 2: Run the focused emitter tests and verify failure**

Run `cd src && zig test main.zig --test-filter "nested record"`.
Expected: FAIL because `emit_record_type` and `emit_record_lift` currently require every record child to be scalar.

- [x] **Step 3: Implement minimal recursive type emission**

In `codegen_component_marshal_module.zig`, recursively collect record nodes in child-before-parent order and emit one named GC struct type per record node. Use deterministic names `$do_record` for the root and `$do_record_<path>` for nested nodes, with fields typed as scalar core words or the nested `(ref null $type)`; reject text/list/resource/variant children. Do not alter scalar/list/text or lower behavior.

- [x] **Step 4: Implement recursive result-area loads and constructors**

In `codegen_component_marshal_wat.zig`, replace the root-only scalar loop with a helper that receives a `MarshalNode` and emits its measured field loads. For a nested record, load each child recursively, then emit `struct.new $<child-type>`; for a scalar, use its measured offset and core load. Emit the root constructor last. Use the root measured byte size for the existing span guard and preserve the canonical call before all loads.

- [x] **Step 5: Run focused emitter tests and all Zig unit tests**

Run `cd src && zig test main.zig --test-filter "nested record"`, then `cd src && zig test main.zig`.
Expected: focused tests pass and the full unit suite reports `536/536` or the current higher count with zero failures.

### Task 3: Add the GC probe and linear-memory reference artifacts

**Files:**
- Create: `src/build/gc_marshal_record_nested_lift_probe.zig`
- Create: `src/gc_marshal_record_nested_lift_probe_main.zig`
- Create: `examples/gc-p3-runtime/marshal-record-nested-lift-arc.core.wat`
- Create: `examples/gc-p3-runtime/marshal-record-nested-lift-assembly.wit`
- Test: `examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_host.sh` (created in Task 4)

**Interfaces:**
- Consumes: Task 1 descriptor id and Task 2 recursive emitter.
- Produces: `emit_nested_record_lift_module(io, allocator, repository_root) ![]u8` and a flat linear-memory component reference under the same WIT world.

- [x] **Step 1: Write the probe RED test**

Add a unit test that calls `emit_nested_record_lift_module`, checks the descriptor module/name, canonical `(param i32)`, `$do_header`, `$do_record`, `struct.new $do_header`, and `struct.new $do_record`, and verifies the export `run`.

- [x] **Step 2: Run the probe test and verify failure**

Run `cd src && zig test main.zig --test-filter "nested record lift probe"`.
Expected: FAIL because the probe entry point and reference artifacts do not exist.

- [x] **Step 3: Implement the probe**

Follow the existing `gc_marshal_record_mixed_lift_probe.zig` pattern, use the nested measurement from Task 1, append a `run` function that calls `marshal`, loads the returned root `$field0` header, then its `$field0`/`$field1`, plus root `$field1` status, and returns their sum as `i32` (`7 + 35 - 5 = 37`). Keep the probe-only entry point private and do not wire it into normal `do build`.

- [x] **Step 4: Add the linear-memory reference**

Create a Core WAT module whose imported `read` receives the same `(i32)` result-area pointer, writes `u32 7` at offset `0`, `u64 35` at offset `8`, and `s64 -5` at offset `16`, and whose `run` validates the area and returns `37`. Export memory and `run` only as required by the existing assembly pattern.

- [x] **Step 5: Parse both artifacts**

Run `wasm-tools parse` on the generated GC output and the checked-in ARC reference. Expected: both parse with the pinned toolchain.

### Task 4: Add host and ARC/GC equivalence gates

**Files:**
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_equivalence.sh`
- Create or modify: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_nested_host_equivalence.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Test: both new Bash gates

**Interfaces:**
- Consumes: Task 3 GC/ARC Core WAT and WIT assembly artifacts.
- Produces: host output `nested-sum=37` and equivalence output `GC/ARC manifest nested scalar record lift equivalence passed sums=37/37`.

- [x] **Step 1: Write the host gate and runner RED path**

Copy the existing manifest-backed mixed-record host gate structure, changing the descriptor id, paths, and expected host callback values to `Val::Record([("header", Val::Record([("code", Val::U32(7)), ("count", Val::U64(35))])), ("status", Val::S64(-5))])`. Assert the generated GC Component validates and the runner returns `37`.

- [x] **Step 2: Run the host gate and verify failure**

Run `bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_host.sh`.
Expected: FAIL until the probe, WIT assembly, runner binary, and recursive emitter are present.

- [x] **Step 3: Implement the Rust host/equivalence runner**

Use `wasmtime::component::Val::Record` recursively, require an empty parameter list and one result, instantiate each Component with `wasm_gc(true)`, invoke typed `run: () -> (u32,)`, and reject any value other than `37`. Print the exact equivalence marker needed by the shell gate.

- [x] **Step 4: Implement the host gate**

Require `wasm-tools 1.255.0`, build the probe with `zig run`, parse the Core module, embed the checked-in WIT world, create and validate the Component, run Cargo with the pinned runner, and grep `nested-sum=37`.

- [x] **Step 5: Implement the equivalence gate**

Generate the GC module, parse both GC and ARC modules, embed each under the same world, create and validate both Components, run the Rust equivalence binary, and require `sums=37/37`. Also grep the generated Core import/type text to ensure no `(ref null` appears in the canonical import declaration.

- [x] **Step 6: Run both gates**

Run `bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_host.sh` and `bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_equivalence.sh`.
Expected: both pass with `37` and `37/37`.

### Task 5: Synchronize evidence and run release-level verification

**Files:**
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `CHANGELOG.md`
- Modify: `src/build/test/check_gc_g5c_residual_gate.sh`
- Test: `src/build/test/run_tests.sh`

**Interfaces:**
- Consumes: all green gates from Tasks 1-4.
- Produces: auditable C10 evidence while `host_wit_marshalling` and G5c cutover remain pending.

- [x] **Step 1: Add the C10 residual/evidence assertions**

Extend the residual checker to run the nested host and equivalence gates, check the pinned tool version, and keep the inventory summary at `complete_rows=14 pending_rows=14`; do not mark the general host/WIT or G5c cutover row complete.

- [x] **Step 2: Update documentation with exact outputs**

Add the C10 descriptor id, measured sizes/offsets (`header=16`, `reading=32`, offsets `0/8/16`), canonical `(i32)`, host `37`, equivalence `37/37`, and the unchanged non-goals to `roadmap_status.md`, `start_here.md`, and `CHANGELOG.md`. Update only the current unit/regression counts after running them.

- [x] **Step 3: Run the complete verification set**

Run from the repository root:

```bash
(cd src && zig test main.zig)
(cd src && zig build -Doptimize=ReleaseSmall)
git diff --check
./src/build/test/run_tests.sh
bash src/build/test/check_gc_g5c_residual_gate.sh
```

Expected: all commands exit zero; the full harness has zero failures; the residual gate explicitly reports C10 host/equivalence success and leaves pending rows unchanged.

- [x] **Step 4: Review the final diff without committing or pushing**

Run `git status --short --branch`, `git diff --stat`, and `git diff --check`. Confirm the accumulated C4-C10 implementation, test, manifest, and evidence files are the only scoped changes; do not stage, commit, or push in this session.
