# UI Control Primitives Design

## Scope

This change extends the executable JavaScript UI runtime reference under
`examples/ui-signal/` with three host primitives:

- `ui_each`: keyed list reconciliation with one child Scope per item;
- `ui_if`: conditional branch mounting with one child Scope per active branch;
- `ui_ref`: string-keyed DOM references owned by a Scope.

The change also updates `doc/ui.md`, `doc/ui.do`, the browser demo, and the
runtime tests. It does not modify the compiler, parser, language grammar,
Wasm ABI, or the existing `scope_id + runtime state table` ownership model.

The JavaScript files remain plain `.mjs` files. JSDoc and `@ts-check` describe
the runtime boundary; TypeScript syntax is not introduced into the demo.

## Design Evidence

The current reference runtime already provides:

1. automatic Scope, signal, derived, effect, and binding IDs;
2. dynamic signal dependency tracking through the active observer;
3. recursive child Scope disposal and bidirectional dependency removal;
4. static function-name dispatch from the host runtime to the simulated `do`
   export table.

Svelte 5 and Solid 2 provide the relevant semantic reference points, but the
implementation is adapted to this language's constraints. The `do` side has
no closure, pointer, reference, or component struct. JavaScript may use
internal closures for effects and DOM listeners, but none cross the `do`
boundary.

## Semantic Mapping

| Primitive | Svelte 5 reference | Solid 2 reference | Runtime contract |
| --- | --- | --- | --- |
| `ui_each` | keyed `{#each items as item (item.id)}` | `<For each={items}>` | keyed child Scope reconciliation |
| `ui_if` | `{#if}` / `{:else}` | `<Show when={...} fallback={...}>` | one active branch Scope |
| `ui_ref` | `bind:this` | `ref` | Scope-owned string-keyed DOM reference |

Both reference frameworks support fine-grained updates. The distinction here
is where the bookkeeping lives: the `do` functions provide stable names and
read/write operations, while JavaScript owns the reactive graph, DOM nodes,
Scope tree, and cleanup.

## Host API

The `do`-facing names are conceptual host bindings. The JavaScript reference
uses the existing camel-case runtime style.

```do
ui_each(list_node, scope, "items", "item_key", "item_render")
ui_if(branch_node, scope, "show_details", "details_on", "details_off")
ui_ref(button_node, scope, "increment_button")
```

The runtime API is:

```js
runtime.each(scope, listNode, itemsFunction, keyFunction, renderFunction)
runtime.ifBlock(scope, branchNode, conditionFunction, thenFunction, elseFunction)
runtime.ref(scope, node, refKey)
runtime.getRef(scope, refKey)
runtime.getEachItem(scope)
runtime.getEachIndex(scope)
```

`runtime.each` and `runtime.ifBlock` return an Effect-like binding resource.
`runtime.ref` returns the supplied node. All function arguments are static
export names; no `do` closure is captured.

## `ui_each` Reconciliation

`ui_each` establishes one outer Effect on the parent Scope. The Effect calls
the list function while dependency tracking is active. A list update then
reconciles the previous keyed record with the new list:

```text
parent Scope
└── each binding Effect
    ├── item Scope: key=a
    │   ├── item signal
    │   ├── index signal
    │   └── item render Effects/listeners
    └── item Scope: key=b
```

The key function is called with the parent Scope, item, and index. The render
function is called once for a new item Scope and receives that item Scope. The
runtime stores the current item and index as internal signals, so an existing
item can update its own bindings without rerunning its render function.

Reconciliation rules:

1. Keys are required and are normalized to a stable runtime key.
2. Duplicate keys throw before the old list is partially mutated.
3. An existing key reuses its Scope and root DOM node.
4. A new key creates a child Scope, initializes item/index signals, and calls
   the render function once.
5. A removed key recursively disposes its Scope, including listeners,
   effects, derived values, refs, and DOM cleanup.
6. Reordering moves existing root nodes into the new order without rerendering
   unchanged items.
7. Updating an item's value or index writes its internal signals; only
   bindings that read those signals are scheduled.

The demo uses a stable string key. Index is not used as identity because it
would move state and event ownership to a different item after insertion or
reordering.

## `ui_if` Branch Ownership

`ui_if` creates one condition Effect on the parent Scope and one child Scope
for the active branch. The branch key is stable (`then` or `else`) within the
binding:

```text
parent Scope
└── if binding Effect
    └── active branch Scope
        ├── branch signals
        ├── branch Effects
        ├── event listeners
        └── refs
```

When the condition remains in the same truthiness branch, the branch Scope is
reused. When it changes, the old branch is disposed before the new branch is
mounted. The parent render function is not rerun. The branch render function
is called only when its branch becomes active.

The `elseFunction` is optional. Without it, the branch container is empty when
the condition is false.

## `ui_ref` Lifecycle

`ui_ref(scope, node, key)` stores `node` in `scope.refs` under a static string
key. `getRef(scope, key)` is the host-side read operation used by an event
action or another binding. A ref registration adds a Scope cleanup that removes
the entry only if it still points to the registered node.

Refs do not provide a callback-ref API. A callback would recreate a closure or
function-value ABI at the `do` boundary. A ref is available only while its
owner Scope is alive; disposing an item or branch removes its refs
automatically.

## Error and Boundary Rules

- `ui_each` rejects a non-array list result and duplicate keys.
- `ui_if` treats only the explicit boolean result as the condition contract;
  invalid dispatch results fail at the host boundary rather than silently
  mounting an unexpected branch.
- `ui_ref` rejects an empty ref key and replaces a previous registration only
  after its old cleanup is detached.
- Every new Effect, child Scope, listener, DOM binding, and ref is registered
  with an owner Scope before it can be observed by the scheduler.
- The scheduler checks `disposed` before running a queued Effect. A disposal
  during a batch therefore cannot update detached DOM.

## Demo Changes

The executable demo will show all three primitives in one browser workflow:

1. the existing counter keeps independent text/class/style/summary Effects;
2. its increment button is registered with `ui_ref` and read by the action;
3. a details panel is mounted through `ui_if`, with branch-local cleanup;
4. a keyed list is mounted through `ui_each`, with add/remove/reorder actions;
5. removing an item proves that its state, listener, Effect, derived value,
   ref, and DOM node are disposed without affecting sibling items.

The simulated `counter-do.mjs` export table remains the stand-in for future
`do` exports. It uses the runtime's static function-name calls and item/branch
context helpers instead of captured component closures.

## Verification

The implementation is accepted only when all of the following pass:

```bash
node --test examples/ui-signal/runtime.test.mjs
tsc -p examples/ui-signal/jsconfig.json
node --check examples/ui-signal/runtime.mjs
node --check examples/ui-signal/counter-do.mjs
node --check examples/ui-signal/demo.mjs
git diff --check
```

The runtime tests must cover:

- keyed Scope and DOM reuse after reorder;
- item-local update without item render rerun;
- removed-item listener/effect/derived/ref/DOM cleanup;
- `ui_if` branch reuse and branch cleanup on switch;
- ref registration, replacement, lookup, and Scope disposal;
- parent Scope disposal recursively disposing each/if descendants.

Browser verification must confirm that the demo updates the intended item or
branch, leaves sibling items unchanged, and produces no console errors or
warnings after mounting, interaction, reorder, branch switching, and removal.

## Non-goals

- No compiler or parser support for special UI syntax.
- No unkeyed list mode or index-based item identity.
- No diffing of arbitrary DOM trees outside the owned list/branch containers.
- No callback refs or function-valued `do` exports.
- No async list loading, suspense, transition, or animation semantics.
- No replacement of the existing signal/effect scheduler.
