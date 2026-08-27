# G5c Scalar Leaf Admission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close one verifiable G5c compiler slice for synchronous functions whose parameters and result are pure Core Wasm scalars, while preserving fail-closed routing for all managed, control-flow, host/WIT, and async shapes.

**Architecture:** The existing GC pipeline admission in `src/build/codegen_pipeline.zig` remains the only routing point. A scalar-leaf candidate is admitted only when every non-`start` function has scalar parameters, one scalar result, and a single direct `return` expression; unsupported shapes continue through the existing ARC fallback. The slice is proven by a real `.do` build, WAT parsing with the pinned toolchain, explicit no-ARC checks, and negative routing tests.

**Tech Stack:** Zig compiler, `.do` fixtures, WAT, `wasm-tools 1.255.0`, Wasmtime GC validation, Bash gates.

**Spec:** `doc/memory.md`, `doc/design/2026-08-11-gc-first-memory-decision.md`, and the current migration ledger in `src/build/test/check_gc_migration_inventory.sh`.

## Global Constraints

- Keep the GC-first v1 memory contract; do not reintroduce ARC as the target runtime.
- Do not add or widen `own<T>`, `borrow<T>`, `ref<T>`, `Result`, `Option`, or async syntax in this slice.
- Admit only synchronous scalar parameters/results with one direct return expression.
- Reject recursion, loop, defer, host/WIT bindings, managed values, tuples, unions, resources, and async before GC WAT emission.
- Unsupported shapes must retain the existing ARC fallback and must not be silently treated as GC.
- Keep `wasm-tools 1.255.0` as the only accepted Component/WAT tool version.
- Do not change `complete_rows=15 pending_rows=15` unless a separate inventory row has complete evidence.
- Preserve all unrelated dirty-worktree changes; stage only files belonging to this slice when delivery is explicitly requested.

### Task 1: Freeze the baseline and route contract

**Files:**
- Read: `src/build/codegen_pipeline.zig`
- Read: `src/build/test/check_gc_default_build_gate.sh`
- Read: `src/build/test/check_gc_g5c_residual_gate.sh`
- Read: `src/build/test/check_gc_migration_inventory.sh`
- Read: `doc/roadmap_status.md`
- Read: `doc/start_here.md`

**Interfaces:**
- Consumes: current `try_emit_default_gc_sync` and `gc_sync_scalar_leaf_*` helpers.
- Produces: a captured baseline showing the focused Zig tests pass, the default GC fixture gate passes, and the migration inventory still reports `complete_rows=15 pending_rows=15` with its documented non-zero status.

- [ ] **Step 1: Capture the worktree boundary**

```bash
git status --short --branch
git diff --stat
git diff -- src/build/codegen_pipeline.zig
```

Record the pre-existing dirty files mentally or in the task log; do not reset, clean, checkout, or stage them.

- [ ] **Step 2: Run the focused compiler baseline**

```bash
cd src
zig test build/codegen_pipeline.zig
```

Expected: the current focused suite passes before fixture or gate edits.

- [ ] **Step 3: Run the migration baseline**

```bash
cd /home/_/._/_/do
bash src/build/test/check_gc_migration_inventory.sh
```

Expected: the command exits non-zero by design and prints `summary complete_rows=15 pending_rows=15`; this is an incomplete-ledger signal, not a test failure to hide.

### Task 2: Add the positive scalar-leaf fixture and default build assertion

**Files:**
- Create: `examples/gc-p3-runtime/scalar-leaf.do`
- Modify: `src/build/test/check_gc_default_build_gate.sh`
- Test: `examples/gc-p3-runtime/test_do_gc_scalar_leaf.sh`

**Interfaces:**
- Consumes: the default `do build` CLI and the existing GC WAT marker convention.
- Produces: a real fixture that exercises identity and scalar arithmetic through the default GC route, plus a structural gate that parses the generated WAT and rejects ARC markers.

- [ ] **Step 1: Write the positive fixture**

Create `examples/gc-p3-runtime/scalar-leaf.do` with this exact bounded shape:

```do
identity(value u32) -> u32 {
    return value
}

add(left u32, right u32) -> u32 {
    return @add(left, right)
}

start() {}
```

The fixture intentionally has no managed type, host/WIT declaration, loop, defer, async operation, or resource.

- [ ] **Step 2: Add the fixture to the default manifest**

Insert `scalar-leaf.do` in the sorted `expected_fixture_manifest` in `src/build/test/check_gc_default_build_gate.sh`. Keep all existing managed fixtures on the stronger `$do_` marker assertion; add a scalar-specific assertion branch that requires `;; gc-sync` and rejects `__arc_` without weakening the managed branch.

- [ ] **Step 3: Add a direct compiler/WAT gate**

Create `examples/gc-p3-runtime/test_do_gc_scalar_leaf.sh` following the existing `test_do_gc_text_identity.sh` pattern:

```bash
"$DO_BIN" build "$fixture" -o "$wat_path"
"$WASM_TOOLS_BIN" parse "$wat_path" -o "$wasm_path"
rg -q ';; gc-sync ' "$wat_path"
! rg -q '__arc_' "$wat_path"
rg -q '\(func \$identity' "$wat_path"
rg -q '\(func \$add' "$wat_path"
test -s "$wasm_path"
```

Use `DO_BIN`, `WASM_TOOLS_BIN`, and `TMPDIR` in the same manner as neighboring gates; do not use a repository-local generated artifact.

- [ ] **Step 4: Run the positive gate**

```bash
WASM_TOOLS_BIN="$(command -v wasm-tools)" \
DO_BIN="$(pwd)/bin/do" \
bash examples/gc-p3-runtime/test_do_gc_scalar_leaf.sh
```

Expected: WAT contains the GC marker and both scalar functions, contains no `__arc_` marker, and `wasm-tools 1.255.0` produces a non-empty Wasm file.

### Task 3: Lock fail-closed negative routing

**Files:**
- Modify: `src/build/codegen_pipeline.zig`

**Interfaces:**
- Consumes: `gc_sync_scalar_leaf_header`, `gc_sync_scalar_leaf_body`, and `try_emit_default_gc_sync`.
- Produces: explicit negative coverage proving the scalar-leaf route does not claim recursive, loop, defer, or host/WIT programs.

- [ ] **Step 1: Add the recursion guard test first**

Add a unit test beside the scalar-leaf tests using:

```do
recurse(value u32) -> u32 {
    return recurse(value)
}

start() {}
```

Call the normal default pipeline and assert that the result does not contain `;; gc-sync` for this candidate. The test must still accept the existing fallback output; it must not require an ARC implementation detail other than the absence of the GC marker.

- [ ] **Step 2: Add loop and defer guards**

Add separate unit cases using the repository's established syntax:

```do
loop_value(value u32) -> u32 {
    loop {
        return value
    }
}

start() {}
```

```do
cleanup() -> nil {
    return
}

deferred(value u32) -> u32 {
    defer cleanup()
    return value
}

start() {}
```

Each case must be rejected by scalar-leaf admission before WAT is emitted through that route and must not contain `;; gc-sync` in the normal pipeline output.

- [ ] **Step 3: Add host/WIT exclusion coverage**

Use a source-level host declaration with a scalar signature:

```do
work = @host_func("do:scalar-leaf-negative/host@0.1.0", "work", (u32) -> u32)

start() {
    value u32 = work(1)
}
```

Assert that the default route does not select the scalar-only GC path when a host/WIT binding is present. Keep this test source-level and deterministic; it must not require a host runner.

- [ ] **Step 4: Implement only the minimum scanner guard needed by the tests**

If the recursion test currently reaches GC, pass the current function name into the scalar-leaf body check and reject a direct self-call. Preserve the existing one-return-expression admission for calls to other functions only if the GC emitter and current tests already support them; otherwise reject all calls explicitly and document that narrower boundary. Do not add a general expression analyzer in this task.

- [ ] **Step 5: Run the focused suite**

```bash
cd src
zig test build/codegen_pipeline.zig
```

Expected: all existing tests plus the new positive/negative cases pass, with no relaxed or deleted assertions.

### Task 4: Synchronize current-state documentation

**Files:**
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `examples/gc-p3-runtime/README.md`

**Interfaces:**
- Consumes: the positive gate output, negative routing tests, and the unchanged migration inventory.
- Produces: a single current description of the scalar-leaf route, its exact boundary, and its verification commands.

- [ ] **Step 1: Document the bounded admission**

Record that ordinary `do build` now admits the exact scalar-leaf fixture through typed GC, while managed, control-flow, host/WIT, async, resource, and recursive shapes remain fail-closed or on their existing fallback.

- [ ] **Step 2: Record the non-closure explicitly**

Keep `complete_rows=15 pending_rows=15` in the roadmap and start-here status. State that this compiler slice is evidence for the default route only and does not close a migration inventory row or authorize full G5c cutover.

- [ ] **Step 3: Add reproducible commands**

Document the focused test, the scalar fixture gate, the default-build gate, and the pinned tool version. Keep the command paths rooted at `/home/_/._/_/do` or expressed relative to the repository root.

- [ ] **Step 4: Check documentation drift**

```bash
git diff --check
rg -n "scalar-leaf|complete_rows=15 pending_rows=15|wasm-tools 1\.255\.0" \
  doc/start_here.md doc/roadmap_status.md examples/gc-p3-runtime/README.md
```

Expected: all three documents use the same boundary and no stale claim says G5c or full GC migration is complete.

### Task 5: Execute the phase gates and select the next slice

**Files:**
- Read/verify: `src/build/test/run_tests.sh`
- Read/verify: `src/build/test/run_release_smoke.sh`
- Read/verify: `src/build/test/check_gc_g5c_residual_gate.sh`
- Read/verify: `src/build/test/check_gc_semantic_equivalence.sh`
- Read/verify: `src/build/test/check_gc_migration_inventory.sh`

**Interfaces:**
- Consumes: Tasks 2–4 outputs.
- Produces: a verified phase result and an evidence-based candidate for the next bounded G5c slice.

- [ ] **Step 1: Run all phase gates**

```bash
cd /home/_/._/_/do
cd src && zig test build/codegen_pipeline.zig
cd /home/_/._/_/do
./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
bash src/build/test/check_gc_default_build_gate.sh
bash src/build/test/check_gc_g5c_residual_gate.sh
bash src/build/test/check_gc_semantic_equivalence.sh
```

Expected: focused tests, full regression, release smoke, default GC build/parse, residual baseline, and equivalence gates pass. The inventory command remains the one expected non-zero command and must still print `complete_rows=15 pending_rows=15`.

- [ ] **Step 2: Verify tool identity and generated output**

```bash
wasm-tools --version
git diff --check
```

Expected: `wasm-tools 1.255.0 ...` and no whitespace errors; generated WAT is temporary and absent from the repository.

- [ ] **Step 3: Review the next candidate without widening this phase**

After the gates are green, review the 15 pending rows and choose one separately gated slice. The recommended next candidate is synchronous scalar control flow only if a fresh design and negative boundary can prove loop/defer/recursion behavior; generic producer expressions, general async/resource lowering, borrowed payloads, and arbitrary host/WIT aggregates remain non-recommended because their existing blockers require independent ABI/runtime evidence.

- [ ] **Step 4: Handoff state**

Report the exact pass/fail output, the unchanged inventory count, residual risks, and the selected next-slice design target. Do not commit or push as part of this plan unless the user explicitly requests delivery.
