# GC Core Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lower the remaining synchronous numeric and boolean core builtin fixtures through the Wasm GC production route.

**Architecture:** Extend the existing `BodyEmitter` dispatch in `src/build/codegen_gc_sync.zig`. Reuse existing type classification and Wasm opcode conventions, keeping each builtin group fail-closed when its argument shape or type is outside the admitted contract.

**Tech Stack:** Zig compiler, Wasm GC WAT, `.do` compile fixtures, `run_tests.sh` integration harness.

**Spec:** `docs/superpowers/specs/2026-11-20-gc-core-and-async-resource-scope.md`

## Global Constraints

- Ordinary objects use Wasm GC reachability; ARC is test-only equivalence code.
- Core builtin calls use `@name(...)` and fixed core signatures.
- Unsupported async/resource and aggregate shapes remain fail-closed.
- Every pending entry removed must have a passing GC compile fixture and WAT expectation.

## Review Focus

- Variadic arithmetic must preserve left fold order and reject mixed types; test `02` and `12`.
- Signed and unsigned integer operations must select the correct Wasm opcode; test `12`, `15`, and `16`.
- Casts must preserve signedness and width; test `13` and `17`.
- Short-circuit branches must avoid evaluating the right side on the inactive path; test `18`.
- Float unary, binary, and comparison operations must use float opcodes without integer coercion; test `19`.

### Task 1: Variadic Numeric Core

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`
- Modify: `src/build/test/compile_ok/02_scalar_numeric_lower.expect`
- Modify: `src/build/test/compile_ok/12_at_builtin_numeric_lower.expect`
- Modify: `src/build/test/gc_compiled_pending.tsv`

- [x] Verify the existing `02` and `12` fixtures fail through the GC route with `UnsupportedGcSyncExpression`.
- [x] Extend numeric core emission for left folded `@add/@sub/@mul`, signed integer `@abs`, and variadic `@min/@max` using the existing scalar type helpers.
- [x] Run both fixtures and update expectations only to the emitted GC WAT.
- [x] Run focused Zig/codegen tests for scalar numeric emission.

### Task 2: Integer Core Operations And Casts

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`
- Modify: `src/build/test/compile_ok/13_at_builtin_wasm_type_lower.expect`
- Modify: `src/build/test/compile_ok/15_at_builtin_bitwise_lower.expect`
- Modify: `src/build/test/compile_ok/16_at_builtin_count_bits_lower.expect`
- Modify: `src/build/test/compile_ok/17_at_builtin_convert_lower.expect`
- Modify: `src/build/test/gc_compiled_pending.tsv`

- [x] Verify the four existing fixtures fail for the expected GC admission reason.
- [x] Add typed Wasm lowering for bitwise, count, and conversion forms while preserving signed/unsigned opcode selection.
- [x] Run the four fixtures and update their expectations.
- [x] Run focused Zig/codegen tests and the compiler fixture matrix.

### Task 3: Boolean And Floating Point Core

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`
- Modify: `src/build/test/compile_ok/18_at_builtin_bool_short_circuit_lower.expect`
- Modify: `src/build/test/compile_ok/19_at_builtin_float_ops_lower.expect`
- Modify: `src/build/test/gc_compiled_pending.tsv`

- [x] Verify the two existing fixtures fail for the expected GC admission reason.
- [x] Lower boolean short-circuit expressions with branch results and float unary/binary operations using the existing expression helpers.
- [x] Run the two fixtures and update their expectations.
- [x] Run focused Zig/codegen tests.

### Task 4: Whole Branch Verification And Status Sync

**Files:**
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `CHANGELOG.md`

- [x] Run `./src/build/test/run_tests.sh` and record the full result.
- [x] Verify no removed pending entry unexpectedly succeeds outside the intended fixtures.
- [x] Update current status with the actual fixture count and remaining pending categories.
- [x] Run `git diff --check` and review all task changes before delivery.
