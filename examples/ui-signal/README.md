# TypeScript UI State Runtime Demo

This is a small executable reference for the UI model in `doc/ui.md` and
`doc/ui.do`:

- `State` stores a value and its subscribers;
- `Computed` tracks state reads and caches a derived value;
- each text, class, and style binding owns an independent `Effect`;
- a do-facing `Context` is a frozen lifecycle handle; the internal `Scope`
  record owns state, derived values, effects, DOM bindings, listeners,
  cleanups, refs, and child scopes;
- `ui_each`/`runtime.each` reconciles keyed item Scopes and reuses their roots;
- `_ui_show`/`runtime.show` owns the active branch Scope;
- `ui_ref`/`runtime.ref` stores a static node reference and cleans it up with
  its Scope;
- `deep-do.ts` demonstrates nested record/list paths with independent leaf
  effects and keyed child Scopes;
- disposing a child removes its dependency edges without destroying parent state
  owned by its parent.

`counter-do.ts` stands in for the current `do` export/dispatcher boundary.
Every simulated export receives `Context`, while the runtime resolves that
handle to its private Scope record. The current compiler does not yet provide
UI host bindings or arbitrary UI exports.

The runtime implementation intentionally separates data records from
operations: State, Derived, Effect, and Scope are plain objects manipulated by
free functions. Context contains only `{ id }`; it is not a snapshot of the
component's state. `getMeta`, `getParentContext`, and `getScope` are the host
boundary helpers used by the demo and tests.

Run the type, lifecycle, and fine-grained update checks:

```bash
bun --cwd examples/ui-signal run verify
```

Serve the browser demo from this directory:

```bash
python3 -m http.server 8000 --directory examples/ui-signal
```

Open `http://127.0.0.1:8000/`. Clicking either counter changes its text,
class, color, and summary through independent effects; the action reads its
Context-owned button ref through the runtime. The keyed list can add, reverse, and remove items
without rerendering reused item roots. The conditional section switches
branch Scopes and disposes the inactive branch. Removing the second counter or
a list item recursively disposes its state graph, event listener, effects,
derived values, refs, and DOM binding. The nested order section shows that
changing `customer.name` does not rerun `shipping.city` or another order;
changing a line quantity does not rerun its product field; adding a line only
changes the keyed `lines.structure` reconciliation.

The do-facing host names are conceptual:

```do
counter_color(ctx Context) -> text {
    value = ui_read_i32(ctx, "count")
    if @eq(value, 0) return "gray"
    return "green"
}

ui_each(list_node, ctx, "list_items", "list_item_key", "list_item_render")
_ui_show(details_node, ctx, "show_details", "details_on", "details_off")
ui_ref(button_node, ctx, "increment_button")
```

The TypeScript source reference exposes the same operations as `runtime.each`,
`runtime.show`, and `runtime.ref`. `getEachItem` and `getEachIndex` expose
the current keyed item context to a static export function.

The JavaScript demo module uses the plain export name `list_add`. It is
resolved through the simulated UI module dispatch table, while the standard
library's pure `list_add(xs, value, ...)` remains a separate do function.

The deep prototype uses ordinary state keys rather than Proxy objects:

```text
orders.structure
order:<key>.customer.name
order:<key>.shipping.city
order:<key>.lines.structure
line:<key>.product.name
line:<key>.quantity
```

The keys represent the future host-binding contract. The current `do` compiler
still sees ordinary struct/list values; `deep-do.ts` keeps the normalized path
table on the JavaScript runtime side.
