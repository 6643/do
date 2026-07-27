# UI Control Primitives Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Add keyed ui_each, scoped _ui_show, Scope-owned ui_ref, and nested struct/list State paths to the TypeScript UI reference runtime, then demonstrate and verify their lifecycle behavior without changing the do compiler.

**Architecture:** Keep the current runtime scheduler and dynamic dependency graph. ui_each owns a parent Effect plus one child Scope per stable key; _ui_show owns a parent condition Effect plus one child Scope for the active branch; ui_ref stores static string-keyed nodes in the owning Scope. Nested records and lists use dotted State keys plus keyed child Scopes. All host calls cross the simulated do boundary by static export name and Scope context.

**Tech Stack:** TypeScript ES modules, Bun build/test, browser DOM, and strict `tsc --noEmit` source checking.

## Global Constraints

- Do not modify the compiler, parser, language grammar, Wasm ABI, or compiler tests.
- Keep do functions closure-free; JavaScript-only closures may remain inside the host runtime.
- Keep stable keys as item identity; do not add unkeyed/index identity mode.
- Every Effect, child Scope, listener, DOM binding, derived value, and ref must have an owner Scope and cleanup path.
- Keep TypeScript source as the type layer; Bun emits the browser ESM files under `dist/`.
- Use State vocabulary in the runtime and demo; do not add legacy reactive-style aliases or data-suffix record names.
- Preserve the user's existing D a.md, M doc/ui.md, M doc/ui.do, and unrelated worktree state.
- Use apply_patch for source edits and run focused verification after each implementation task.

---

## File Map

| File | Responsibility |
| --- | --- |
| examples/ui-signal/runtime.ts | State graph, Scope ownership, DOM bindings, each, show, ref, and item/branch context helpers. |
| examples/ui-signal/runtime.test.ts | Fake DOM plus lifecycle and fine-grained regression tests. |
| examples/ui-signal/counter-do.ts | Static simulated do export table for counters, keyed items, and branches. |
| examples/ui-signal/deep-do.ts | Static nested order/line exports using dotted State keys and keyed Scopes. |
| examples/ui-signal/demo.ts | Browser wiring for counters, keyed list controls, branch toggling, and ref action. |
| examples/ui-signal/index.html | Demo host copy/layout only if a stable mount section is needed. |
| examples/ui-signal/tsconfig.json | Strict no-emit TypeScript source configuration. |
| examples/ui-signal/package.json | Local Bun build, test, type-check, and verification commands. |
| examples/ui-signal/README.md | Commands and behavior covered by the executable reference. |
| doc/ui.md | Normative conceptual contract for the three primitives. |
| doc/ui.do | Future do host-binding sketch for the three primitives. |

---

### Task 1: Extend the Fake DOM and Write Failing Lifecycle Tests

Files:
- Modify: examples/ui-signal/runtime.test.ts

Interfaces:
- Consumes: Existing createRuntime, createCounterModule, FakeNode, and setup helpers.
- Produces: Failing regression tests for runtime.ref, runtime.each, and runtime.show, plus a Fake DOM that models browser append/move and branch replacement.

- [x] Step 1: Add TypeScript types to the test imports, fake event type, and FakeNode fields.

Import Runtime, Scope, and UiNode from runtime.ts, and declare the fake listener shape. Type children, parentNode, style, and listeners explicitly so runtime API calls are checked instead of inferred as any.

- [x] Step 2: Make FakeNode match browser append and replacement semantics.

Update append(...children) so an already-mounted child is removed from its old parent before it is appended. Add:

~~~js
replaceChildren(...children) {
    for (const child of [...this.children]) child.parentNode = null;
    this.children.length = 0;
    this.append(...children);
}
~~~

Add focus() and a focused boolean so the ref demo can assert that an action reads the registered button. Keep remove() idempotent.

- [x] Step 3: Add the ref lifecycle test.

Create refs are scoped, replaceable, and removed with their owner. Create two fake nodes, register one key, verify getRef, replace the key, verify the new node is returned, dispose the Scope, and verify lookup is undefined.

- [x] Step 4: Add the keyed each test.

Create each reuses keyed item scopes and disposes removed items. Use a module table with:

~~~js
items(scope) { return runtime.getState(scope, "items", ["a", "b"]); }
item_key(scope, item) { return item; }
item_text(scope) { return String(runtime.getEachItem(scope)); }
item_render(scope) {
    const node = runtime.createElement("li");
    runtime.ref(scope, node, "item");
    runtime.bindText(scope, node, "item_text");
    runtime.onClick(scope, node, "item_remove");
    return node;
}
~~~

Mount a list container, assert two child Scopes and roots, reorder to ["b", "a"], assert the same roots changed order and render counts stayed at one, then remove "a" and assert its listener, ref, state subscribers, and DOM node were disposed while "b" remains active.

- [x] Step 5: Add the conditional branch test.

Create show reuses a branch and disposes it on switch. The condition reads show; then and else render functions increment independent render counters, register a ref, and register cleanup. Assert repeated true updates do not rerender the then branch, switching to false removes the then ref/listener and mounts else, and disposing the parent removes the remaining branch.

- [x] Step 6: Run the focused test file and confirm the new tests fail for missing APIs.

Run:

~~~bash
bun --cwd examples/ui-signal run test
~~~

Expected: the original lifecycle tests pass while the new tests fail with missing each, show, or ref methods. Do not weaken assertions to make the baseline pass.

---

### Task 2: Add Scope-Owned Refs and Context Helpers

Files:
- Modify: examples/ui-signal/runtime.ts
- Test: examples/ui-signal/runtime.test.ts ref test from Task 1

Interfaces:
- Consumes: Existing Scope cleanup, scheduler disposal, and UiNode type.
- Produces: runtime.ref(scope, node, key), runtime.getRef(scope, key), runtime.getEachItem(scope), and runtime.getEachIndex(scope).

- [x] Step 1: Extend the TypeScript contracts.

Add refs: Map<string, UiNode> and these Runtime properties:

~~~js
ref: (scope: Scope, node: UiNode, key: string) => UiNode
getRef: (scope: Scope, key: string) => UiNode | undefined
getEachItem: (scope: Scope) => unknown
getEachIndex: (scope: Scope) => number | undefined
~~~

Extend UiNode with replaceChildren(...children) and focus() at the adapter boundary; FakeNode and browser elements both provide these operations for the demo contract.

- [x] Step 2: Implement ref with validation and idempotent cleanup.

Reject an empty key. If the key already has a registration, run the old registration cleanup before installing the new node. Register cleanup that deletes the map entry only when it still points to that node. getRef returns undefined for a disposed Scope.

- [x] Step 3: Implement item context reads over reserved internal state.

Use reserved keys __ui_each_item and __ui_each_index. getEachItem reads the item state and getEachIndex reads the index state, allowing item Effects to track updates. The each reconciler initializes these states before item render.

- [x] Step 4: Run the ref test and current test file.

Run bun --cwd examples/ui-signal run test. The ref test must pass; the keyed-list and `_ui_show` tests are the remaining implementation stages.

---

### Task 3: Implement Keyed ui_each

Files:
- Modify: examples/ui-signal/runtime.ts
- Test: examples/ui-signal/runtime.test.ts keyed each test from Task 1

Interfaces:
- Consumes: callDo, effect, createScope, getEachItem, getEachIndex, and Scope disposal.
- Produces: runtime.each(scope, container, itemsFunction, keyFunction, renderFunction) -> Effect.

- [x] Step 1: Define the keyed record shape.

Keep a binding-local Map<string, { key: string, scope: Scope, root: UiNode }> and a unique binding ID. Normalize primitive keys (string, number, boolean, bigint) as type:value; throw TypeError for null, undefined, objects, or functions. This keeps 1 and "1" distinct.

- [x] Step 2: Implement the outer list Effect.

The Effect calls itemsFunction under the active observer, requires an array, computes all descriptors before mutating the old record, and throws on duplicate normalized keys. For each descriptor:

~~~js
const itemScope = existing?.scope ?? createScope("each:<bindingId>", key, scope);
runtime.setState(itemScope, "__ui_each_item", item);
runtime.setState(itemScope, "__ui_each_index", index);
~~~

For a new item, call renderFunction with the item Scope exactly once, assign itemScope.root, and register root.remove() as item cleanup. Existing items only update context state.

- [x] Step 3: Dispose removed records and move roots into the new order.

Dispose every old record absent from the new key set. Call container.append(...nextRoots); browser append moves existing nodes and the Fake DOM models the same behavior. Keep the binding Effect owned by the parent Scope.

- [x] Step 4: Expose each and its TypeScript type.

Expose each in the returned runtime object with static itemsFunction, keyFunction, and renderFunction names. Do not expose callback or function-valued item renderers to do.

- [x] Step 5: Run the keyed each test and all runtime tests.

Run bun --cwd examples/ui-signal run test. All each assertions must pass, including root reuse, render-count stability, item state updates, removal cleanup, and sibling isolation.

---

### Task 4: Implement Conditional _ui_show

Files:
- Modify: examples/ui-signal/runtime.ts
- Test: examples/ui-signal/runtime.test.ts conditional branch test from Task 1

Interfaces:
- Consumes: callDo, effect, createScope, replaceChildren, refs, and Scope disposal.
- Produces: runtime.show(scope, container, conditionFunction, thenFunction, elseFunction?) -> Effect.

- [x] Step 1: Implement the branch Effect with explicit boolean validation.

Call the condition under dependency tracking and throw TypeError unless it returns boolean. Track active { name, scope, root }. If the branch name is unchanged, return without rerendering.

- [x] Step 2: Dispose and replace branches atomically.

On a branch change, dispose the old branch Scope first, call container.replaceChildren(), then create the new branch Scope only when its render function exists. Call that render once, assign its root, register root cleanup, and append it. The parent render function must never be called by a branch update.

- [x] Step 3: Expose show and update its TypeScript type.

Use elseFunction = null as the no-else contract. Add it to Runtime and preserve the existing Effect return type.

- [x] Step 4: Run the conditional test and all runtime tests.

Run bun --cwd examples/ui-signal run test. All original and new ref/each/`_ui_show` tests must pass with zero failures.

---

### Task 5: Extend the Simulated do Module and Browser Demo

Files:
- Modify: examples/ui-signal/counter-do.ts
- Modify: examples/ui-signal/demo.ts
- Modify: examples/ui-signal/index.html
- Test: examples/ui-signal/runtime.test.ts

Interfaces:
- Consumes: runtime.each, runtime.show, runtime.ref, runtime.getRef, and item context helpers.
- Produces: visible counter ref behavior, branch switching, and keyed list add/remove/reorder behavior.

- [x] Step 1: Add static export functions for item and branch rendering.

Add these exact roles:

~~~js
list_items(scope)          // parent state array
list_item_key(scope, item) // stable string key
list_item_render(scope)    // one item Scope
list_add(scope)            // JavaScript demo module action
list_remove(scope)         // remove current item from parent list
list_reverse(scope)        // reorder parent list
show_details(scope)        // details-visible state
details_on(scope)          // true branch
details_off(scope)         // false branch
~~~

Use runtime.getEachItem(scope) instead of captured item values. Item render registers a ref and event listener so removal proves recursive cleanup.

- [x] Step 2: Register and consume a counter button ref.

Call ui.ref(scope, button, "increment_button") during counter_render. In counter_increment, read the ref and call focus() when available after updating the state. Keep the counter render count unchanged after clicks.

- [x] Step 3: Mount list and conditional containers from the app demo.

Create stable host nodes, call static render functions once, and wire:

~~~js
runtime.each(listScope, listNode, "list_items", "list_item_key", "list_item_render");
runtime.show(detailsScope, detailsNode, "show_details", "details_on", "details_off");
~~~

Add visible add, reverse, remove, and toggle controls. Remove updates the parent list state instead of touching DOM directly.

- [x] Step 4: Add focused simulated-module assertions.

Assert that list actions change only the intended keyed item, reverse preserves roots/render counts, branch toggling changes branch DOM, and the counter action reads its registered ref.

- [x] Step 5: Run build and runtime verification.

~~~bash
bun --cwd examples/ui-signal run test
bun --cwd examples/ui-signal run check
bun --cwd examples/ui-signal run build
~~~

All commands must exit with status 0.

---

### Task 6: Finish TypeScript Tooling and Synchronize Documentation

Files:
- Modify: examples/ui-signal/runtime.ts
- Modify: examples/ui-signal/counter-do.ts
- Modify: examples/ui-signal/deep-do.ts
- Modify: examples/ui-signal/demo.ts
- Modify: examples/ui-signal/runtime.test.ts
- Create: examples/ui-signal/tsconfig.json
- Create: examples/ui-signal/package.json
- Modify: examples/ui-signal/README.md
- Modify: doc/ui.md
- Modify: doc/ui.do

Interfaces:
- Consumes: Public runtime signatures from Tasks 2-5.
- Produces: Consistent TypeScript types and documentation that describe implemented behavior.

- [x] Step 1: Complete TypeScript types on public runtime and demo functions.

Annotate State, Computed, Effect, Scope, Runtime, UiNode, item context, ref methods, and all simulated do functions with parameter and return types. Use explicit unknown casts only at DOM/query and dynamic export boundaries.

- [x] Step 2: Add strict TypeScript configuration and Bun commands.

Create tsconfig.json with strict noEmit checking, target ES2022, module NodeNext, moduleResolution NodeNext, DOM/ES2022 libs, and skipLibCheck. package.json supplies local Bun build, test, and verification commands.

- [x] Step 3: Update README commands and behavior notes.

~~~bash
bun --cwd examples/ui-signal run test
bun --cwd examples/ui-signal run check
~~~

Explain that ui_each is keyed, _ui_show owns branch Scopes, and ui_ref is cleaned up with its owner.

- [x] Step 4: Synchronize doc/ui.md and doc/ui.do.

Add host-binding contracts, item/index context rules, branch disposal order, ref lookup/cleanup, duplicate-key and invalid-result errors, and explicit non-goals. Keep both files future design sketches; do not imply compiler support.

- [x] Step 5: Run TypeScript and whitespace checks.

~~~bash
bun --cwd examples/ui-signal run check
git diff --check
~~~

Expect zero TypeScript diagnostics and zero whitespace errors.

---

### Task 7: Complete Nested Struct/List State Prototype and Naming Cleanup

Files:
- Modify: examples/ui-signal/runtime.ts
- Modify: examples/ui-signal/deep-do.ts
- Modify: examples/ui-signal/runtime.test.ts
- Modify: docs/superpowers/specs/2026-07-27-ui-control-primitives-design.md
- Modify: docs/superpowers/plans/2026-07-27-ui-control-primitives.md

Interfaces:
- Consumes: `runtime.getState`/`setState`, keyed `runtime.each`, Scope disposal, and the static export table.
- Produces: Fine-grained dotted State paths for nested record/list values and framework-neutral source vocabulary.

- [x] Step 1: Add the nested state tree contract.

Use `orders.structure` for order identity, order child Scope paths for `customer.name`, `shipping.city`, and `lines.structure`, and line child Scope paths for `product.name`, `quantity`, and `price`. Keep list identity in stable keys; do not make a whole struct/list one binding.

- [x] Step 2: Add the executable deep demo and regression assertions.

`deep-do.ts` uses `ORDERS`/`LINES`, `getOrder`/`getLine`, and keyed child Scopes. The runtime test proves that changing one name or quantity updates only its leaf binding, while adding a line reuses existing roots.

- [x] Step 3: Remove stale internal and demo names.

Use `GraphNode`, `StateSource`, `StateObserver`, and `OwnedResource` in the runtime types and implementation. Remove legacy reactive-style aliases and data-suffixed record/table/lookup names from the UI reference surface.

- [x] Step 4: Synchronize the design spec and implementation plan.

Document the State tree, WASI record/list snapshot boundary, stable-key rule, and current verification coverage. Keep compiler support and arbitrary WIT nested values as non-goals.

---

### Task 8: Browser Verification and Final Review

Files:
- Verify: examples/ui-signal/index.html, examples/ui-signal/demo.ts, and all changed files above.

Interfaces:
- Consumes: Complete runtime/demo implementation and documented verification commands.
- Produces: Fresh evidence for fine-grained updates and lifecycle cleanup in a browser.

- [x] Step 1: Start the demo server on an unused local port.

~~~bash
python3 -m http.server 8000 --directory examples/ui-signal
~~~

If port 8000 is occupied, use the next available local port and record it in the final report.

- [x] Step 2: Exercise the browser workflow.

Verify that counter clicks update only that counter and keep render count stable; the counter action focuses its registered ref; details toggling disposes the old branch; add/reverse/remove preserve keyed item roots and local state; and removing an item clears its listener, Effect, derived value, ref, and DOM while siblings continue working.

- [x] Step 3: Inspect the browser console.

After reload and the complete interaction sequence, require 0 errors and 0 warnings. Fix any failure at the owning Scope or DOM boundary before completion is claimed.

- [x] Step 4: Run the final command set.

~~~bash
bun --cwd examples/ui-signal run test
bun --cwd examples/ui-signal run check
bun --cwd examples/ui-signal run build
git diff --check
git status --short
~~~

All commands must exit 0; status may show only intended UI docs/demo changes plus the pre-existing D a.md.

- [x] Step 5: Review the diff for scope and contract drift.

Confirm no compiler, parser, generated, or unrelated user files changed. Confirm docs, types, runtime, tests, and README use the same names: each, show, ref, getRef, getEachItem, and getEachIndex.

---

### Task 9: Context Handle and Data-Record Runtime Split

Files:
- Modify: examples/ui-signal/runtime.ts
- Modify: examples/ui-signal/counter-do.ts
- Modify: examples/ui-signal/deep-do.ts
- Modify: examples/ui-signal/runtime.test.ts
- Modify: examples/ui-signal/README.md
- Modify: doc/ui.md
- Modify: doc/ui.do
- Modify: docs/superpowers/specs/2026-07-27-ui-control-primitives-design.md

Interfaces:
- Consumes: the existing `scope_id + runtime state table` ownership model and
  static do export dispatch.
- Produces: a do-facing `Context` handle and a runtime made of plain data
  records plus free functions.

- [x] Step 1: Make Context the do callback boundary.

`callDo` accepts a host Scope or Context but invokes every export with the
frozen `{ id }` Context. State, metadata, refs, parent lookup, bindings, and
cleanup APIs resolve Context back to the internal Scope record.

- [x] Step 2: Keep lifecycle resources on Scope records.

Context does not copy State, Derived, Effect, metadata, or child maps. Scope
disposal recursively releases resources and removes the Context from the
validation registry; post-disposal metadata and parent lookup return
`undefined`.

- [x] Step 3: Remove class-based runtime records.

State, graph nodes, effects, and scopes are ordinary objects. Operations use
`create_state`, `state_get`, `state_set`, `create_effect`, `create_scope`, and
`scope_dispose`; no `class GraphNode`, `class State`, `class Computed`,
`class Effect`, or `class ScopeRecord` remains in the runtime.

- [x] Step 4: Migrate examples, tests, and documentation.

Counter and nested record/list exports use Context and runtime metadata APIs.
Host-side tests may inspect Scope records only for lifecycle assertions. The
docs distinguish Context identity from Scope ownership and retain the
fine-grained per-State-key update contract.

- [x] Step 5: Verify the split.

Run the focused runtime test, TypeScript type check, browser build, the
browser demo interaction pass, and `git diff --check`.
