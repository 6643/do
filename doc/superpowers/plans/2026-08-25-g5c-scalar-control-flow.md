# G5c Scalar Control-Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admit only the bounded synchronous scalar `if/else`, `else-if`, and guard-return forms through the default typed-GC route.

**Architecture:** Add a separate fail-closed admission predicate in `codegen_pipeline.zig` and reuse the existing `codegen_gc_sync.zig` control-flow emitter. Keep managed candidates, the ARC fallback, imported module graphs, host/WIT, async/resource, loops, `defer`, recursion, and the migration ledger unchanged.

**Tech Stack:** Zig compiler, `.do` fixtures, WAT, `wasm-tools 1.255.0`, Bash gates, and the existing default GC test harness.

**Spec:** `doc/superpowers/specs/2026-08-25-g5c-scalar-control-flow-design.md`

## Global Constraints

- Keep the GC-first v1 memory contract; this is an admission slice, not a full GC cutover.
- Do not add or change public syntax, `own<T>`, `borrow<T>`, `ref<T>`, `Option`, `Result`, async, resource, or WIT semantics.
- Admit only Core Wasm scalar parameters, one scalar result, and the three listed control-flow shapes.
- Reject imported module graphs, host/WIT, managed values, loops, `defer`, recursion, arbitrary producer expressions, and unsupported branches before selecting the route.
- Keep `wasm-tools 1.255.0` as the only accepted WAT/Component tool version.
- Preserve `complete_rows=15 pending_rows=15`; this plan cannot mark an inventory row complete.
- Preserve all unrelated dirty-worktree changes. Do not reset, clean, checkout, format unrelated files, commit, or push unless separately requested.

### Task 1: Freeze the baseline and write RED admission tests

**Files:**
- Read: `src/build/codegen_pipeline.zig`
- Read: `doc/superpowers/specs/2026-08-25-g5c-scalar-control-flow-design.md`
- Test: `src/build/codegen_pipeline.zig`

**Interfaces:**
- Consumes: `emit_default_wat_for_source`, `try_emit_default_gc_sync`, and the existing scalar-leaf tests.
- Produces: failing tests that prove the desired control-flow slice is currently not admitted, without changing existing negative expectations.

- [x] **Step 1: Capture the worktree boundary**

```bash
git status --short --branch
git diff --stat
git diff -- src/build/codegen_pipeline.zig
```

Record the existing dirty boundary; do not stage or remove any unrelated file.

- [x] **Step 2: Add the positive `if/else` RED test**

Add this Zig test beside the scalar-leaf route tests:

```zig
test "default pipeline admits scalar if else through GC" {
    const source =
        \\choose(value i32) -> i32 {
        \\    if @eq(value, 0) {
        \\        return 7
        \\    } else {
        \\        return value
        \\    }
        \\}
        \\start() {}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root branch_join") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}
```

- [x] **Step 3: Add the positive guard-return and `else-if` RED tests**

Use the same helper and assert the `gc-root guard_join` marker for this source:

```do
guard(value i32) -> i32 {
    if @eq(value, 0) return 7
    return value
}

choose_chain(value i32) -> i32 {
    if @eq(value, 0) {
        return 7
    } else if @eq(value, 1) {
        return 8
    } else {
        return value
    }
}

start() {}
```

Keep the assertions separate so a future regression identifies which form
lost admission.

- [x] **Step 4: Run the RED tests**

```bash
cd src
zig test build/codegen_pipeline.zig
```

Expected before implementation: the new positive assertions fail because the
current scalar-leaf predicate rejects control-flow bodies. Existing tests must
continue to pass; a parser or syntax failure is not an acceptable RED result.

### Task 2: Implement the scalar-control-flow admission predicate

**Files:**
- Modify: `src/build/codegen_pipeline.zig` near `gc_sync_scalar_leaf_header`, `gc_sync_scalar_leaf_body`, and `try_emit_default_gc_sync`
- Test: `src/build/codegen_pipeline.zig`

**Interfaces:**
- Consumes: token helpers `find_stmt_end`, `find_top_level_block_open`, `find_matching_in_range`, scalar header validation, and the existing `BodyEmitter` behavior.
- Produces: `gc_sync_scalar_control_flow_expr(tokens, start_idx, end_idx) bool`, `gc_sync_scalar_control_flow_body(tokens, start_idx, end_idx) bool`, `tokens_have_gc_sync_scalar_control_flow_candidate(tokens) bool`, and a route-specific candidate flag used by `try_emit_default_gc_sync`.

- [x] **Step 1: Add a body-shape scanner with explicit branches**

Implement `gc_sync_scalar_control_flow_expr(tokens, start_idx, end_idx) bool`
as the expression boundary. It accepts one scalar identifier, one numeric
literal, or the exact pure scalar intrinsic form `@eq(<scalar-atom>,
<scalar-atom>)`; it rejects calls to user functions, host bindings, managed
values, and every other producer form. Then implement a bounded body scanner
that accepts only:

```text
if <scalar-condition> { return <scalar-expr> } else { return <scalar-expr> }
if <scalar-condition> { return <scalar-expr> } else if ... else { return <scalar-expr> }
if <scalar-condition> return <scalar-expr>; return <scalar-expr>
```

Use `find_stmt_end` for statement boundaries, `find_top_level_block_open` and
`find_matching_in_range` for block matching, and the existing scalar expression
admission helper rather than introducing a second expression parser. Reject
any assignment, call producer, managed token, loop, `defer`, or extra statement.

- [x] **Step 2: Require scalar headers for every non-`start` function**

Reuse `gc_sync_scalar_leaf_header` for parameter/result shape. Skip `start`
only for candidate discovery; still reject unsupported tokens in its body so a
managed or asynchronous `start` cannot be pulled onto this route.

- [x] **Step 3: Add whole-program exclusions**

Before returning true, reject `tokens_require_async_lowering(tokens)`, host/WIT
bindings, managed declarations, unsupported header shapes, recursion, and any
loop or `defer` token. Keep this predicate independent from
`tokens_have_gc_sync_candidate`; do not relax the managed route.

- [x] **Step 4: Integrate route ordering and imported-graph guard**

In `try_emit_default_gc_sync`, compute the new candidate only when both the
managed and scalar-leaf candidates are false. Treat it like scalar-leaf for
`graph_has_imported_module` rejection and for converting only
`is_gc_sync_admission_rejection` into `null`. Keep capability errors from
managed candidates as errors, and keep the existing host-route checks.

- [x] **Step 5: Run the focused suite**

```bash
cd src
zig test build/codegen_pipeline.zig
```

Expected: all existing tests and the new `if/else`, `else-if`, and guard tests
pass; WAT contains no `__arc_` marker for the positive cases.

### Task 3: Lock negative routing and add the real fixture gate

**Files:**
- Create: `examples/gc-p3-runtime/scalar-control-flow.do`
- Create: `examples/gc-p3-runtime/test_do_gc_scalar_control_flow.sh`
- Modify: `src/build/test/check_gc_default_build_gate.sh`
- Test: existing scalar negative tests in `src/build/codegen_pipeline.zig` and `src/build/test/compile_err/16_imported_func_missing_helper_no_global_fallback.do`

**Interfaces:**
- Consumes: the new admission predicate and default `do build` route.
- Produces: one reproducible positive fixture and a no-ARC/wasm-tools gate; existing loop, `defer`, recursion, host/WIT, and imported-module rejection remains locked.

- [x] **Step 1: Create the positive fixture**

Create `examples/gc-p3-runtime/scalar-control-flow.do` with exactly:

```do
choose(value i32) -> i32 {
    if @eq(value, 0) {
        return 7
    } else {
        return value
    }
}

guard(value i32) -> i32 {
    if @eq(value, 0) return 7
    return value
}

choose_chain(value i32) -> i32 {
    if @eq(value, 0) {
        return 7
    } else if @eq(value, 1) {
        return 8
    } else {
        return value
    }
}

start() {}
```

- [x] **Step 2: Add the standalone WAT gate**

Create `test_do_gc_scalar_control_flow.sh` using the neighboring GC fixture
gates and these assertions:

```bash
"$DO_BIN" build "$fixture" -o "$wat_path"
"$WASM_TOOLS_BIN" parse "$wat_path" -o "$wasm_path"
rg -q ';; gc-sync ' "$wat_path"
rg -q ';; gc-root branch_join' "$wat_path"
rg -q ';; gc-root guard_join' "$wat_path"
! rg -q '__arc_' "$wat_path"
test -s "$wasm_path"
```

Use only `DO_BIN`, `WASM_TOOLS_BIN`, and a temporary directory; do not check in
generated WAT or Wasm.

- [x] **Step 3: Add the fixture to the default manifest**

Insert `scalar-control-flow.do` in the sorted manifest in
`check_gc_default_build_gate.sh`. Add a named branch that requires both GC
join markers and no `__arc_`; retain the existing scalar-leaf and managed
assertions unchanged. The manifest count is expected to become 78.

- [x] **Step 4: Run focused negative and positive gates**

```bash
cd /home/_/._/_/do
WASM_TOOLS_BIN="$(command -v wasm-tools)" \
DO_BIN="$(pwd)/bin/do" \
bash examples/gc-p3-runtime/test_do_gc_scalar_control_flow.sh

cd src
zig test build/codegen_pipeline.zig
```

Also run the existing imported-helper compile-error fixture and confirm its
diagnostic remains `NoMatchingCall`; no imported module may be admitted by the
new route.

### Task 4: Synchronize documentation without changing migration status

**Files:**
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `examples/gc-p3-runtime/README.md`

**Interfaces:**
- Consumes: the verified fixture/gate output from Tasks 2 and 3.
- Produces: one consistent current-state description of the scalar-control-flow boundary.

- [x] **Step 1: Record the exact admission**

State that default typed GC now admits pure scalar `if/else`, `else-if`, and
guard-return functions, with `branch_join`/`guard_join` markers and no ARC
marker. State that the route has no grammar or public API change.

- [x] **Step 2: Record exclusions and fallback**

Explicitly list loops, `defer`, recursion, imported graphs, managed values,
host/WIT, async/resource, arbitrary producer expressions, and unsupported
scalar calls as fallback/fail-closed. Do not imply that all scalar control flow
or all GC functions are now supported.

- [x] **Step 3: Preserve the inventory statement and commands**

Keep `complete_rows=15 pending_rows=15` and document that this slice does not
close G5c or authorize full GC cutover. Add the focused Zig test, standalone
fixture gate, default-build gate, and `wasm-tools 1.255.0` requirement.

- [x] **Step 4: Check documentation drift**

```bash
git diff --check
rg -n "scalar-control-flow|branch_join|guard_join|complete_rows=15 pending_rows=15|wasm-tools 1\.255\.0" \
  doc/start_here.md doc/roadmap_status.md examples/gc-p3-runtime/README.md
```

### Task 5: Run the phase-wide verification and hand off the next slice

**Files:**
- Read/verify: `src/build/test/run_tests.sh`
- Read/verify: `src/build/test/run_release_smoke.sh`
- Read/verify: `src/build/test/check_gc_default_build_gate.sh`
- Read/verify: `src/build/test/check_gc_g5c_residual_gate.sh`
- Read/verify: `src/build/test/check_gc_semantic_equivalence.sh`
- Read/verify: `src/build/test/check_gc_migration_inventory.sh`

**Interfaces:**
- Consumes: all code, fixture, gate, and documentation changes above.
- Produces: a verified handoff with the intentional pending inventory visible.

- [x] **Step 1: Run the focused compiler tests**

```bash
cd /home/_/._/_/do/src
zig test build/codegen_pipeline.zig
```

Expected: all tests pass, including the new control-flow cases.

- [x] **Step 2: Run the repository regression and release smoke**

```bash
cd /home/_/._/_/do
./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
```

Expected: no existing fixture or diagnostic regression.

- [x] **Step 3: Run all GC gates**

```bash
bash src/build/test/check_gc_default_build_gate.sh
bash src/build/test/check_gc_g5c_residual_gate.sh
bash src/build/test/check_gc_semantic_equivalence.sh
```

Expected: default, residual, and equivalence gates pass; no ARC marker is
introduced in any admitted output.

- [x] **Step 4: Verify the intentionally incomplete inventory**

```bash
set +e
bash src/build/test/check_gc_migration_inventory.sh
status=$?
set -e
test "$status" -ne 0
```

Expected output includes `complete_rows=15 pending_rows=15`; this non-zero result
must be reported as an open migration ledger, not hidden or converted to a
pass.

- [x] **Step 5: Perform the final diff check and leave delivery explicit**

```bash
git diff --check
git status --short --branch
```

Do not commit or push in this phase without a separate delivery instruction;
the repository contains unrelated dirty worktree changes that must remain
untouched.

## Exit criteria

The phase is complete only when Tasks 1-5 pass, the fixture and docs agree on
the same bounded boundary, all existing negative routes remain locked, and the
inventory still reports `complete_rows=15 pending_rows=15`. The next design
decision after this phase is a separate admission review for the next scalar
shape; it is not automatic authorization for loops, general calls, host/WIT,
async/resource, or full G5c cutover.
