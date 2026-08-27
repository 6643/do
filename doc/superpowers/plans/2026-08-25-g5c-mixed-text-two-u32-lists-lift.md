# G5c Mixed `text` + Two `list<u32>` Lift Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan task-by-task with review checkpoints. Preserve unrelated dirty changes in the current `main` checkout.

**Goal:** Add one hash-pinned synchronous default GC/WIT lift route for `Reading { code: u32, label: text, first: [u32], second: [u32] }`.

**Architecture:** Reuse the manifest-backed `LoadedRequest`/`SyncValuePlan` route and the existing result-area lift emitter. Add one fixed descriptor and one three-span lift emitter variant; no generic aggregate inference or second ownership model is introduced. Unsupported shapes remain fail-closed or on the ARC fallback.

**Tech Stack:** Zig compiler, `.do` fixtures, WIT/component descriptors, Rust 2024 Wasmtime runner, Bash gates, and pinned `wasm-tools 1.255.0`.

**Spec:** `doc/superpowers/specs/2026-08-25-g5c-mixed-text-two-u32-lists-lift-design.md`

## Global Constraints

- Accept only descriptor `demo:marshal-record-mixed-text-two-u32-lists-lift/api.read@1.0.0/lift` and the exact 28-byte layout in the spec.
- Keep canonical lift `(i32)` result-area ABI with no GC reference crossing it.
- Invoke the canonical host callback exactly once; after it returns, guard the
  result area and all three linear spans before the first load/copy.
- Never retry or copy after a runtime guard failure; retain cleanup-mask behavior
  on traps.
- Construct/publish the GC record before freeing `second`, `first`, then `label`
  exactly once.
- Use only `wasm-tools 1.255.0` and the pinned Wasmtime/Rust runner.
- Do not add public syntax, ownership syntax, Option/Result, async, resource, cancellation, or generic aggregate inference.
- Preserve unrelated dirty-worktree changes; do not reset, clean, commit, or push.
- Keep `complete_rows=15 pending_rows=15`; inventory exit `1` remains deliberate.

---

### Task 1: Lock exact source admission with RED tests (complete 2026-08-25)

**Files:**

- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Test input: inline source first; later add `src/build/test/compile_ok/673_gc_wit_mixed_text_two_u32_lists_lift_host_boundary.do`

**Interfaces:**

- Consumes: existing `descriptor_id_for_host` and source-level validator.
- Produces: a failing test for the exact `read -> Reading` descriptor before
  production admission exists.

- [x] **Step 1: Add the boundary RED test.**

  Tokenize this exact source and assert that the new descriptor is accepted
  after implementation:

  ```do
  Reading {
      code u32
      label text
      first [u32]
      second [u32]
  }
  read = @host_func("demo:marshal-record-mixed-text-two-u32-lists-lift/api@1.0.0", "read", () -> Reading)
  ```

  Before adding admission, the test must fail with
  `UnsupportedGcWitHostDescriptor` or the equivalent unknown-descriptor error.

- [x] **Step 2: Run only the RED test.**

  ```bash
  cd src
  zig test build/codegen_gc_wit_host_boundary.zig --test-filter 'mixed text two u32-list lift'
  ```

  Expected: the new case fails because no production descriptor has been
  registered yet. Do not weaken the assertion to make the RED phase pass.

### Task 2: Add exact source, WIT, manifest, and compiler fixtures (complete 2026-08-25)

**Files:**

- Create: `examples/gc-p3-runtime/marshal-record-mixed-text-two-u32-lists-lift-manifest-source.wit`
- Create: `doc/wit/gc_marshal_record_mixed_text_two_u32_lists_lift_imports.wit`
- Create: `examples/gc-p3-runtime/marshal-record-mixed-text-two-u32-lists-lift-assembly.wit`
- Create: `examples/gc-p3-runtime/ordinary-host-record-mixed-text-two-u32-lists-lift-call.do`
- Modify: `doc/wit/gc_descriptor_manifest.json`
- Create: `src/build/test/compile_ok/673_gc_wit_mixed_text_two_u32_lists_lift_host_boundary.do`
- Create: `src/build/test/compile_err/674_gc_wit_mixed_text_two_u32_lists_lift_async.do` and `.expect`
- Create: `src/build/test/compile_err/675_gc_wit_mixed_text_two_u32_lists_lift_locator.do` and `.expect`
- Create: `src/build/test/compile_err/676_gc_wit_mixed_text_two_u32_lists_lift_member.do` and `.expect`
- Create: `src/build/test/compile_err/677_gc_wit_mixed_text_two_u32_lists_lift_reordered.do` and `.expect`
- Create: `src/build/test/compile_err/678_gc_wit_mixed_text_two_u32_lists_lift_u8_field.do` and `.expect`
- Create: `src/build/test/compile_err/679_gc_wit_mixed_text_two_u32_lists_lift_text_field.do` and `.expect`
- Create: `src/build/test/compile_err/680_gc_wit_mixed_text_two_u32_lists_lift_extra_field.do` and `.expect`
- Create: `src/build/test/compile_err/681_gc_wit_mixed_text_two_u32_lists_lift_record_name.do` and `.expect`

**Interfaces:**

- Consumes: the exact source/WIT pair and hash from the spec.
- Produces: one descriptor with result-area layout `0/4/12/20`, capacities
  `3/2`, and canonical lift `(i32)`.

- [x] **Step 1: Add the exact WIT/world/assembly/Do sources.**

  The manifest source must contain the `reading` record and `read: func() ->
  reading`; the world must import `api` and export `run: func() -> u32` and
  `stats: func() -> u32`. The Do positive fixture must declare the exact host
  function and call `read()` once from `start()` so the compiler path is
  exercised.

- [x] **Step 2: Compute the source hash and add the manifest record.**

  ```bash
  python3 - <<'PY'
  import hashlib
  from pathlib import Path
  source = Path("examples/gc-p3-runtime/marshal-record-mixed-text-two-u32-lists-lift-manifest-source.wit").read_bytes()
  world = Path("doc/wit/gc_marshal_record_mixed_text_two_u32_lists_lift_imports.wit").read_bytes()
  print("sha256:" + hashlib.sha256(source + b"\n" + world + b"\n").hexdigest())
  PY
  ```

  Expected: `sha256:518edd667347a947c1bb3b912b4cf3579be0288567086b7e4b45dc6345964e75`.
  Add the descriptor with `direction: "lift"`, result area `28`, alignment `4`,
  text offsets `4/8`, list offsets `12/16` and `20/24`, capacities `3/2`, and
  stride `4`.

- [x] **Step 3: Add positive and negative fixtures.**

  The eight negative fixtures must cover async declaration, locator drift,
  member drift, field reorder, `[u8]` substitution, `text` substitution,
  extra field, and record-name drift. Each `.expect` file must assert the
  descriptor-specific fail-closed diagnostic and no WAT may be produced.

- [x] **Step 4: Run parser, manifest, and compile-mode RED checks.**

  ```bash
  (cd src && zig test build/codegen_gc_wit_host_boundary.zig --test-filter 'mixed text and two u32-list lift declaration is accepted')
  (cd src && zig test build/codegen_component_descriptor_manifest.zig --test-filter 'mixed text and two u32-list lift')
  ./src/build/test/run_tests.sh
  ```

  Expected: the positive fixture is accepted by a non-empty focused test,
  all eight negatives reject before WAT, and the manifest hash/layout facts
  agree with the spec.

### Task 3: Implement the measured three-span GC lift emitter (complete 2026-08-25)

**Files:**

- Modify: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/build/codegen_gc_wit_marshal.zig`
- Modify: `src/build/codegen_component_descriptor_manifest.zig`
- Modify: `src/build/codegen_component_manifest_route.zig`
- Modify: `src/build/test/check_gc_default_build_gate.sh`
- Modify: `src/build/test/check_gc_g5c_residual_gate.sh`
- Test: `src/build/codegen_gc_wit_marshal.zig`, `src/build/codegen_component_marshal_wat.zig`, and `src/build/codegen_gc_plans_test.zig`

**Interfaces:**

- Consumes: one loaded manifest request and the existing `SyncValuePlan` with
  four record children.
- Produces: `marshal` returning `$do_record`, one `(param i32)` canonical lift
  import, three GC array copies, and reverse exactly-once cleanup.

- [x] **Step 1: Make the RED emitter assertions explicit.**

  Assert that the new descriptor emits all of the following before adding the
  branch:

  ```text
  (type $canonical_lift (func (param i32)))
  array.new_default $do_bytes
  array.new_default $do_u32       # first
  array.new_default $do_u32       # second
  struct.new $do_record
  runtime allocation counter `3` and free counter `3`
  no canonical import containing (ref
  ```

- [x] **Step 2: Add the smallest fixed descriptor branch.**

  Reuse the existing result-area guard, span validator, `$do_bytes` copy, and
  `$do_u32` copy helpers. Only add the second measured list child and the
  descriptor-specific record construction. Do not add a general loop over
  arbitrary list fields in the emitter.

- [x] **Step 3: Enforce cleanup ordering.**

  The generated WAT must call the three frees in this order:

  ```text
  second span -> first span -> label span
  ```

  Allocation failure and bounds traps must use the existing cleanup mask. The
  canonical callback is called exactly once before runtime result-area/span
  validation; a failed guard must not copy, repeat, or hide the failure.

- [x] **Step 4: Run focused GREEN tests.**

  ```bash
  cd src
  zig test build/codegen_gc_wit_host_boundary.zig --test-filter 'mixed text and two u32-list lift declaration is accepted'
  zig test build/codegen_gc_wit_marshal.zig --test-filter 'G5c mixed text and two u32-list lift'
  zig test build/codegen_component_manifest_route.zig --test-filter 'mixed text and two u32-list lift'
  zig test build/codegen_gc_plans_test.zig --test-filter 'mixed text and two u32-list lift'
  zig test build/codegen_component_marshal_wat.zig --test-filter 'span'
  ```

  Expected: every focused filter runs at least one test, WAT has three
  allocations/frees at runtime, and the canonical boundary remains
  GC-reference-free.

### Task 4: Add host, equivalence, negative, and default-route gates (complete 2026-08-25)

**Files:**

- Create: `examples/gc-p3-runtime/marshal-record-mixed-text-two-u32-lists-lift-arc.core.wat`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_mixed_text_two_u32_lists_lift.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_two_u32_lists_lift_manifest_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_two_u32_lists_lift_manifest_equivalence.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_two_u32_lists_lift_negative.sh`
- Create: `examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_two_u32_lists_lift_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_two_u32_lists_lift_equivalence.sh`
- Create: `examples/gc-p3-runtime/test_gc_default_host_route_mixed_text_two_u32_lists_lift_negative.sh`
- Modify: `src/build/test/check_gc_g5c_residual_gate.sh`
- Modify: `src/build/test/check_gc_g5c_residual_gate_test.sh`

**Interfaces:**

- Consumes: the compiler output from Task 3 and the existing Rust/Wasmtime
  runner conventions.
- Produces: host execution, ARC/GC equivalence, negative fail-closed, and
  ordinary default-route evidence.

- [x] **Step 1: Add the Rust host adapter.**

  The `read` callback must return `Reading { code: 7, label: "hello", first:
  [10,20,5], second: [3,4] }`, reject any other signature, and require exactly
  one callback. The runner must require `(run, stats, calls) == (54, 51, 1)` and
  print `allocations=3 frees=3`.

- [x] **Step 2: Add manifest host/equivalence scripts.**

  Each script must pin `wasm-tools 1.255.0`, build Debug, parse/validate the
  Component, reject canonical `(ref`, and invoke the runner. Equivalence must
  compare the generated GC component and fixed ARC component and require
  `54/54`, `51/51`, and `1/1`.

- [x] **Step 3: Add the eight negative invocations.**

  Each negative must fail before WAT and leave no output artifact. The script
  must fail if any rejected input reaches Component assembly.

- [x] **Step 4: Add default-route wiring.**

  The ordinary `@host_func` fixture must emit GC-only WAT for the exact
  descriptor. An unrelated ordinary host record must retain ARC fallback. Add
  all host/equivalence/negative scripts to the residual gate and static wiring
  test; update the default fixture count by exactly one positive fixture plus
  the negative cases.

### Task 5: Run full verification and update current-state handoff (complete 2026-08-25)

**Files:**

- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/pending_blocked.md`
- Modify: `examples/gc-p3-runtime/README.md`
- Modify: `CHANGELOG.md`

**Interfaces:**

- Consumes: all evidence scripts and focused tests from Tasks 1–4.
- Produces: a verified bounded promotion and a fresh residual design gate; no
  migration-row closure.

- [x] **Step 1: Run focused and full verification.**

  ```bash
  (cd src && zig test main.zig)
  ./src/build/test/run_tests.sh
  ./src/build/test/check_gc_default_build_gate.sh
  ./src/build/test/check_gc_g5c_residual_gate.sh
  ./src/build/test/run_release_smoke.sh
  set +e
  bash src/build/test/check_gc_migration_inventory.sh
  inventory_status=$?
  set -e
  test "$inventory_status" -eq 1
  git diff --check
  ```

  Expected: all commands except inventory exit `0`; inventory reports
  `complete_rows=15 pending_rows=15` and exit `1`; default fixture count
  increases by the exact positive admission count.

- [x] **Step 2: Update current-state docs with exact facts.**

  Record descriptor id, source hash, 28-byte layout, canonical `(i32)`,
  `54/51/1` host oracle, `3/3` cleanup, negative fixture range `674–681`,
  pinned toolchain, and the continued non-goals. Preserve historical
  checkpoints and do not claim full G5c cutover.

- [x] **Step 3: Re-audit scope and hand off.**

  Confirm only this bounded route changed, no public syntax was added, no
  canonical GC reference crossed the boundary, and no unrelated dirty changes
  were overwritten. Leave the worktree uncommitted and unpushed unless the user
  separately requests delivery.

## Completion criteria

This plan is complete: Tasks 1–5 pass, the exact host/equivalence oracles are
observed (`54/51/1`, `54/54`, `51/51`, `1/1`, `3/3` allocations/frees), all
negative fixtures reject before WAT, the default gate covers `85 fixtures`, the
full regression is `pass=1380 fail=0 skip=3`, Zig is `678/678`, and inventory
remains `complete_rows=15 pending_rows=15` with exit `1`. The current docs state
that this is fixed-shape evidence only; it does not close full G5c.
