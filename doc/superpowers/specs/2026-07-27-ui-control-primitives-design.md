# UI Control Primitives Design

## Scope

This change extends the executable TypeScript UI runtime reference under
`examples/ui-signal/` with three host primitives:

- `ui_each`: keyed list reconciliation with one child Scope per item;
- `_ui_show`: conditional branch mounting with one child Scope per active branch;
- `ui_ref`: string-keyed DOM references owned by a Scope.

The change also updates `doc/ui.md`, `doc/ui.do`, the browser demo, and the
runtime tests. It includes a nested record/list prototype based on dotted
State keys and keyed child Scopes. It does not modify the compiler, parser,
language grammar, Wasm ABI, or the existing `scope_id + runtime state table`
ownership model.

The TypeScript source files are compiled by Bun to browser ESM under `dist/`.
`tsc --noEmit` checks the source boundary. The runtime implementation keeps
data records and operations separate: State, Derived, Effect, and Scope are
plain objects manipulated by free functions, not class instances.

## Design Evidence

The current reference runtime already provides:

1. automatic Scope, state, derived, effect, and binding IDs;
2. dynamic state dependency tracking through the active observer;
3. recursive child Scope disposal and bidirectional dependency removal;
4. static function-name dispatch from the host runtime to the simulated `do`
   export table;
5. framework-neutral internal graph names: `GraphNode`, `StateSource`,
   `StateObserver`, and `OwnedResource`.

Svelte 5 and Solid 2 provide the relevant semantic reference points, but the
implementation is adapted to this language's constraints. The `do` side has
no closure, pointer, reference, or component struct. JavaScript may use
internal closures for effects and DOM listeners, but none cross the `do`
boundary.

## Context Boundary

`Context` is the only lifecycle handle visible to a do-facing function:

```js
{ id: scopeId }
```

It is frozen and contains no State, Derived, Effect, metadata, or child map.
The runtime resolves it to an internal Scope record:

```text
Context
└── Scope record
    ├── states / derived / effects
    ├── resources / cleanups / refs
    └── parent / children
```

`callDo` accepts a host-side Scope or Context but always invokes the do export
with Context. `getState`, `setState`, `getMeta`, `setMeta`, refs, and cleanup
helpers resolve that handle at the boundary. A child may read a parent-owned
State through its parent Context, but ownership does not move. Disposal
recursively removes child resources and unregisters the Context; later metadata
or parent lookups on that Context return `undefined`.

## Semantic Mapping

| Primitive | Svelte 5 reference | Solid 2 reference | Runtime contract |
| --- | --- | --- | --- |
| `ui_each` | keyed `{#each items as item (item.id)}` | `<For each={items}>` | keyed child Scope reconciliation |
| `_ui_show` | `{#if}` / `{:else}` | `<Show when={...} fallback={...}>` | one active branch Scope |
| `ui_ref` | `bind:this` | `ref` | Context-addressed, Scope-record-owned string-keyed DOM reference |

Both reference frameworks support fine-grained updates. The distinction here
is where the bookkeeping lives: the `do` functions provide stable names and
read/write operations, while JavaScript owns the state graph, DOM nodes,
Scope tree, and cleanup.

## Nested Struct/List State Tree

Nested values keep their ordinary `do` struct/list value semantics. The host
adapter exposes only the paths that need independent UI updates as State
entries, and uses keyed child Scopes for repeated records:

```text
app Scope
└── orders.structure -> [order-1001, order-1002]
    ├── order Scope: order-1001
    │   ├── customer.name
    │   ├── shipping.city
    │   └── lines.structure -> [line-compiler, line-runtime]
    │       ├── line Scope: line-compiler
    │       │   ├── product.name
    │       │   ├── quantity
    │       │   └── price
    │       └── line Scope: line-runtime
    └── order Scope: order-1002
```

The runtime API remains the same:

```js
runtime.getState(orderContext, "customer.name", initialName)
runtime.setState(orderContext, "customer.name", nextName)
runtime.getState(lineContext, "quantity", initialQuantity)
runtime.setState(lineContext, "quantity", nextQuantity)
```

A binding that reads `customer.name` does not subscribe to `shipping.city` or
another order. A quantity update therefore reruns only the quantity binding
and any explicit derived value that reads quantity. A list insertion or
removal updates the corresponding `*.structure` State and lets keyed
reconciliation create or dispose only the affected child Scope. Reordering
moves existing roots and preserves their Scope-local state.

WASI `record` and `list` values cross the host boundary as decoded snapshots.
The adapter writes the relevant fields into path State entries and requires a
stable application key for records that participate in `ui_each`. A
`list<u8>` used as a blob remains one value; it is not implicitly expanded into
per-byte UI State. This prototype does not require Proxy objects, pointers,
references, closures, or a compiler-generated component struct.

The executable reference is `examples/ui-signal/deep-do.ts`. Its record names
are `Order` and `Line`, its tables are `ORDERS` and `LINES`, and its lookup
functions are `getOrder` and `getLine`; the UI surface does not use
data-suffixed names.

## Host API

The `do`-facing names are conceptual host bindings. The JavaScript reference
uses the existing camel-case runtime style.

```do
ui_each(list_node, ctx, "items", "item_key", "item_render")
_ui_show(branch_node, ctx, "show_details", "details_on", "details_off")
ui_ref(button_node, ctx, "increment_button")
```

The runtime API is:

```js
runtime.each(context, listNode, itemsFunction, keyFunction, renderFunction)
runtime.show(context, branchNode, conditionFunction, thenFunction, elseFunction)
runtime.ref(context, node, refKey)
runtime.getRef(context, refKey)
runtime.getEachItem(context)
runtime.getEachIndex(context)
```

`runtime.each` and `runtime.show` return an Effect-like binding resource.
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
    │   ├── item state
    │   ├── index state
    │   └── item render Effects/listeners
    └── item Scope: key=b
```

The key function is called with the parent Context, item, and index. The render
function is called once for a new item Scope and receives that item's Context.
The runtime stores the current item and index as internal state, so an existing
item can update its own bindings without rerunning its render function.

Reconciliation rules:

1. Keys are required and are normalized to a stable runtime key.
2. Duplicate keys throw before the old list is partially mutated.
3. An existing key reuses its Scope and root DOM node.
4. A new key creates a child Scope, initializes item/index state, and calls
   the render function once.
5. A removed key recursively disposes its Scope, including listeners,
   effects, derived values, refs, and DOM cleanup.
6. Reordering moves existing root nodes into the new order without rerendering
   unchanged items.
7. Updating an item's value or index writes its internal state; only
   bindings that read those state values are scheduled.

The demo uses a stable string key. Index is not used as identity because it
would move state and event ownership to a different item after insertion or
reordering.

## `_ui_show` Branch Ownership

`_ui_show` creates one condition Effect on the parent Scope and one child Scope
for the active branch. The branch key is stable (`then` or `else`) within the
binding:

```text
parent Scope
└── if binding Effect
    └── active branch Scope
        ├── branch state
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

`ui_ref(context, node, key)` stores `node` in the internal Scope record under a
static string key. `getRef(context, key)` is the host-side read operation used by an event
action or another binding. A ref registration adds a Scope cleanup that removes
the entry only if it still points to the registered node.

Refs do not provide a callback-ref API. A callback would recreate a closure or
function-value ABI at the `do` boundary. A ref is available only while its
owner Scope is alive; disposing an item or branch removes its refs
automatically.

## Error and Boundary Rules

- `ui_each` rejects a non-array list result and duplicate keys.
- `_ui_show` treats only the explicit boolean result as the condition contract;
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
3. a details panel is mounted through `_ui_show`, with branch-local cleanup;
4. a keyed list is mounted through `ui_each`, with add/remove/reorder actions;
5. the nested order/line panel updates dotted State leaves independently and
   reuses keyed order and line Scopes;
6. removing an item proves that its state, listener, Effect, derived value,
   ref, and DOM node are disposed without affecting sibling items.

The simulated `counter-do.ts` export table remains the stand-in for future
`do` exports. It uses the runtime's static function-name calls and item/branch
context helpers instead of captured component closures.

## Verification

The implementation is accepted only when all of the following pass:

```bash
bun --cwd examples/ui-signal run verify
git diff --check
```

The runtime tests must cover:

- keyed Scope and DOM reuse after reorder;
- item-local update without item render rerun;
- removed-item listener/effect/derived/ref/DOM cleanup;
- `_ui_show` branch reuse and branch cleanup on switch;
- ref registration, replacement, lookup, and Scope disposal;
- parent Scope disposal recursively disposing each/`_ui_show` descendants;
- dotted nested State updates that leave sibling fields and keyed roots unchanged.

Browser verification must confirm that the demo updates the intended item or
branch, leaves sibling items unchanged, and produces no console errors or
warnings after mounting, interaction, reorder, branch switching, nested leaf
updates, and removal.

## Non-goals

- No compiler or parser support for special UI syntax.
- No unkeyed list mode or index-based item identity.
- No diffing of arbitrary DOM trees outside the owned list/branch containers.
- No callback refs or function-valued `do` exports.
- No async list loading, suspense, transition, or animation semantics.
- No replacement of the existing state/effect scheduler.
