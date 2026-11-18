# If Expressions and Conditional Assignment Implementation Plan

> **For agentic workers:** Execute this plan task by task. The scope and decisions below were confirmed in the conversation.

**Goal:** Support value-producing `if` expressions with explicit `else`, no-`else` conditional reassignment of an existing variable, Tuple as one branch value, and defer execution when a value block exits.

**Architecture:** Extend the parser's expression representation to carry conditional branches and value blocks. Semantic analysis checks condition type, branch compatibility, assignment targets, and Tuple shape. Code generation emits only the selected branch, preserves the conditional-assignment target when false, and saves a block result before running that block's deferred cleanup.

**Tech Stack:** Zig compiler frontend, Do grammar, WebAssembly text code generation.

**Spec:** Conversation decisions in this task. Update `doc/grammar.peg` and `doc/spec_rules.md` with the implemented contract.

## Confirmed Semantics

- `count i32 = if b 1 else 2` is a value expression. Both branches produce one value compatible with the expected type.
- `if b { print("b == 1") 1 } else 2` uses the final expression of the block as that branch's value.
- Tuple is one value. Both branches must have compatible Tuple types and shape.
- A no-`else` form such as `count = if b 128` is conditional reassignment of an already bound target. False leaves the current target value intact. This form does not define a value-producing `if` expression.
- `defer` registered inside a value block runs when that block exits. Evaluate and save the block result first, run deferred cleanup, then yield the saved result.
- Conditional list elements, including `List<i32>{0, if b 111}`, are deferred and excluded from this implementation.

## Global Constraints

- Keep the expression parser and semantic domains within the existing flat `src/build/` module structure.
- Update `doc/grammar.peg` for syntax changes and `doc/spec_rules.md` for semantic rules.
- Do not change the deferred `List` conditional-element design as part of this task.
- Preserve existing no-value `if` statements and their control-flow behavior.

## Review Focus

- Nested conditional expressions must associate each `else` with the nearest unmatched `if`.
- The condition is evaluated once, and only the selected branch's expressions and side effects run.
- Both branches must agree on one logical value type; Tuple remains one logical value.
- A block-local deferred cleanup runs after its result is captured and before control returns to the outer expression.
- A false conditional reassignment must preserve the old value and must not evaluate the right-hand expression.

## Implementation Tasks

### Task 1: Specify and parse conditional expression shapes

**Files:** `doc/grammar.peg`, `src/build/parser.zig`

- Add expression grammar for `if condition branch else branch`, supporting inline branches and braced value blocks.
- Define a braced value block as statements followed by exactly one final value expression. Reject an empty block or a block with no final value.
- Extend the expression representation with conditional node data that identifies condition, then branch, and else branch ranges or child nodes.
- Keep statement-form `if` parsing distinct, and make nested `else` association deterministic by binding to the nearest unmatched `if`.
- Parse block statements and the final value expression without allowing block-local bindings to escape.

**Completion check:** The parser can represent all agreed expression forms and nested forms without treating value branches as standalone statements.

### Task 2: Add branch type and Tuple validation

**Files:** `src/build/sema_function_calls.zig`, `src/build/sema_function_support.zig`, `src/build/sema_structures.zig`, `src/build/sema_type_checks.zig` as dictated by existing ownership

- Thread expected type context into both branches from typed bindings, assignments, struct fields, and returns.
- Require a boolean condition.
- Require each branch to produce one logical value compatible with the expected type; without an expected type, require compatible inferred types.
- Treat Tuple as one value and verify both branch Tuple type arguments and arity agree.
- Preserve explicit `else` as mandatory for value-producing `if` expressions; accept `nil` only through ordinary nullable type compatibility.

**Completion check:** Invalid condition types, incompatible branches, and mismatched Tuple shapes are rejected in semantic analysis.

### Task 3: Add conditional reassignment

**Files:** `doc/grammar.peg`, `src/build/parser.zig`, relevant assignment checks under `src/build/sema_*.zig`, `src/build/codegen_emit_control.zig`

- Recognize `existing_target = if condition value` as conditional reassignment.
- Require an already bound assignment target and type-check the condition and assigned value against that target.
- Preserve the target value when the condition is false.
- Evaluate the condition once and evaluate the assigned value only on the true path.
- Keep this no-`else` form unavailable as a general value expression or new typed binding initializer.

**Completion check:** Reassignment lowers to explicit control flow and preserves prior target state on the false path.

### Task 4: Generate value-producing branches and block cleanup

**Files:** `src/build/codegen_emit_expression.zig`, `src/build/codegen_emit_control.zig`, `src/build/codegen_body.zig`, and supporting codegen modules only where needed

- Emit the condition once and branch using the existing expected type and expression callbacks.
- Emit one result value from each branch, including Tuple as one logical value.
- For a value block with `defer`, evaluate and save the final result before executing the block's deferred cleanups; then yield the saved result.
- Ensure local bindings in a branch block stay scoped to that branch and cleanup runs once on the block's normal exit.
- Keep return, break, and other non-fallthrough control flow behavior consistent with existing statement lowering.

**Completion check:** Generated WAT leaves a value of the agreed type on both reachable branch paths, with cleanup in the defined order.

### Task 5: Synchronize language documentation and review integration

**Files:** `doc/grammar.peg`, `doc/spec_rules.md`, relevant examples in `doc/spec_examples.md` if that file is the established location

- Document value `if`, value blocks, branch typing, Tuple behavior, conditional reassignment, and defer timing.
- Include examples for inline branches, block branches, Tuple values, nested `if`, and false-path reassignment.
- State that conditional list elements remain deferred.
- Review parser, sema, and codegen paths for evaluation order, scoping, ownership, and error handling.

**Completion check:** Grammar and semantic documentation agree with compiler behavior; all implementation diffs are reviewed against the five Review Focus cases.

## Out of Scope

- Conditional elements in `List<T>{...}` or other aggregate literals.
- No-`else` value expressions that implicitly produce `nil` or any other default.
- Mutating a target when the condition is false.
- General block expressions outside `if` branches.
