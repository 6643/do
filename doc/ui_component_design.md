# UI Component Design Record

## Status And Scope

This document records the intended end-state architecture for the `do` UI
framework. It is a design record, not an implemented source-language feature.

The design targets AOT `do` to Core Wasm, with JavaScript acting only as a Web
platform adapter. It does not require general source closures, source pointers,
source references, or a JavaScript UI runtime.

## Architecture Decision

The framework uses these layers:

```text
do component contract
  -> compiler static template, slots, blocks, and dispatch tables
  -> JavaScript minimal DOM platform adapter
  -> browser DOM, events, observers, timers
```

JavaScript provides DOM creation and mutation, delegated event delivery,
observers, timers, and scheduling. It does not own component state, a virtual
DOM, dependency tracking, effects, or application lifecycle semantics.

The `do` compiler owns the component state machine, UI structure, keyed list
logic, conditional block lifecycle, and static event/message routing.

## Rendering Model

`view(model) -> Ui<Msg>` is a declarative compiler input, not a runtime virtual
DOM builder. The compiler analyzes it into:

- static DOM template nodes, created once per component instance;
- dynamic slots, each associated with a known model dependency;
- conditional `show` blocks with mount and unmount boundaries;
- keyed `each` blocks with retained row instances;
- static event descriptors and handler ids.

For example:

```do
Text{ value = to_text(@get(model, .count)) }
Input{ value = @get(model, .name) }
each(@get(model, .todos), todo_key, todo_row)
```

lowers conceptually to:

```text
CounterModel.count -> text node data slot
CounterModel.name  -> input value slot
CounterModel.todos -> keyed todo block
```

A message does not cause per-frame rendering or full DOM replacement. On a
state transition, generated code updates only changed slots and keyed blocks.
The intended runtime has no general VDOM allocation or reconciliation engine.

## Component Contract

A component is a compile-time descriptor satisfying this contract:

```text
Props
Model
Msg
Output

init(props Props) -> Model
update(model Model, msg Msg) -> ComponentResult<Model, Output>
view(model Model) -> Ui<Msg>
```

The planned surface form is:

```do
component Counter {
    Props = CounterProps
    Model = CounterModel
    Msg = CounterMsg
    Output = CounterOut

    init = counter_init
    update = counter_update
    view = counter_view
}
```

This is not a runtime interface object and does not store functions in a
struct. It is a compile-time binding that lets the compiler generate mount,
dispatch, patch, and cleanup functions for the component.

`Output = nil` is valid for leaf components with no parent-visible output.

## Message Boundaries

Every component owns its own `Msg` type. Different DOM event kinds decode into
different variants of that one component-local sum type.

```text
click event      -> CounterMsg.Increment
input event      -> CounterMsg.NameChanged(text)
checkbox event   -> CounterMsg.ToggleTodo(key)
```

Nested components may have separate `Msg` and `Output` types. A parent embeds a
child with a static output constructor:

```do
Child{
    key = todo_id,
    component = TodoRow,
    props = todo,
    output = CounterMsg.TodoEvent,
}
```

`CounterMsg.TodoEvent` is a statically known constructor from `(child_key,
child_output)` to the parent message. It is not a closure or a runtime callback.

## Events And JavaScript Adapter

An event field holds a typed descriptor, not a user callback:

```do
Button{
    text = "+",
    on = Events{
        click = Emit(Increment),
    },
}

Input{
    on = Events{
        input = InputText(NameChanged),
        keydown = KeySubmit(AddTodo),
    },
}
```

The adapter uses delegated event listeners. A DOM event carries a static
handler id, component instance id, optional keyed-row id, and normalized event
payload back to a compiler-generated `do` dispatch entry. JavaScript owns its
own listener closures; no `do` function crosses the JavaScript boundary.

## Custom Events

There are two distinct custom-event paths.

Component-to-component business events use the typed `Output` boundary. They
do not create a DOM event and do not pass through JavaScript.

Browser `CustomEvent` values from a custom element or third-party widget must
declare a static event name, a serializable detail schema, and a static message
constructor:

```do
EditorChange {
    value text
    revision i32
}

EditorMsg = Changed(EditorChange)

RichEditor{
    on = Events{
        custom = CustomEvent<EditorChange, EditorMsg>{
            name = "editor-change",
            into = Changed,
        },
    },
}
```

`CustomEvent<Detail, Msg>` is a typed event descriptor value, not a callback or
a function call. `into` is a statically checked `Msg` variant tag whose payload
must accept `Detail`. The compiler records the event name and detail schema in
the adapter contract. The JavaScript adapter normalizes `event.detail` into the
declared value layout, then invokes the static component dispatch entry.
Arbitrary JavaScript objects, functions, and object references do not cross
this boundary.

If a custom DOM event bubbles, the adapter handles it through root delegation.
If it does not bubble, the generated node binding installs one adapter-owned
listener and removes it automatically on node replacement or component
unmount.

## Ref And Lifecycle

`Ref("name")` is a component-scoped stable ref slot, not a DOM or JavaScript
object reference:

```text
(component_instance_id, ref_key, node_generation)
```

Normal events belong in the node `on` field and are automatically removed when
the node is replaced or unmounted. Ref-based commands run after a commit:

```do
AfterCommit{
    commands = [Focus(Ref("todo_input"))],
}
```

Ref-bound observers such as resize or intersection observers emit typed
messages. On node or component unmount, the adapter removes listeners, clears
the ref slot, cancels associated observers, and rejects late notifications with
an old node generation.

## Explicit Non-Goals

- JavaScript full UI runtime ownership.
- React-style general VDOM runtime as the final renderer.
- Solid-style user-facing signal/effect dependency runtime.
- General source closures or cross-boundary callbacks.
- Direct `document.*` access from `do` component code.
- Per-frame full-tree rendering as the main Web UI model.

Immediate-mode UI remains a possible separate future tool/debug UI model. It
is not the primary DOM application framework described here.
