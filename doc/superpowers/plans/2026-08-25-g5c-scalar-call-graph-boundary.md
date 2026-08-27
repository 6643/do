# G5c Scalar Call-Graph Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the existing synchronous scalar typed-GC route so acyclic same-module helper calls remain admitted while recursive call graphs fail closed.

**Architecture:** Keep `src/build/codegen_pipeline.zig` as the only admission point. Add a pure token-based cycle detector beside the scalar predicates and invoke it from both scalar routes. Preserve the existing `BodyEmitter` call lowering and all fallback paths.

**Tech Stack:** Zig compiler, `.do` fixture, WAT, `wasm-tools 1.255.0`, Bash gates, and the existing regression suite.

**Spec:** `doc/superpowers/specs/2026-08-25-g5c-scalar-call-graph-boundary-design.md`

## Global Constraints

- Preserve GC-first v1 and the existing ARC fallback for unsupported shapes.
- Do not add syntax or change `own<T>`, `borrow<T>`, `ref<T>`, `Option`, `Result`, async, resource, or WIT semantics.
- Preserve non-recursive scalar helper calls already emitted by `BodyEmitter`.
- Reject self-recursion and every mutual/longer call cycle before selecting typed GC.
- Keep imported module graphs, host/WIT, managed, loops, `defer`, and async/resource fail-closed.
- Keep `wasm-tools 1.255.0` pinned.
- Preserve `complete_rows=15 pending_rows=15`.
- Preserve unrelated dirty-worktree changes; do not commit or push in this phase.

### Task 1: Capture the current boundary and RED test

**Files:**
- Read: `src/build/codegen_pipeline.zig`
- Read: `doc/superpowers/specs/2026-08-25-g5c-scalar-call-graph-boundary-design.md`
- Modify: `src/build/codegen_pipeline.zig`

**Interfaces:**
- Consumes: the current scalar-leaf predicate and default route.
- Produces: a regression test proving mutual recursion is not a GC candidate.

- [x] **Step 1: Confirm the existing probes**

  The current route emits typed GC for an acyclic helper chain and also emits
  typed GC for mutual recursion. Preserve both observations in the task log;
  the second is the bug to close.

- [x] **Step 2: Add the failing mutual-recursion test**

  Add this test beside the existing recursive scalar fallback test:

  ```zig
  test "default pipeline keeps mutually recursive scalar helpers on the fallback route" {
      const source =
          \\even(value u32) -> u32 {
          \\    return odd(value)
          \\}
          \\
          \\odd(value u32) -> u32 {
          \\    return even(value)
          \\}
          \\
          \\start() {}
      ;
      const wat = try emit_default_wat_for_source(std.testing.allocator, source);
      defer std.testing.allocator.free(wat);
      try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") == null);
  }
  ```

- [x] **Step 3: Run the RED test**

  ```bash
  cd src
  zig test build/codegen_pipeline.zig --test-filter 'mutually recursive scalar helpers'
  ```

  Expected before implementation: one `TestUnexpectedResult` because the
  generated WAT still contains `;; gc-sync`.

### Task 2: Implement bounded cycle detection

**Files:**
- Modify: `src/build/codegen_pipeline.zig`
- Test: `src/build/codegen_pipeline.zig`

**Interfaces:**
- Consumes: token helpers `find_matching`, `find_top_level_block_open`,
  `is_top_level_decl_head`, and the existing scalar predicates.
- Produces: `gc_sync_scalar_call_graph_reaches` and
  `tokens_have_gc_sync_scalar_call_graph_cycle`.

- [x] **Step 1: Add declaration-range lookup**

  Add:

  ```zig
  const GcScalarFunctionRange = struct {
      body_start: usize,
      body_end: usize,
  };

  fn gc_sync_scalar_function_range(
      tokens: []const lexer.Token,
      name: []const u8,
  ) ?GcScalarFunctionRange
  ```

  Scan only `is_top_level_decl_head` entries, use
  `find_top_level_block_open` and `find_matching`, and return `null` on a
  malformed range or when the name is not declared exactly once.

- [x] **Step 2: Add bounded reachability**

  Add:

  ```zig
  fn gc_sync_scalar_call_graph_reaches(
      tokens: []const lexer.Token,
      current_name: []const u8,
      target_name: []const u8,
      depth: usize,
  ) bool
  ```

  Recursively scan a function body for identifier-call pairs. Ignore an edge
  when the preceding token is `@`; only declared top-level function names are
  graph edges. Return true when the target name is reached. Follow each edge
  with `depth + 1`, and treat `depth >= tokens.len` or an unresolved/ambiguous
  declared call as a cycle/fail-closed result.

- [x] **Step 3: Reject every cycle**

  For each top-level function name, ask whether it can reach itself. Include
  `start` in the graph so a helper-to-start cycle cannot select GC. Do not
  reject an acyclic helper chain merely because it has more than one hop.

- [x] **Step 4: Wire both scalar admissions**

  Add:

  ```zig
  fn tokens_have_gc_sync_scalar_call_graph_cycle(tokens: []const lexer.Token) bool
  ```

  Iterate every top-level function, including `start`, and ask whether its
  name reaches itself. Require this predicate to be false before returning true
  from `tokens_have_gc_sync_scalar_leaf_candidate` or
  `tokens_have_gc_sync_scalar_control_flow_candidate`. Keep the existing
  imported-module guard and route ordering unchanged.

- [x] **Step 5: Run the focused tests**

  ```bash
  cd src
  zig test build/codegen_pipeline.zig --test-filter 'scalar'
  ```

  Expected: the mutual-recursion test passes; existing scalar leaf,
  scalar-control-flow, and recursive self-call tests remain green.

### Task 3: Lock positive and negative fixture gates

**Files:**
- Create: `examples/gc-p3-runtime/scalar-call-graph.do`
- Create: `examples/gc-p3-runtime/test_do_gc_scalar_call_graph.sh`
- Modify: `src/build/test/check_gc_default_build_gate.sh`
- Test: `src/build/codegen_pipeline.zig`

**Interfaces:**
- Consumes: the cycle detector and existing scalar call emitter.
- Produces: one real acyclic-chain GC fixture and structural WAT/toolchain
  evidence; mutual recursion remains covered by the unit test.

- [x] **Step 1: Add the acyclic fixture**

  Use exactly:

  ```do
  leaf(value u32) -> u32 {
      return @add(value, 1)
  }

  middle(value u32) -> u32 {
      return leaf(value)
  }

  caller(value u32) -> u32 {
      return middle(value)
  }

  start() {}
  ```

- [x] **Step 2: Add the standalone gate**

  Build the fixture, parse it with `wasm-tools 1.255.0`, require `;; gc-sync`,
  `call $leaf`, and `call $middle`, reject `__arc_`, and require a non-empty
  Wasm output. Use only `DO_BIN`, `WASM_TOOLS_BIN`, and a temporary directory.

- [x] **Step 3: Add the fixture to the default manifest**

  Add `scalar-call-graph.do` in sorted order and update the expected count from
  78 to 79. Add a named branch requiring the GC marker, both calls, and no ARC;
  leave all existing assertions unchanged.

- [x] **Step 4: Add a positive call-chain unit assertion**

  Assert the default pipeline emits `;; gc-sync`, `call $leaf`, and
  `call $middle` for the fixture source. This protects the behavior preserved
  by the cycle hardening.

- [x] **Step 5: Run focused fixture gates**

  ```bash
  DO_BIN="$(pwd)/bin/do" \
  WASM_TOOLS_BIN="$(command -v wasm-tools)" \
  bash examples/gc-p3-runtime/test_do_gc_scalar_call_graph.sh
  bash src/build/test/check_gc_default_build_gate.sh
  ```

### Task 4: Synchronize current-state documentation

**Files:**
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `examples/gc-p3-runtime/README.md`

**Interfaces:**
- Consumes: verified positive fixture and cycle-negative test.
- Produces: one consistent description of acyclic scalar calls and the
  unchanged pending inventory.

- [x] **Step 1: Record the exact boundary**

  State that scalar-leaf typed GC supports acyclic same-module scalar helper
  calls; recursive graphs and scalar-control-flow call expressions remain
  fail-closed.

- [x] **Step 2: Update fixture count and commands**

  Change only the relevant default manifest count to 79 and document the
  standalone gate plus the pinned tool version.

- [x] **Step 3: Preserve non-closure statements**

  Keep `complete_rows=15 pending_rows=15` and explicitly state that this is
  admission hardening, not a migration-row closure or full GC cutover.

- [x] **Step 4: Check documentation drift**

  ```bash
  git diff --check
  rg -n "scalar-call-graph|acyclic|complete_rows=15 pending_rows=15|wasm-tools 1\\.255\\.0" \
    doc/start_here.md doc/roadmap_status.md examples/gc-p3-runtime/README.md
  ```

### Task 5: Run phase-wide verification and hand off

**Files:**
- Read/verify: `src/build/test/run_tests.sh`
- Read/verify: `src/build/test/run_release_smoke.sh`
- Read/verify: `src/build/test/check_gc_g5c_residual_gate.sh`
- Read/verify: `src/build/test/check_gc_semantic_equivalence.sh`
- Read/verify: `src/build/test/check_gc_migration_inventory.sh`

- [x] **Step 1: Run focused Zig tests**

  ```bash
  cd src
  zig test build/codegen_pipeline.zig
  ```

- [x] **Step 2: Run full regression and release smoke**

  ```bash
  ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  ```

- [x] **Step 3: Run all GC gates**

  ```bash
  bash src/build/test/check_gc_default_build_gate.sh
  bash src/build/test/check_gc_g5c_residual_gate.sh baseline
  bash src/build/test/check_gc_semantic_equivalence.sh
  ```

- [x] **Step 4: Verify the intentional inventory status**

  Require non-zero inventory exit and exact output
  `summary complete_rows=15 pending_rows=15`.

- [x] **Step 5: Final diff/status check**

  ```bash
  git diff --check
  git status --short --branch
  ```

  Do not commit or push in this phase.

## Exit Criteria

All five tasks pass; acyclic helper calls remain typed GC, every recursive call
cycle falls back, the default manifest has 79 fixtures, all existing gates are
green, and the migration ledger remains intentionally incomplete.
