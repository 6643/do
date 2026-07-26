# JS UI Signal Runtime Demo

This is a small executable reference for the UI model in `doc/ui.md` and
`doc/ui.do`:

- `Signal` stores a value and its subscribers;
- `Computed` tracks signal reads and caches a derived value;
- each text, class, and style binding owns an independent `Effect`;
- a `Scope` owns signals, derived values, effects, DOM bindings, listeners,
  cleanups, and child scopes;
- `ui_each`/`runtime.each` reconciles keyed item Scopes and reuses their roots;
- `ui_if`/`runtime.ifBlock` owns the active branch Scope;
- `ui_ref`/`runtime.ref` stores a static node reference and cleans it up with
  its Scope;
- disposing a child removes its dependency edges without destroying a signal
  owned by its parent.

`counter-do.mjs` stands in for the current `do` export/dispatcher boundary.
The functions have the same shape as the sketch in `doc/ui.do`; the current
compiler does not yet provide UI host bindings or arbitrary UI exports.

Run the lifecycle and fine-grained update checks:

```bash
node --test examples/ui-signal/runtime.test.mjs
tsc -p examples/ui-signal/jsconfig.json
```

Serve the browser demo from this directory:

```bash
python3 -m http.server 8000 --directory examples/ui-signal
```

Open `http://127.0.0.1:8000/`. Clicking either counter changes its text,
class, color, and summary through independent effects; the action reads its
Scope-owned button ref. The keyed list can add, reverse, and remove items
without rerendering reused item roots. The conditional section switches
branch Scopes and disposes the inactive branch. Removing the second counter or
a list item recursively disposes its signal graph, event listener, effects,
derived values, refs, and DOM binding.

The do-facing host names are conceptual:

```do
ui_each(list_node, scope, "list_items", "list_item_key", "list_item_render")
ui_if(details_node, scope, "show_details", "details_on", "details_off")
ui_ref(button_node, scope, "increment_button")
```

The JavaScript reference exposes the same operations as `runtime.each`,
`runtime.ifBlock`, and `runtime.ref`. `getEachItem` and `getEachIndex` expose
the current keyed item context to a static export function.
