// Future UI syntax sketch only.
// This file is not current do syntax, not an implementation fixture, and not
// a commitment that the current compiler already provides these UI bindings.
// The executable JS reference is examples/ui-signal/.

// The component has no component struct. The runtime owns scope_id and all
// signal/effect/binding ids. Source code supplies stable names only.

counter_increment(scope i32) -> nil {
    value = ui_read_i32(scope, "count")
    ui_write_i32(scope, "count", @add(value, 1))
}

counter_text(scope i32) -> text {
    value = ui_read_i32(scope, "count")
    return @to_text(value)
}

counter_class(scope i32) -> text {
    value = ui_read_i32(scope, "count")
    if @eq(value, 0) return "counter empty"
    return "counter active"
}

counter_color(scope i32) -> text {
    value = ui_read_i32(scope, "count")
    if @eq(value, 0) return "gray"
    return "green"
}

counter_summary(scope i32) -> text {
    name = ui_read_text(scope, "name")
    count = ui_read_i32(scope, "count")
    enabled = ui_read_bool(scope, "enabled")

    if !enabled return "disabled"
    return name + ": " + @to_text(count)
}

counter_render(scope i32) -> i32 {
    ui_state_i32(scope, "count", 0)
    ui_state_text(scope, "name", "counter")
    ui_state_bool(scope, "enabled", true)

    root = ui_element("article")
    value_node = ui_element("strong")
    summary_node = ui_element("p")
    button_node = ui_button("+")

    // Each binding owns an independent JS Effect. A count update does not
    // rerun counter_render or rebuild the whole DOM subtree.
    ui_bind_text(value_node, scope, "counter_text")
    ui_bind_text(summary_node, scope, "counter_summary")
    ui_bind_attr(root, "class", scope, "counter_class")
    ui_bind_style(root, "color", scope, "counter_color")
    ui_on_click(button_node, scope, "counter_increment")

    return ui_append(root, value_node, summary_node, button_node)
}

// Parent and child scopes are runtime-owned. A keyed child is reused when the
// key remains stable and is recursively disposed when the key is removed.
counter_list(scope i32) -> i32 {
    first = ui_child_scope(scope, "first")
    second = ui_child_scope(scope, "second")

    first_node = counter_render(first)
    second_node = counter_render(second)
    return ui_append(ui_element("section"), first_node, second_node)
}

// JS runtime contract (conceptual):
//
//   mount("counter", key) -> scope_id
//   call_do("counter_render", scope_id)
//   signal.get() during ui_read_* records the active Effect as a subscriber
//   signal.set() schedules only affected Effects
//   dispose(scope_id) recursively removes child scopes, event listeners,
//       DOM bindings, Effects, Derived values and owned state
//
// An event binding is a static function name plus scope context, not a
// captured do closure. JS may use an internal closure for the DOM listener.
