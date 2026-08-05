// Future UI syntax sketch only.
// This file is not a current do syntax fixture. It records the host-binding
// contract while the compiler still has no UI export/dispatcher special form.
// The executable JavaScript reference is examples/ui-signal/.

// A do function receives a Context handle. Context contains only lifecycle
// identity; State, Derived, Effect, refs and cleanups remain in the host's
// internal Scope record. Runtime ids are allocated automatically.

counter_increment(ctx Context) -> nil {
    value = ui_read_i32(ctx, "count")
    ui_write_i32(ctx, "count", @add(value, 1))
}

counter_text(ctx Context) -> text {
    value = ui_read_i32(ctx, "count")
    return to_text(value)
}

counter_class(ctx Context) -> text {
    value = ui_read_i32(ctx, "count")
    if @eq(value, 0) return "counter empty"
    return "counter active"
}

counter_color(ctx Context) -> text {
    value = ui_read_i32(ctx, "count")
    if @eq(value, 0) return "gray"
    return "green"
}

counter_summary(ctx Context) -> text {
    name = ui_read_text(ctx, "name")
    count = ui_read_i32(ctx, "count")
    enabled = ui_read_bool(ctx, "enabled")

    if !enabled return "disabled"
    // text_concat is a planned standard-library API, not current syntax.
    return text_concat(name, ": ", to_text(count))
}

counter_render(ctx Context) -> i32 {
    ui_state_i32(ctx, "count", 0)
    ui_state_text(ctx, "name", "counter")
    ui_state_bool(ctx, "enabled", true)

    root = ui_element("article")
    value_node = ui_element("strong")
    summary_node = ui_element("p")
    button_node = ui_button("+")

    // Every binding owns an independent host Effect. A count update does not
    // rerun counter_render or rebuild the whole DOM subtree.
    ui_bind_text(value_node, ctx, "counter_text")
    ui_bind_text(summary_node, ctx, "counter_summary")
    ui_bind_attr(root, "class", ctx, "counter_class")
    ui_bind_style(root, "color", ctx, "counter_color")
    ui_on_click(button_node, ctx, "counter_increment")

    return ui_append(root, value_node, summary_node, button_node)
}

// Keyed list bindings use stable item keys. The runtime owns one child Scope
// record per key; reordering preserves item resources and removal recursively
// disposes them. The item function still receives only its Context handle.
list_items(ctx Context) -> list<text> {
    return ui_read_list_text(ctx, "items")
}

list_item_key(ctx Context, item text) -> text {
    return item
}

list_item_text(ctx Context) -> text {
    item = ui_each_item(ctx)
    index = ui_each_index(ctx)
    return text_concat(item, ":", to_text(index))
}

list_item_render(ctx Context) -> i32 {
    root = ui_element("li")
    label = ui_element("span")
    remove_node = ui_button("Remove")

    ui_bind_text(label, ctx, "list_item_text")
    ui_on_click(remove_node, ctx, "list_remove")
    ui_ref(remove_node, ctx, "remove_button")
    return ui_append(root, label, remove_node)
}

list_remove(ctx Context) -> nil {
    item = ui_each_item(ctx)
    parent = ui_parent_context(ctx)
    ui_remove_from_text_list(parent, "items", item)
}

show_details(ctx Context) -> bool {
    return ui_read_bool(ctx, "show_details")
}

details_on(ctx Context) -> i32 {
    node = ui_element("p")
    ui_set_text(node, "details visible")
    ui_ref(node, ctx, "details")
    return node
}

details_off(ctx Context) -> i32 {
    node = ui_element("p")
    ui_set_text(node, "details hidden")
    ui_ref(node, ctx, "details")
    return node
}

// Host binding shape (conceptual only):
//
//   ui_each(list_node, ctx, "list_items", "list_item_key", "list_item_render")
//   _ui_show(details_node, ctx, "show_details", "details_on", "details_off")
//   ui_ref(button_node, ctx, "increment_button")
//
// Deep struct/list prototype (path State + keyed Scope record):
//   ui_read(ctx, "orders.structure")
//   ui_read(order_ctx, "customer.name")
//   ui_read(order_ctx, "lines.structure")
//   ui_read(line_ctx, "product.name")
//   ui_read(line_ctx, "quantity")
//
// JS runtime contract (conceptual):
//
//   instantiate(wasm, do_ui_host_imports) -> instance + export manifest
//   attach(instance.exports, manifest)
//   mount("counter_render", key) -> internal Scope record
//   wasm.exports.counter_render(scope.context) -> do receives Context
//   get_state(ctx, key, initial) -> runtime.getState(ctx, key, initial)
//       records the active Effect as a subscriber during ui_read_*
//   set_state(ctx, key, next) -> runtime.setState(ctx, key, next)
//       schedules only affected Effects
//   each() reuses keyed child Scope records and moves existing roots
//   show() owns the active branch record and disposes it on switch
//   ref() stores a static node under the current Scope record
//   dispose(ctx) recursively removes children, listeners, bindings,
//       Effects, Derived values and owned State
//
// The JavaScript implementation stores data records and operates on them with
// free functions such as create_state/state_get/state_set/create_effect and
// scope_dispose. It does not require class-based State, Effect or Scope types.
// An event binding is a static function name plus Context, not a captured do
// closure. JavaScript may use private host closures for DOM listeners.
// A binding/action name is resolved by JS against the generic host-export
// manifest and its expected ABI. The compiler does not recognize ui_bind_*
// and does not emit ui_dispatch. Private do functions are absent from this
// manifest and cannot be JS callback targets.
//
// Full implementation plan:
//   1. add a generic host-export build target for public entry functions and
//      emit a name/signature/export-name manifest with stable overload names.
//   2. implement generic JS/Wasm wrappers for Context/Node handles, text,
//      lists and structs, including allocation and ownership rules.
//   3. add lib/ui.do as the do-facing host import library; keep graph records
//      and lifecycle implementation inside JS.
//   4. define instantiate -> attach exports -> mount -> initial binding flush.
//   5. make State/Computed dynamic, lazy, Object.is-gated and error-stable.
//   6. add internal dirty-only Watcher, then split every binding into:
//        compute: do derived export runs with dependency tracking;
//        apply: JS consumes its returned value without State access.
//      User ui_watch apply/cleanup have the same no-State-access rule;
//      event actions may read/write State. Microtask flush remains internal.
//   7. add Scope cleanup revision/abort handling and fine-grained keyed
//      struct/list path State, then text_concat, devtools and full ABI tests.
// js_eval is an experiment only, not a UI or host ABI API.
