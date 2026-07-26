# JS UI Signal Runtime Demo

This is a small executable reference for the UI model in `doc/ui.md` and
`doc/ui.do`:

- `Signal` stores a value and its subscribers;
- `Computed` tracks signal reads and caches a derived value;
- each text, class, and style binding owns an independent `Effect`;
- a `Scope` owns signals, derived values, effects, DOM bindings, listeners,
  cleanups, and child scopes;
- disposing a child removes its dependency edges without destroying a signal
  owned by its parent.

`counter-do.mjs` stands in for the current `do` export/dispatcher boundary.
The functions have the same shape as the sketch in `doc/ui.do`; the current
compiler does not yet provide UI host bindings or arbitrary UI exports.

Run the lifecycle and fine-grained update checks:

```bash
node --test examples/ui-signal/runtime.test.mjs
```

Serve the browser demo from this directory:

```bash
python3 -m http.server 8000 --directory examples/ui-signal
```

Open `http://127.0.0.1:8000/`. Clicking either counter changes its text,
class, color, and summary through independent effects. Removing the second
counter recursively disposes its signal graph, event listener, effects, and
DOM binding.
