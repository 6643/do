# UI Control Primitives Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Add keyed ui_each, scoped ui_if, and Scope-owned ui_ref primitives to the JavaScript UI reference runtime, then demonstrate and verify their lifecycle behavior without changing the do compiler.

**Architecture:** Keep the current runtime scheduler and dynamic dependency graph. ui_each owns a parent Effect plus one child Scope per stable key; ui_if owns a parent condition Effect plus one child Scope for the active branch; ui_ref stores static string-keyed nodes in the owning Scope. All host calls cross the simulated do boundary by static export name and Scope context.

**Tech Stack:** Plain JavaScript ES modules (.mjs), JSDoc with // @ts-check, Node node:test, browser DOM, and TypeScript 6 tsc --checkJs with a local Node test-module declaration shim.

## Global Constraints

- Do not modify the compiler, parser, language grammar, Wasm ABI, or compiler tests.
- Keep do functions closure-free; JavaScript-only closures may remain inside the host runtime.
- Keep stable keys as item identity; do not add unkeyed/index identity mode.
- Every Effect, child Scope, listener, DOM binding, derived value, and ref must have an owner Scope and cleanup path.
- Keep the JavaScript files plain .mjs; JSDoc is the type layer and TypeScript is not runtime code.
- Preserve the user's existing D a.md, M doc/ui.md, M doc/ui.do, and unrelated worktree state.
- Use apply_patch for source edits and run focused verification after each implementation task.

---

## File Map

| File | Responsibility |
| --- | --- |
| examples/ui-signal/runtime.mjs | Reactive graph, Scope ownership, DOM bindings, each, ifBlock, ref, and item/branch context helpers. |
| examples/ui-signal/runtime.test.mjs | Fake DOM plus lifecycle and fine-grained regression tests. |
| examples/ui-signal/counter-do.mjs | Static simulated do export table for counters, keyed items, and branches. |
| examples/ui-signal/demo.mjs | Browser wiring for counters, keyed list controls, branch toggling, and ref action. |
| examples/ui-signal/index.html | Demo host copy/layout only if a stable mount section is needed. |
| examples/ui-signal/jsconfig.json | Reproducible JSDoc checkJs configuration. |
| examples/ui-signal/node-test-shims.d.ts | Minimal declarations for node:test and node:assert/strict; no runtime dependency. |
| examples/ui-signal/README.md | Commands and behavior covered by the executable reference. |
| doc/ui.md | Normative conceptual contract for the three primitives. |
| doc/ui.do | Future do host-binding sketch for the three primitives. |

---

### Task 1: Extend the Fake DOM and Write Failing Lifecycle Tests

Files:
- Modify: examples/ui-signal/runtime.test.mjs

Interfaces:
- Consumes: Existing createRuntime, createCounterModule, FakeNode, and setup helpers.
- Produces: Failing regression tests for runtime.ref, runtime.each, and runtime.ifBlock, plus a Fake DOM that models browser append/move and branch replacement.

- [ ] Step 1: Add JSDoc to the test imports, fake event type, and FakeNode fields.

Use // @ts-check, import Runtime, Scope, and UiNode from runtime.mjs, and declare the fake listener shape. Type children, parentNode, style, and listeners explicitly so runtime API calls are checked instead of inferred as any.

- [ ] Step 2: Make FakeNode match browser append and replacement semantics.

Update append(...children) so an already-mounted child is removed from its old parent before it is appended. Add:

~~~js
replaceChildren(...children) {
    for (const child of [...this.children]) child.parentNode = null;
    this.children.length = 0;
    this.append(...children);
}
~~~

Add focus() and a focused boolean so the ref demo can assert that an action reads the registered button. Keep remove() idempotent.

- [ ] Step 3: Add the ref lifecycle test.

Create refs are scoped, replaceable, and removed with their owner. Create two fake nodes, register one key, verify getRef, replace the key, verify the new node is returned, dispose the Scope, and verify lookup is undefined.

- [ ] Step 4: Add the keyed each test.

Create each reuses keyed item scopes and disposes removed items. Use a module table with:

~~~js
items(scope) { return scope.signal("items", ["a", "b"]).get(); }
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

Mount a list container, assert two child Scopes and roots, reorder to ["b", "a"], assert the same roots changed order and render counts stayed at one, then remove "a" and assert its listener, ref, signal subscribers, and DOM node were disposed while "b" remains active.

- [ ] Step 5: Add the conditional branch test.

Create ifBlock reuses a branch and disposes it on switch. The condition reads show; then and else render functions increment independent render counters, register a ref, and register cleanup. Assert repeated true updates do not rerender the then branch, switching to false removes the then ref/listener and mounts else, and disposing the parent removes the remaining branch.

- [ ] Step 6: Run the focused test file and confirm the new tests fail for missing APIs.

Run:

~~~bash
node --test examples/ui-signal/runtime.test.mjs
~~~

Expected: the original lifecycle tests pass while the new tests fail with missing each, ifBlock, or ref methods. Do not weaken assertions to make the baseline pass.

---

### Task 2: Add Scope-Owned Refs and Context Helpers

Files:
- Modify: examples/ui-signal/runtime.mjs
- Test: examples/ui-signal/runtime.test.mjs ref test from Task 1

Interfaces:
- Consumes: Existing Scope.cleanup, scheduler disposal, and UiNode JSDoc type.
- Produces: runtime.ref(scope, node, key), runtime.getRef(scope, key), runtime.getEachItem(scope), and runtime.getEachIndex(scope).

- [ ] Step 1: Extend the JSDoc contracts.

Add refs: Map<string, UiNode> and these Runtime properties:

~~~js
ref: (scope: Scope, node: UiNode, key: string) => UiNode
getRef: (scope: Scope, key: string) => UiNode | undefined
getEachItem: (scope: Scope) => unknown
getEachIndex: (scope: Scope) => number | undefined
~~~

Extend UiNode with replaceChildren(...children) and focus() at the adapter boundary; FakeNode and browser elements both provide these operations for the demo contract.

- [ ] Step 2: Implement ref with validation and idempotent cleanup.

Reject an empty key. If the key already has a registration, run the old registration cleanup before installing the new node. Register cleanup that deletes the map entry only when it still points to that node. getRef returns undefined for a disposed Scope.

- [ ] Step 3: Implement item context reads over reserved internal signals.

Use reserved keys __ui_each_item and __ui_each_index. getEachItem reads the item signal and getEachIndex reads the index signal, allowing item Effects to track updates. The each reconciler initializes these signals before item render.

- [ ] Step 4: Run the ref test and current test file.

Run node --test examples/ui-signal/runtime.test.mjs. The ref test must pass; each and if remain the only new failures.

---

### Task 3: Implement Keyed ui_each

Files:
- Modify: examples/ui-signal/runtime.mjs
- Test: examples/ui-signal/runtime.test.mjs keyed each test from Task 1

Interfaces:
- Consumes: callDo, effect, createScope, getEachItem, getEachIndex, and Scope disposal.
- Produces: runtime.each(scope, container, itemsFunction, keyFunction, renderFunction) -> Effect.

- [ ] Step 1: Define the keyed record shape.

Keep a binding-local Map<string, { key: string, scope: Scope, root: UiNode }> and a unique binding ID. Normalize primitive keys (string, number, boolean, bigint) as type:value; throw TypeError for null, undefined, objects, or functions. This keeps 1 and "1" distinct.

- [ ] Step 2: Implement the outer list Effect.

The Effect calls itemsFunction under the active observer, requires an array, computes all descriptors before mutating the old record, and throws on duplicate normalized keys. For each descriptor:

~~~js
const itemScope = existing?.scope ?? createScope("each:<bindingId>", key, scope);
itemScope.signal("__ui_each_item", item);
itemScope.signal("__ui_each_index", index);
~~~

For a new item, call renderFunction with the item Scope exactly once, assign itemScope.root, and register root.remove() as item cleanup. Existing items only update context signals.

- [ ] Step 3: Dispose removed records and move roots into the new order.

Dispose every old record absent from the new key set. Call container.append(...nextRoots); browser append moves existing nodes and the Fake DOM models the same behavior. Keep the binding Effect owned by the parent Scope.

- [ ] Step 4: Expose each and its JSDoc.

Expose each in the returned runtime object with static itemsFunction, keyFunction, and renderFunction names. Do not expose callback or function-valued item renderers to do.

- [ ] Step 5: Run the keyed each test and all runtime tests.

Run node --test examples/ui-signal/runtime.test.mjs. All each assertions must pass, including root reuse, render-count stability, item signal updates, removal cleanup, and sibling isolation.

---

### Task 4: Implement Conditional ui_if

Files:
- Modify: examples/ui-signal/runtime.mjs
- Test: examples/ui-signal/runtime.test.mjs conditional branch test from Task 1

Interfaces:
- Consumes: callDo, effect, createScope, replaceChildren, refs, and Scope disposal.
- Produces: runtime.ifBlock(scope, container, conditionFunction, thenFunction, elseFunction?) -> Effect.

- [ ] Step 1: Implement the branch Effect with explicit boolean validation.

Call the condition under dependency tracking and throw TypeError unless it returns boolean. Track active { name, scope, root }. If the branch name is unchanged, return without rerendering.

- [ ] Step 2: Dispose and replace branches atomically.

On a branch change, dispose the old branch Scope first, call container.replaceChildren(), then create the new branch Scope only when its render function exists. Call that render once, assign its root, register root cleanup, and append it. The parent render function must never be called by a branch update.

- [ ] Step 3: Expose ifBlock and update JSDoc.

Use elseFunction = null as the no-else contract. Add it to Runtime and preserve the existing Effect return type.

- [ ] Step 4: Run the conditional test and all runtime tests.

Run node --test examples/ui-signal/runtime.test.mjs. All original and new ref/each/if tests must pass with zero failures.

---

### Task 5: Extend the Simulated do Module and Browser Demo

Files:
- Modify: examples/ui-signal/counter-do.mjs
- Modify: examples/ui-signal/demo.mjs
- Modify: examples/ui-signal/index.html
- Test: examples/ui-signal/runtime.test.mjs

Interfaces:
- Consumes: runtime.each, runtime.ifBlock, runtime.ref, runtime.getRef, and item context helpers.
- Produces: visible counter ref behavior, branch switching, and keyed list add/remove/reorder behavior.

- [ ] Step 1: Add static export functions for item and branch rendering.

Add these exact roles:

~~~js
list_items(scope)          // parent signal array
list_item_key(scope, item) // stable string key
list_item_render(scope)    // one item Scope
list_add(scope)            // append stable item
list_remove(scope)         // remove current item from parent list
list_reverse(scope)        // reorder parent list
show_details(scope)        // details-visible signal
details_on(scope)          // true branch
details_off(scope)         // false branch
~~~

Use runtime.getEachItem(scope) instead of captured item values. Item render registers a ref and event listener so removal proves recursive cleanup.

- [ ] Step 2: Register and consume a counter button ref.

Call ui.ref(scope, button, "increment_button") during counter_render. In counter_increment, read the ref and call focus() when available after updating the signal. Keep the counter render count unchanged after clicks.

- [ ] Step 3: Mount list and conditional containers from the app demo.

Create stable host nodes, call static render functions once, and wire:

~~~js
runtime.each(listScope, listNode, "list_items", "list_item_key", "list_item_render");
runtime.ifBlock(detailsScope, detailsNode, "show_details", "details_on", "details_off");
~~~

Add visible add, reverse, remove, and toggle controls. Remove updates the parent list signal instead of touching DOM directly.

- [ ] Step 4: Add focused simulated-module assertions.

Assert that list actions change only the intended keyed item, reverse preserves roots/render counts, branch toggling changes branch DOM, and the counter action reads its registered ref.

- [ ] Step 5: Run Node syntax and runtime verification.

~~~bash
node --test examples/ui-signal/runtime.test.mjs
node --check examples/ui-signal/runtime.mjs
node --check examples/ui-signal/counter-do.mjs
node --check examples/ui-signal/demo.mjs
~~~

All commands must exit with status 0.

---

### Task 6: Finish JSDoc Tooling and Synchronize Documentation

Files:
- Modify: examples/ui-signal/runtime.mjs
- Modify: examples/ui-signal/counter-do.mjs
- Modify: examples/ui-signal/demo.mjs
- Modify: examples/ui-signal/runtime.test.mjs
- Create: examples/ui-signal/jsconfig.json
- Create: examples/ui-signal/node-test-shims.d.ts
- Modify: examples/ui-signal/README.md
- Modify: doc/ui.md
- Modify: doc/ui.do

Interfaces:
- Consumes: Public runtime signatures from Tasks 2-5.
- Produces: Consistent JSDoc types and documentation that describe implemented behavior.

- [ ] Step 1: Complete JSDoc on public runtime and demo functions.

Keep // @ts-check in every .mjs. Annotate Signal, Computed, Effect, Scope, Runtime, UiNode, item context, ref methods, and all simulated do functions with parameter and return types. Use explicit unknown casts only at DOM/query and dynamic export boundaries.

- [ ] Step 2: Add checkJs configuration and Node module shim.

Create jsconfig.json with allowJs, checkJs, noEmit, target ES2022, module NodeNext, moduleResolution NodeNext, DOM/ES2022 libs, and skipLibCheck. Include all .mjs and node-test-shims.d.ts. The shim declares only the imported test function and assert.equal.

- [ ] Step 3: Update README commands and behavior notes.

~~~bash
node --test examples/ui-signal/runtime.test.mjs
tsc -p examples/ui-signal/jsconfig.json
~~~

Explain that ui_each is keyed, ui_if owns branch Scopes, and ui_ref is cleaned up with its owner.

- [ ] Step 4: Synchronize doc/ui.md and doc/ui.do.

Add host-binding contracts, item/index context rules, branch disposal order, ref lookup/cleanup, duplicate-key and invalid-result errors, and explicit non-goals. Keep both files future design sketches; do not imply compiler support.

- [ ] Step 5: Run JSDoc and whitespace checks.

~~~bash
tsc -p examples/ui-signal/jsconfig.json
git diff --check
~~~

Expect zero TypeScript diagnostics and zero whitespace errors.

---

### Task 7: Browser Verification and Final Review

Files:
- Verify: examples/ui-signal/index.html, examples/ui-signal/demo.mjs, and all changed files above.

Interfaces:
- Consumes: Complete runtime/demo implementation and documented verification commands.
- Produces: Fresh evidence for fine-grained updates and lifecycle cleanup in a browser.

- [ ] Step 1: Start the demo server on an unused local port.

~~~bash
python3 -m http.server 8000 --directory examples/ui-signal
~~~

If port 8000 is occupied, use the next available local port and record it in the final report.

- [ ] Step 2: Exercise the browser workflow.

Verify that counter clicks update only that counter and keep render count stable; the counter action focuses its registered ref; details toggling disposes the old branch; add/reverse/remove preserve keyed item roots and local state; and removing an item clears its listener, Effect, derived value, ref, and DOM while siblings continue working.

- [ ] Step 3: Inspect the browser console.

After reload and the complete interaction sequence, require 0 errors and 0 warnings. Fix any failure at the owning Scope or DOM boundary before completion is claimed.

- [ ] Step 4: Run the final command set.

~~~bash
node --test examples/ui-signal/runtime.test.mjs
tsc -p examples/ui-signal/jsconfig.json
node --check examples/ui-signal/runtime.mjs
node --check examples/ui-signal/counter-do.mjs
node --check examples/ui-signal/demo.mjs
git diff --check
git status --short
~~~

All commands must exit 0; status may show only intended UI docs/demo changes plus the pre-existing D a.md.

- [ ] Step 5: Review the diff for scope and contract drift.

Confirm no compiler, parser, generated, or unrelated user files changed. Confirm docs, JSDoc, runtime, tests, and README use the same names: each, ifBlock, ref, getRef, getEachItem, and getEachIndex.
