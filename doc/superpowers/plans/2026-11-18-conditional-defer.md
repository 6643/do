# Conditional defer Implementation Plan

> Status: implemented in `db00785`; integrated with the current `main` changes and verified on 2026-11-18. Conditional `StreamWriter` finalization remains conservatively rejected as an unfinalized lease because the predicate may be false.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `defer(condition) cleanup_call()` and `defer(condition) { ... }` with condition capture at registration and cleanup at the enclosing lexical scope exit.

**Architecture:** Parse conditional defer as its own statement form. Keep lexical, statically collected cleanup sites, adding a hidden boolean local per site to preserve the condition evaluated at registration. Guard cleanup emission with that local on every existing defer exit path; each loop body activation updates its own site flag and cleans up before the iteration exits.

**Tech Stack:** Zig compiler, PEG grammar, `.do` integration fixtures, existing `src/build/test/run_tests.sh` harness.

**Spec:** `doc/superpowers/specs/2026-11-18-conditional-defer-design.md`

## Global Constraints

- Preserve existing `defer` semantics: lexical scope, LIFO order, cleanup on normal exit, `return`, `break`, and `continue`.
- Evaluate and store the conditional-defer predicate when its statement executes; overwrite the hidden flag for both true and false.
- Evaluate cleanup call arguments at cleanup time, matching existing `defer`.
- Conditional defer in a loop body belongs to that body's per-iteration scope activation.
- Keep changes flat and one-way across parser, semantic analysis, and code generation modules.
- Keep the syntax aligned with the approved `defer(condition)` form.

## Review Focus

- A later assignment to the predicate must not change whether cleanup runs: cover in Task 1.
- A false predicate on a later loop iteration must not reuse a true value from the prior iteration: cover in Task 2.
- Early exits must run cleanup exactly once and preserve LIFO order: cover `return`, `break`, and `continue` in Tasks 2-3.
- Nested lexical scopes must run conditional cleanup at the containing block exit: cover in Task 3.
- Invalid predicate type or non-nil cleanup result must fail semantic validation: cover in Task 4.

---

### Task 1: Parser and scalar conditional-defer lowering

**Files:**
- Modify: `doc/grammar.peg`
- Modify: `src/build/parser.zig`
- Modify: `src/build/codegen_body.zig`
- Modify: `src/build/codegen_context.zig`
- Modify: `src/build/codegen_emit_control.zig`
- Test: `src/build/test/compile_ok/789_conditional_defer_capture_lower.do`
- Test: `src/build/test/compile_ok/789_conditional_defer_capture_lower.expect`

**Interfaces:**
- Consumes: existing `ConditionExpr`, `ValueExpr`, `DeferContext`, and `DeferItem` representations.
- Produces: recognized `defer(<condition>) <call>` and `defer(<condition>) { ... }` forms with guarded cleanup lowering using a generated bool local.

- [x] **Step 1: Add a compile fixture for condition capture.** The fixture registers with a bool local, mutates that local afterward, and asserts generated WAT stores the predicate at the statement and guards cleanup at scope exit.
- [x] **Step 2: Run the focused compile test and inspect condition capture and guarded cleanup.** Run `./bin/do build src/build/test/compile_ok/789_conditional_defer_capture_lower.do -o /tmp/conditional-defer-capture.wat`.
- [x] **Step 3: Keep the parenthesized conditional form in `DeferStmt`.** Parse condition and cleanup independently, record the condition for bool checking, and return the complete statement end.
- [x] **Step 4: Add hidden bool metadata to the owning lexical `LocalSet`.** Assign a stable compiler-only name from the source token position; do not expose it to source name lookup.
- [x] **Step 5: Emit condition assignment at the statement and guarded cleanup on normal scope exit.** Ensure both true and false values are written.
- [x] **Step 6: Re-run the focused test and inspect WAT for capture-before-mutation and guarded cleanup.**

### Task 2: Loop activation and continue/break handling

**Files:**
- Modify: `src/build/codegen_emit_control.zig`
- Test: `src/build/test/compile_ok/790_conditional_defer_loop_control_lower.do`
- Test: `src/build/test/compile_ok/790_conditional_defer_loop_control_lower.expect`

**Interfaces:**
- Consumes: per-site hidden bool metadata and Task 1's conditional cleanup representation.
- Produces: correct guarded cleanup for each loop-body activation and its exit branches.

- [x] **Step 1: Add a loop fixture with a conditional defer and `continue`, plus a separate `break` path.** Verify the current implementation rejects it.
- [x] **Step 2: Implement per-iteration flag overwrite and guarded cleanup emission for loop-body normal, `continue`, and `break` exits.** Keep the cleanup inside the generated loop body so each activation executes independently.
- [x] **Step 3: Run the focused compile test and verify the cleanup guard is emitted before each corresponding loop-control jump.**

### Task 3: Nested scopes, return, and LIFO behavior

**Files:**
- Modify: `src/build/codegen_emit_control.zig`
- Test: `src/build/test/compile_ok/791_conditional_defer_nested_lifo_lower.do`
- Test: `src/build/test/compile_ok/791_conditional_defer_nested_lifo_lower.expect`

**Interfaces:**
- Consumes: conditional defer site metadata from Tasks 1-2.
- Produces: cleanup emission that obeys lexical ownership, LIFO order, and early returns.

- [x] **Step 1: Add fixtures for two conditional cleanup sites in one scope and a nested `if` block scope.** Assert LIFO order and that nested cleanup runs at the nested block exit.
- [x] **Step 2: Add a `return` path fixture and confirm it fails or lowers without the conditional cleanup.**
- [x] **Step 3: Extend shared defer collection/emission to recognize conditional sites in the owning scope and emit guarded cleanup in reverse order on return and ordinary exits.**
- [x] **Step 4: Run focused fixtures and inspect cleanup order and scope placement.**

### Task 4: Semantic validation and diagnostics

**Files:**
- Modify: relevant `src/build/sema_*.zig` module selected by existing condition/defer validation ownership
- Test: `src/build/test/err/335_conditional_defer_non_bool.do`
- Test: `src/build/test/err/335_conditional_defer_non_bool.expect`
- Test: `src/build/test/err/336_conditional_defer_non_nil_cleanup.do`
- Test: `src/build/test/err/336_conditional_defer_non_nil_cleanup.expect`

**Interfaces:**
- Consumes: parser's conditional-defer condition and cleanup-call records.
- Produces: rejection of conditions not typed as bool and cleanup calls whose result is not nil, using established diagnostics.

- [x] **Step 1: Add negative fixtures and confirm both fail for the intended semantic reasons.**
- [x] **Step 2: Implement validation by reusing ordinary condition and defer-call checks where possible.** Conditional `close(writer)` remains rejected with `StreamWriterLeaseDropped`, since the predicate may be false.
- [x] **Step 3: Run both negative fixtures and verify their expected diagnostic substrings.**

### Task 5: Contract documentation and full regression

**Files:**
- Modify: `doc/grammar.peg`
- Modify: `doc/spec_rules.md`
- Modify: `doc/syntax/control.md`
- Modify: `src/build/test/README.md` if fixture conventions require an index update.

**Interfaces:**
- Consumes: implemented parser, semantic, and lowering behavior.
- Produces: synchronized grammar and user-facing semantics.

- [x] **Step 1: Document `defer(condition)` syntax, registration-time condition capture, cleanup-time call argument evaluation, loop iteration scope, LIFO, and exit paths.**
- [x] **Step 2: Run `./src/build/test/run_tests.sh` from the repository root and record the exact result: `Build Summary: 14/14 steps succeeded`; integration harness passed.**
- [x] **Step 3: Review the complete diff for unintended changes, including the pre-existing dirty files.**
