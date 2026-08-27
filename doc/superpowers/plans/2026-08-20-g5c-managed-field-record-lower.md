# C15-B scalar-plus-text record lower Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a private, manifest-pinned GC lower gate for `record { code: u32, label: string }` with flat canonical parameters and exactly-once temporary-buffer cleanup.

**Architecture:** Reuse the parser-backed `SyncValuePlan`, measured layout, and existing GC WAT/module emitters. Admit only the exact root scalar-plus-text shape in the lower operation plan; emit the flat canonical import `(i32, i32, i32)`, copy the GC text bytes through `cabi_realloc`, call the host, then free the temporary span. Keep the default ARC host/WIT route and all unsupported aggregate shapes unchanged.

**Tech Stack:** Zig 0.16, existing WIT parser/resolver, Core Wasm GC WAT, `wasm-tools 1.255.0`, Wasmtime `47.0.2`, Rust host runners, Bash gates.

**Spec:** `doc/superpowers/specs/2026-08-20-g5c-managed-field-record-lower-design.md`

## Global Constraints

- Use only `wasm-tools 1.255.0 (76e20611d 2026-07-30)` for Component assembly.
- Keep the route private and manifest-backed; do not change default host/WIT routing.
- Canonical imports contain only Core scalar types; no GC reference crosses the boundary.
- Admit exactly one root `u32` field followed by one `string` field; reject other managed aggregates.
- Preserve call-before-free ordering and exactly one allocation/free pair.
- Do not add `own<T>`, `borrow<T>`, `ref<T>`, `Option`, `Result`, async, or resource syntax.
- Preserve unrelated dirty worktree changes and do not push.

### Task 1: Add the descriptor and shape-level RED test

**Files:**
- Create: `examples/gc-p3-runtime/marshal-record-managed-lower-manifest-source.wit`
- Create: `doc/wit/gc_marshal_record_managed_lower_imports.wit`
- Modify: `doc/wit/gc_descriptor_manifest.json`
- Modify: `src/build/codegen_component_manifest_route_test.zig`
- Test: `src/build/codegen_component_manifest_route_test.zig`

**Interfaces:**
- Consumes: manifest loader and parser-backed `SyncValuePlan`.
- Produces: descriptor id `demo:marshal-record-managed-lower/api.write@1.0.0/lower` and measured layout `12/4` with child offsets `0` and `4`.

- [x] **Step 1: Write the failing route test.** Add a measured root record with `code: u32` at `0` and `label: string` at `4`, assert the new descriptor route is currently rejected or lacks managed lower admission, and add a negative extra-child/source-hash case.
- [x] **Step 2: Run the focused test.** Run `cd src && zig test main.zig --test-filter 'managed.*record.*lower'`. Expected: FAIL because the descriptor and lower managed-text shape are not admitted.
- [x] **Step 3: Add exact WIT fragments and manifest entry.** Use the WIT text from the spec, compute the source SHA-256, and pin package/world/interface/member/direction/signature/canonical import in the manifest.
- [x] **Step 4: Re-run the route test.** Confirm source identity and measurement validation still fail closed for mutation and child-count drift.

### Task 2: Admit the fixed measured lower shape

**Files:**
- Modify: `src/build/codegen_component_marshal_ops.zig`
- Test: `src/build/codegen_component_marshal_ops.zig`

**Interfaces:**
- Consumes: `MarshalNode` and `MeasuredFacts` from the parser-backed plan.
- Produces: a record lower `MemoryPlan` whose operations are read, copy/allocate, canonical call, free, with the root managed-text shape admitted only once.

- [x] **Step 1: Add the RED operation test.** Build the exact two-child measured plan and assert `record_fields` is rejected or does not expose the managed-text operation sequence; add a nested-text rejection test.
- [x] **Step 2: Run the focused test and capture the expected failure.** Run `cd src && zig test main.zig --test-filter 'marshal operation plan.*record'`.
- [x] **Step 3: Implement the narrow validator.** Admit only a root record with exactly two children, first scalar `u32` with Core `i32`, second measured `text` with ptr/len facts, no root indirect layout, and no nested managed child. Preserve scalar-only and indirect scalar paths.
- [x] **Step 4: Encode the operation order.** Add a dedicated managed-text lower operation list that places `cabi_realloc_free` after `canonical_call`; assert the order in unit tests.
- [x] **Step 5: Run focused Zig tests.** Confirm the exact shape passes and all alternate shapes remain rejected.

### Task 3: Emit flat canonical WAT and module resources

**Files:**
- Modify: `src/build/codegen_component_marshal_module.zig`
- Modify: `src/build/codegen_component_marshal_wat.zig`
- Test: `src/build/codegen_component_marshal_wat.zig`
- Test: `src/build/codegen_component_marshal_module.zig`

**Interfaces:**
- Consumes: the Task 2 managed-text `MemoryPlan`.
- Produces: `(type $canonical_lower (func (param i32 i32 i32)))`, `$do_record` with `u32`/`do_text` fields, exported memory/realloc, byte copy, canonical call, and post-call free.

- [x] **Step 1: Add RED emitter assertions.** Assert that the exact plan requires three canonical params, contains `array.get_s $do_bytes`, `call $canonical_call` before the realloc free, and rejects GC-reference imports/indirect managed lower.
- [x] **Step 2: Run the focused emitter/module tests and capture failure.** Run `cd src && zig test main.zig --test-filter 'canonical marshal WAT.*managed|marshal module.*managed'`.
- [x] **Step 3: Implement flat text parameter emission.** Extend the canonical record type builder for text as two `i32` words and add the specialized root lower emitter that loads scalar and text bytes, allocates, copies, calls, then frees.
- [x] **Step 4: Ensure module resources are emitted.** Mark managed-text lower as using linear memory and realloc; keep result-area/indirect paths unchanged.
- [x] **Step 5: Run focused tests and parse generated WAT.** Confirm exact import type and operation order.

### Task 4: Add GC probe and ARC reference

**Files:**
- Create: `src/build/gc_marshal_record_managed_lower_probe.zig`
- Create: `src/gc_marshal_record_managed_lower_probe_main.zig`
- Create: `examples/gc-p3-runtime/marshal-record-managed-lower-arc.core.wat`
- Create: `examples/gc-p3-runtime/marshal-record-managed-lower-assembly.wit`
- Modify: `src/main.zig`

**Interfaces:**
- Consumes: manifest descriptor and Task 3 emitter.
- Produces: GC Core WAT that constructs `code=7`, `label="hello"`, and returns packed cleanup counts; ARC Core WAT that passes equivalent `code=7`/`hello` bytes through linear memory.

- [x] **Step 1: Add the probe test first.** Assert descriptor identity, three-parameter import, GC record/text construction, and counter instrumentation.
- [x] **Step 2: Run the probe test RED.** Run `cd src && zig test main.zig --test-filter 'managed-field record lower probe'` and capture the missing-probe failure.
- [x] **Step 3: Implement the probe wrapper.** Use the manifest route with `emit_realloc_counters=true`, append the `run` function, and reject source-hash mutation through the existing manifest loader.
- [x] **Step 4: Add the ARC reference WAT and assembly world.** Keep the same package/world/member identity, canonical `(i32 i32 i32)` import, linear memory, `hello` data, and one call.
- [x] **Step 5: Run Zig probe tests.** Confirm generated GC WAT has no GC reference in the canonical import.

### Task 5: Add host and ARC/GC equivalence runners and gates

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_managed_lower.rs`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_managed_lower_host_equivalence.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_manifest_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_manifest_equivalence.sh`

**Interfaces:**
- Consumes: GC/ARC Core WAT, assembly WIT, Wasmtime component callbacks.
- Produces: host evidence for `code=7`, `label=hello`, one call, allocations `1`, frees `1`; equivalence evidence with identical values and cleanup.

- [x] **Step 1: Add RED shell gates and runner targets.** Require exact tool version, three-param import, no GC reference, source-hash rejection, Component validation, and expected runner output.
- [x] **Step 2: Run the host gate RED.** Run `bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_manifest_host.sh`; expected failure until runner and probe exist.
- [x] **Step 3: Implement the Rust callback.** Decode the Component record parameter, validate `code` and `label`, count calls, and validate the packed cleanup result.
- [x] **Step 4: Implement the equivalence runner.** Run GC and ARC components independently and compare values, calls, allocation count, and free count.
- [x] **Step 5: Run both gates.** Confirm Wasmtime execution and equivalence pass.

### Task 6: Register evidence and run release gates

**Files:**
- Modify: `src/build/test/check_gc_g5c_residual_gate.sh`
- Modify: `src/build/test/check_gc_migration_inventory.sh`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `examples/gc-p3-runtime/README.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: passing C15-B focused host/equivalence gates.
- Produces: explicit bounded evidence while keeping general text/list record lower and G5c full cutover pending.

- [x] **Step 1: Add residual/inventory gate calls.** Keep the row labeled bounded/pending for general host/WIT marshalling and list/aggregate lower.
- [x] **Step 2: Update documentation.** Record exact flat ABI and cleanup contract; do not claim default-route or general aggregate support.
- [x] **Step 3: Run focused and toolchain gates.** Run C15-B host/equivalence, Core parse, Component embed/new/validate, and residual baseline.
- [x] **Step 4: Run repository verification.** Run `cd src && zig test main.zig`, `./src/build/test/run_tests.sh`, `cd src && zig build -Doptimize=ReleaseSmall`, `cargo fmt --check`, `git diff --check`, and migration inventory.
- [x] **Step 5: Record final evidence and remaining risks.** Report completed unit count in `N/6` format; leave push for explicit user instruction.
