# G5c Mixed `text` + `list<u32>` Lift Implementation Plan

> **For agentic workers:** Execute this plan task-by-task in the current checkout. Preserve unrelated dirty changes; do not reset, clean, commit, or push unless explicitly requested.

**Goal:** Add one hash-pinned synchronous default GC/WIT lift route for `Reading { code: u32, label: text, payload: [u32] }`.

**Architecture:** Reuse the existing manifest-backed record-lift emitter and measured list facts. Add only the descriptor/source-level host boundary, exact manifest layout, generated probe/runner, and default residual gates. All unadmitted shapes remain fail-closed or ARC-backed.

**Tech Stack:** Zig compiler, `.do` fixtures, WIT/component descriptors, Rust 2024 Wasmtime runner, Bash gates, and pinned `wasm-tools 1.255.0`.

**Spec:** `doc/superpowers/specs/2026-08-25-g5c-mixed-text-u32-list-lift-design.md`

## Global Constraints

- Keep GC-first v1 and ARC fallback for unsupported shapes.
- Accept only the exact descriptor and measured 20-byte layout in the spec.
- Keep canonical lift `(i32)` result-area ABI with no GC reference crossing it.
- Free label and payload linear spans exactly once after successful copies.
- Use only `wasm-tools 1.255.0`.
- Do not add public syntax, ownership syntax, Option/Result, async, resource, or generic aggregate inference.
- Preserve unrelated dirty-worktree changes; do not reset, clean, commit, or push.
- Keep `complete_rows=15 pending_rows=15` until the complete gate set passes; even then this route does not close full G5c.

---

### Task 1: Lock exact boundary admission with RED tests

**Files:**

- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Test input: inline source first; later add `src/build/test/compile_ok/639_gc_wit_mixed_text_u32_list_lift_host_boundary.do`

**Interfaces:**

- Consumes: existing host-boundary validator.
- Produces: a failing test for the exact `read -> Reading` descriptor before production admission exists; default dispatch is verified by the integration gate in Task 4.

- [x] **Step 1: Add the boundary RED test.**

  Add a test that tokenizes:

  ```do
  Reading {
      code u32
      label text
      payload [u32]
  }
  read = @host_func("demo:marshal-record-mixed-text-u32-list-lift/api@1.0.0", "read", () -> Reading)
  ```

  Call `validate(tokens, "demo:marshal-record-mixed-text-u32-list-lift/api.read@1.0.0/lift")` and assert success.

- [x] **Step 2: Run only the RED tests.**

  ```bash
  cd src
  zig test build/codegen_gc_wit_host_boundary.zig --test-filter 'mixed text u32-list lift'
  ```

  Expected: failure with `UnsupportedGcWitHostDescriptor`, proving the new behavior is not already admitted.

### Task 2: Add source, WIT, manifest, and typed-lift RED coverage

**Files:**

- Add: `examples/gc-p3-runtime/marshal-record-mixed-text-u32-list-lift-manifest-source.wit`
- Add: `doc/wit/gc_marshal_record_mixed_text_u32_list_lift_imports.wit`
- Add: `examples/gc-p3-runtime/marshal-record-mixed-text-u32-list-lift-assembly.wit`
- Add: `examples/gc-p3-runtime/ordinary-host-record-mixed-text-u32-list-lift-call.do`
- Modify: `doc/wit/gc_descriptor_manifest.json`
- Modify: `src/build/codegen_gc_plans_test.zig`

**Interfaces:**

- Consumes: the exact source and layout in the spec.
- Produces: one manifest descriptor and a measured plan test requiring the 20-byte result area, text child, and `list<u32>` child.

- [x] **Step 1: Add exact WIT/world/assembly/Do sources.**

  The WIT package is `demo:marshal-record-mixed-text-u32-list-lift@1.0.0`; the world imports `api` and exports `run: func() -> u32` and `stats: func() -> u32`. The Do fixture declares the exact synchronous host function and an empty `start()`.

- [x] **Step 2: Compute and record the source hash.**

  ```bash
  { cat examples/gc-p3-runtime/marshal-record-mixed-text-u32-list-lift-manifest-source.wit; printf '\n'; cat doc/wit/gc_marshal_record_mixed_text_u32_list_lift_imports.wit; printf '\n'; } | sha256sum
  ```

  Add one manifest entry with record `reading`, no params, result `reading`, direction `lift`, measured root/children from the spec, and the computed `source_sha256`. Do not alter existing entries.

- [x] **Step 3: Add typed-plan RED assertions and run them.**

  Assert record field count `3`, root size/alignment `20/4`, child offsets `0/4/12`, text pointer/length `0/4`, list element size/stride/alignment `4/4/4`, capacity `3`, and `operations == canonical_call, validate_linear_range, copy_from_linear, construct_gc_value, publish_gc_root` (the exact lift-plan sequence; linear frees are emitter actions, not plan operations). Run:

  ```bash
  cd src
  zig test build/codegen_gc_plans_test.zig --test-filter 'mixed text u32-list lift'
  ```

  Expected: the manifest/plan lookup fails before the descriptor and route are implemented; fix only fixture setup errors, not the missing route.

### Task 3: Implement exact validator/dispatch and lift probe

**Files:**

- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/run.zig`
- Modify: `src/build/codegen_gc_wit_marshal.zig`
- Add: `src/build/gc_marshal_record_mixed_text_u32_list_lift_probe.zig`
- Add: `src/gc_marshal_record_mixed_text_u32_list_lift_probe_main.zig`

**Interfaces:**

- Consumes: the manifest descriptor and exact source-level host boundary.
- Produces: `mixed_text_u32_list_lift_descriptor`, exact `Reading` field validation, compiler dispatch, and a generated Core probe using the existing record-lift emitter.

- [x] **Step 1: Add the descriptor constants/spec.**

  Add exact fields `code u32`, `label text`, `payload [u32]` with `shape = .lift_record`. Dispatch only the exact locator/member pair and reject async, extra, reordered, or mismatched declarations before WAT.

- [x] **Step 2: Add the probe with measured layout.**

  Load the manifest-owned descriptor, emit the marshal function, build a `$run` that sums code, label length, and the first three `$do_u32` elements, and export `run`. Add an emitter test for `(type $canonical_lift (func (param i32)))`, `$do_bytes`, `$do_u32`, `struct.new $do_record`, and exactly two realloc frees.

- [x] **Step 3: Run focused GREEN tests.**

  ```bash
  cd src
  zig test build/codegen_gc_wit_host_boundary.zig --test-filter 'mixed text u32-list lift'
  zig test build/codegen_gc_wit_marshal.zig --test-filter 'mixed text u32-list lift'
  zig test build/run.zig --test-filter 'mixed text u32-list lift'
  zig run gc_marshal_record_mixed_text_u32_list_lift_probe_main.zig -- /tmp/mixed-text-u32-list-lift.wat ..
  wasm-tools parse /tmp/mixed-text-u32-list-lift.wat -o /tmp/mixed-text-u32-list-lift.wasm
  ```

  Expected: all focused tests pass, canonical import has no GC reference, and WAT contains both managed-array copies and `struct.new $do_record`.

### Task 4: Add host, equivalence, negative, and default-route gates

**Files:**

- Add: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_mixed_text_u32_list_lift.rs`
- Add: `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_u32_list_lift_manifest_host.sh`
- Add: `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_u32_list_lift_manifest_equivalence.sh`
- Add: `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_u32_list_lift_negative.sh`
- Add: `examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lift_host.sh`
- Add: `examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lift_equivalence.sh`
- Add: `examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_u32_list_lift_negative.sh`
- Add: `src/build/test/compile_ok/639_gc_wit_mixed_text_u32_list_lift_host_boundary.do`
- Add: `src/build/test/compile_err/640_gc_wit_mixed_text_u32_list_lift_async.do` and `.expect`
- Add: `src/build/test/compile_err/641_gc_wit_mixed_text_u32_list_lift_locator.do` and `.expect`
- Add: `src/build/test/compile_err/642_gc_wit_mixed_text_u32_list_lift_member.do` and `.expect`
- Add: `src/build/test/compile_err/643_gc_wit_mixed_text_u32_list_lift_reordered.do` and `.expect`
- Add: `src/build/test/compile_err/644_gc_wit_mixed_text_u32_list_lift_u8_payload.do` and `.expect`
- Add: `src/build/test/compile_err/645_gc_wit_mixed_text_u32_list_lift_text_payload.do` and `.expect`
- Add: `src/build/test/compile_err/646_gc_wit_mixed_text_u32_list_lift_extra_field.do` and `.expect`
- Add: `src/build/test/compile_err/647_gc_wit_mixed_text_u32_list_lift_record_name.do` and `.expect`

**Interfaces:**

- Consumes: compiler output from Task 3 and the existing `wasm-tools`/Wasmtime runner conventions.
- Produces: host execution, ARC/GC equivalence, negative fail-closed, and ordinary default-route evidence.

- [x] **Step 1: Add the Rust host runner.**

  The host returns `Reading { code: 7, label: "hello", payload: [10,20,5] }`; it requires one callback, observes `run=47`, `stats=34`, and reports exactly two linear frees.

- [x] **Step 2: Add manifest host/equivalence scripts.**

  Both scripts pin `wasm-tools 1.255.0`, build the compiler in Debug, parse/validate the component, reject canonical imports containing `(ref`, and invoke the Rust runner. Equivalence runs the generated GC Core and the checked-in ARC Core through the same Component world and requires `47/47`, `34/34`, and callback `1/1`.

- [x] **Step 3: Add eight source-level negative cases.**

  Each case must fail before WAT and leave no output artifact: async marker, locator drift, member drift, field reorder, `[u8]` payload, `text` payload, extra field, and record-name drift.

- [x] **Step 4: Add default-route scripts and residual wiring.**

  The ordinary `@host_func` fixture must emit GC-only WAT for the exact descriptor. An unrelated ordinary host record must retain ARC fallback. Add host/equivalence/negative calls to `check_gc_g5c_residual_gate.sh` and its static wiring test.

### Task 5: Full verification and documentation handoff

**Files:**

- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/pending_blocked.md`
- Modify: `examples/gc-p3-runtime/README.md`

**Interfaces:**

- Consumes: all evidence scripts and focused tests from Tasks 1–4.
- Produces: current-state documentation and a verified handoff for the next bounded shape.

- [x] **Step 1: Run focused and full verification.**

  ```bash
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  ./src/build/test/check_gc_default_build_gate.sh
  ./src/build/test/check_gc_g5c_residual_gate.sh
  ./src/build/test/run_release_smoke.sh
  bash src/build/test/check_gc_migration_inventory.sh
  git diff --check
  ```

  The inventory command is expected to exit `1` with `complete_rows=15 pending_rows=15`; all other commands must exit `0`.

- [x] **Step 2: Update current-state docs.**

  Record the exact descriptor, measured ABI, host output, equivalence output, negative fixture range, pinned tool version, and the fact that general aggregate/async/resource/ownership/full cutover remain pending. Do not change inventory status.

- [x] **Step 3: Re-audit scope and hand off.**

  Confirm only the new bounded route changed, no unrelated dirty changes were overwritten, no public syntax was added, and no new P0/P1 blocker exists. Leave the worktree uncommitted and unpushed unless the user separately requests delivery.

## Completion evidence (2026-08-25)

- `zig test main.zig`: `639/639` passed.
- Focused manifest/default host, equivalence, and negative gates passed.
- Default GC build/parse gate: `81 fixtures` passed.
- G5c residual baseline passed; migration inventory intentionally returned exit `1`
  with `complete_rows=15 pending_rows=15`.
- ReleaseSmall/release smoke and `git diff --check` remain required after the
  documentation edits; this plan does not claim full G5c cutover.

## Handoff

The next bounded shape is `Reading { code: u32, label: text, payload: [u8] }`.
It retains the 20-byte root and canonical `(i32)` lift ABI, adds only the
measured byte-list child (`stride=1`, capacity `4`), and must receive its own
design, manifest, probe, negative, host/equivalence, default, and residual gates.
