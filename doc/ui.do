// Future UI syntax sketch only.
// This file is not current do syntax, not an implementation fixture, and not
// a commitment to the final UI design.

Counter {
    count State<i32>
}

counter_text(value i32) -> text {
    return @to_text(value)
}

counter_class(value i32) -> text {
    if @eq(value, 0) {
        return "counter empty"
    }

    return "counter active"
}

counter_click(c Counter, e Element) -> nil {
    count = @get(c, .count)
    value = @state_get(count)
    @state_set(count, @add(value, 1))
}

counter_mount(scope Scope, c Counter) -> View {
    count = state<i32>(0)
    @set(c, .count, count)

    label = text(derived(count, counter_text))
    button_node = button("+")

    bind_click(button_node, counter_click, c)

    return div(
        .{
            class = derived(count, counter_class)
        },
        label,
        button_node
    )
}

// Runtime shape of a callback binding:
//     function + component context + optional event payload
//
// The binding is not a captured closure. `Counter` is a runtime-owned
// component context and is not an independently copied value.

// Candidate UI library/runtime operations:
//     bind_text(element, derived_value)
//     bind_attr(element, name, derived_value)
//     bind_click(element, handler, context)
//     bind_input(element, handler, context)
//     bind_scroll(element, handler, context)
//
// These are ordinary library/host APIs in the design draft. They are not
// required to become one compiler special form per DOM operation.
