# Conditional defer design

## Intent

Add `defer(condition) cleanup_call()` and `defer(condition) { ... }` so cleanup
is registered only when the condition is true at that statement. This supports
conditional resource cleanup without moving cleanup into a temporary `if` block.

## Goals

- Evaluate the condition where the statement runs and retain that boolean
  decision until the owning defer scope exits.
- Register cleanup in the current lexical block, not in a new scope created by
  the conditional statement.
- Preserve existing defer behavior: cleanup runs on normal block exit,
  `return`, `break`, and `continue`, in LIFO order.
- In a loop body, each iteration is a separate activation of that lexical block.
  A true conditional defer runs when that iteration exits; it does not
  accumulate until the loop's enclosing block exits.
- Keep cleanup calls subject to existing defer restrictions, including a `nil`
  result.

## Non-goals

- Conditional `defer` blocks.
- A runtime defer stack or heap allocation for defer records.
- Changing when cleanup call arguments are evaluated. Like existing `defer f(x)`,
  the call expression is emitted at cleanup time; only the condition is saved
  at registration time.
- Running cleanup after a trap or process termination.

## Approaches

1. Add a dedicated conditional-defer statement and lower it into the existing
   lexical defer mechanism. At each statement, store the condition in a hidden
   boolean local. At scope exits, guard the cleanup call with that saved value.
   This matches the current static-scope lowering and naturally runs once per
   loop-body activation. Recommended.
2. Add a runtime defer stack. Each execution pushes a cleanup record and scope
   exit pops records in reverse order. This supports a general dynamic cleanup
   model, but is unnecessary for the current lexical rule and requires a larger
   runtime and control-flow change.
3. Lower to `if condition { defer cleanup() }`. This assigns the defer to the
   temporary `if` block, causing cleanup immediately at the end of that block;
   it does not meet the intended lifetime.

## Syntax and semantics

Proposed PEG shape:

```peg
IfStmt          <- 'if' IfCondExpr Block ElseTail?
                 / 'if' IfCondExpr GuardStmt
DeferStmt       <- 'defer' DeferCondition? (DeferCall / DeferBlock)
DeferCondition  <- '(' Expr ')'
```

`defer(condition) cleanup_call()` and `defer(condition) { ... }` are defer
statements. The condition must have type `bool`; the cleanup must satisfy the
existing defer rules. The statement does not create an additional lexical scope.

At runtime, each execution evaluates the condition and writes the result to a
hidden boolean associated with the current lexical scope and source defer
site. This write occurs for both `true` and `false`, so a prior loop iteration
cannot leave a stale `true` value. On every exit path from that scope, cleanup
sites are visited in reverse source registration order; a site calls its
cleanup only when its saved boolean is true.

For example:

```do
x Text = choose_text()
defer(should_close) close(x)
should_close = false
use(x)
```

The saved condition is unaffected by the later assignment. `close(x)` remains
evaluated at scope exit, consistent with existing `defer close(x)` semantics.

In a loop:

```do
loop item, index = items {
    defer(should_close(item)) close(item)
    continue
}
```

If the condition is true, cleanup runs on that iteration's `continue` path.
Each later iteration evaluates the condition again and has its own block
activation. A normal iteration exit, `break`, and `return` follow the same
scope-exit cleanup rules.

## Implementation boundary

- `doc/grammar.peg`: add the conditional defer form to `DeferStmt`.
- `src/build/parser.zig`: recognize the conditional form, parse its condition and
  cleanup call, and record condition/value validation inputs.
- Semantic analysis: require a boolean condition and a valid nil-returning
  cleanup call; preserve name visibility and stream-writer lease checks.
- Code generation: allocate a hidden boolean per conditional-defer site in the
  owning scope; write it at the statement; guard the generated cleanup at
  normal exit, `return`, `break`, and `continue` paths. Loop-body activation
  must reset/update the flag on every execution.
- Tests: cover true/false, condition mutation after registration, repeated loop
  iterations, LIFO order, nested scopes, and every supported exit path. Include
  negative cases for non-boolean conditions and non-nil cleanup results.
- `doc/spec_rules.md` and control syntax documentation: synchronize the
  language contract and examples.

## Open implementation check

Before coding, verify that hidden locals can be declared and initialized for
each lexical defer scope without leaking across branch scopes, and that every
early-exit cleanup emitter can guard a conditional site while preserving LIFO
ordering. If either assumption fails, revise lowering before broadening syntax.
