# UI 与响应式状态设计

**状态:** 未来设计计划 / 未授权实现。本文定义 UI 状态、副作用监听和函数完成监视的目标语义，不表示当前 compiler、UI runtime 或渲染器已实现。可执行的 JS runtime 参考见 `examples/ui-signal/`。

## 设计边界

UI 响应式层负责把状态变化转换为渲染、日志、缓存刷新等副作用；它不替代异步核心：

| 机制        | 责任                                |
| :---------- | :---------------------------------- |
| `Future<T>` | 等待一次异步结果                    |
| `Stream<T>` | 接收一系列异步事件                  |
| `await`     | 挂起当前异步任务                    |
| `watch`     | 监听状态变化并调度副作用            |
| `monitor`   | 监听函数完成并调度副作用            |
| scheduler   | 执行 ready task、watcher 和 monitor |

`watch` 和 `monitor` 属于 UI/响应式状态层，不改变 `Future`、`Stream`、`await` 和取消的核心语义。

## 推荐的 UI 运行时模型

当前方案采用 **普通函数组件 + JS reactive runtime**。`do` 只提供组件函数、事件动作和派生计算函数; JavaScript 负责 Signal、Derived、Effect、DOM binding、事件监听、scheduler 和生命周期。

```text
Signal<T>       状态单元, 保存值和 subscribers
Derived<T>      派生值, 保存依赖和缓存
Effect          副作用, 例如更新 text/class/style
Action          事件动作, 例如 increment(scope)
Binding         DOM 节点与 Effect 的关联
Scope           组件 owner 和资源清理边界
```

`do` 不创建组件结构体, 不保存捕获闭包, 也不手写 runtime 数字 ID。`scope_id`、`signal_id`、`derived_id` 和 binding id 都由 JS runtime 自动分配; 源码只需要提供组件/状态/事件的稳定 key。Wasm 边界可以把它们表示为不透明整数句柄, 但句柄不属于组件的业务数据。

### JS runtime 与 do 的边界

组件首次 mount 时, JS 创建一个 Scope 并调用普通的 `do` render 函数:

```text
JS: scope = mount("counter", key)
JS: call_do("counter_render", scope)
do: ui_bind_text(node, scope, "counter_text")
do: ui_on_click(button, scope, "counter_increment")
```

函数名或静态 key 只用于定位导出函数; JS runtime 可以把它们转换为内部数字 ID。当前 compiler 未实现 UI export/dispatcher, 因此这些 API 仍是设计草案; 最小桥接只需要固定的 `do_dispatch`/函数表, 不需要把 `funcref`、指针、引用或闭包暴露给 `do`。

事件和响应式回调分工不同:

```text
click event -> counter_increment(scope) -> signal.set(value)
signal.set -> scheduler -> text/class/style Effects
```

### 动态依赖追踪

JS runtime 的 `effect` 在执行期间设置当前 observer。`do` 函数通过 `ui_read_*` 读取 signal 时, host binding 调用 JS 的 `signal.get()` 并登记依赖:

```text
effect(counter_class, scope)
        |
        +-- ui_read_i32(scope, "count")
                |
                +-- count.subscribers.add(class_effect)
```

一个 signal 可以有多个订阅者, 一个 Effect 也可以读取多个 signal。Effect 每次重新执行前, runtime 先删除旧依赖; 条件分支改变后, 依赖边会按本次读取结果重新建立。

因此 `increment` 只修改状态, 不调用 render, 不手写 class 或 style 更新:

```do
counter_increment(scope i32) -> nil {
    value = ui_read_i32(scope, "count")
    ui_write_i32(scope, "count", @add(value, 1))
}
```

### 文本、class、style 和组合派生

每个 DOM 输出建立独立的 Effect, 以保持细粒度更新:

```do
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
```

```text
bind_text(node, counter_text)       -> textContent Effect
bind_attr(node, "class", counter_class) -> class Effect
bind_style(node, "color", counter_color) -> style Effect
```

多个状态的组合函数会自动依赖所有读取到的 signal:

```do
counter_summary(scope i32) -> text {
    name = ui_read_text(scope, "name")
    count = ui_read_i32(scope, "count")
    enabled = ui_read_bool(scope, "enabled")

    if !enabled return "disabled"
    return name + ": " + @to_text(count)
}
```

如果 class 或 style 包含多个独立属性, 应为每个属性建立独立 binding; 如果返回一个完整 style 字符串, 则该字符串是一个整体更新单元。

### `ui_each` keyed 列表

`ui_each` 对齐 keyed `{#each}` 和 Solid `<For>` 的语义。它接收列表函数、key 函数和 item render 函数的静态导出名:

```do
ui_each(list_node, scope, "list_items", "list_item_key", "list_item_render")
```

JS runtime 对每个稳定 key 建立一个 child Scope。item render 函数只在 key 首次出现时调用; 插入、删除和重排由 runtime reconciliation 处理:

```text
list signal -> each Effect -> key map reconciliation
                              ├── reuse item Scope/root
                              ├── create item Scope/root
                              └── dispose removed item Scope
```

key 只能是稳定的 primitive 值。重复 key、`null`、对象和函数 key 都在 host boundary 报错。index 不是 identity; item 重排时, runtime 只更新 item/index context signal, 因此读取它们的 binding 会更新, item render 不会重新执行。

item 函数通过 runtime context 读取当前值, 不需要闭包或手写数字 ID:

```do
list_item_text(scope i32) -> text {
    item = ui_each_item(scope)
    index = ui_each_index(scope)
    return item + ":" + @to_text(index)
}
```

删除 item 时, item Scope 递归取消它的 Effect、Derived、事件、ref 和 DOM cleanup; sibling item 的 Scope 和 state 不受影响。

### `ui_if` 条件分支

`ui_if` 对齐 Svelte `{#if}`/`{:else}` 和 Solid `<Show>`:

```do
ui_if(details_node, scope, "show_details", "details_on", "details_off")
```

condition 函数必须返回 boolean。runtime 为 active branch 建立 child Scope; condition 仍在同一 branch 时复用该 Scope, branch 改变时按以下顺序处理:

1. dispose 旧 branch Scope;
2. 清空 branch container;
3. 创建并调用新 branch render 函数一次;
4. 将新 root 和所有 cleanup 归属到新 branch Scope。

父组件 render 不会因为 branch 切换而重新执行。没有 `else` 函数时, false branch 保持为空。

### `ui_ref` DOM 引用

`ui_ref` 对齐 Svelte `bind:this` 和 Solid `ref`, 但为了适配当前语言只接受静态字符串 key:

```do
ui_ref(button_node, scope, "increment_button")
```

JS runtime 将 node 存入 `scope.refs`; action 可以通过 `getRef(scope, "increment_button")` 读取。ref 替换时旧 registration 会先清理; Scope 卸载时自动删除 ref。callback ref 不进入 `do`, 因为它会重新引入函数值或闭包 ABI。

三种 host binding 的 JS 参考 API 是:

```text
runtime.each(scope, container, items_fn, key_fn, render_fn)
runtime.ifBlock(scope, container, condition_fn, then_fn, else_fn)
runtime.ref(scope, node, key)
runtime.getRef(scope, key)
```

它们都是 Scope-owned runtime resource。scheduler 在执行排队 Effect 前再次检查 `disposed`, 因此 list 删除、branch 切换和父 Scope 卸载不会更新已经脱离 DOM 的节点。

### Scope owner tree 与卸载

Scope 是所有 runtime 资源的 owner, 不只是 state table 的 key:

```text
AppScope
└── CounterScope
    ├── signals
    ├── derived values
    ├── effects/subscriptions
    ├── DOM bindings
    ├── event listeners
    └── child scopes
```

子组件使用 `parent scope + stable key` 建立 child scope。卸载时按 owner tree 递归清理:

1. 将 Scope 标记为 `disposed`, scheduler 跳过其中的待执行 Effect;
2. 递归卸载所有 child Scope;
3. 取消事件监听和 DOM bindings;
4. 从 signal 的 subscribers 中删除 Effect;
5. Derived 取消对 source signals 的订阅, 并删除缓存;
6. 删除该 Scope 自己创建的 signals/state;
7. 执行用户注册的 cleanup;
8. 从父 Scope 和 runtime registry 中移除。

依赖边必须双向可移除:

```text
signal.subscribers -> effects
effect.dependencies -> signals
```

子组件使用父组件共享 signal 时, 卸载子组件只删除子组件的订阅, 不销毁父组件拥有的 signal。Effect 已经排入 ready queue 但组件随后卸载时, 执行前必须再次检查 `disposed`。

正常状态更新不会销毁 Scope; keyed child 被替换或组件明确卸载时才销毁 Scope。`examples/ui-signal/` 提供文本、class、style、派生值和子 Scope 清理的可执行参考。

### 选择这套模型的原因

1. 不需要完整闭包、捕获分析或结构式组件。
2. JS runtime 可以使用闭包保存内部 Effect 和事件 listener, 但这些闭包不进入 `do`。
3. Signal 读取自动建立依赖, 不要求用户手写依赖数组或数字 ID。
4. 每个文本、属性和 style binding 都可以独立更新。
5. Scope 统一拥有子组件、订阅、事件、Derived、DOM binding 和 cleanup。
6. UI API 可以作为普通 host binding 扩展, 不要求每个 DOM 操作成为 compiler special form。

## `watch` 状态监听

`watch` 是响应式语义的概念名称; 第一版 JS runtime 通过 signal read + Effect 自动收集依赖, 不要求引入 `watch x, y { ... }` 这种新的 `do` 语法。

监听一个或多个状态值的目标效果等价于:

```do
x i32 = 0
y i32 = 0

watch x, y {
    render_counter(x, y)
}
```

`watch x, y` 表示对列表中的每个依赖建立监听; 任意一个依赖发生有效变化时, handler 被调度一次。JS runtime 的动态依赖版本不需要预先列出 `x, y`, handler 执行期间的 `ui_read_*` 就是依赖来源。

字段路径也可以作为依赖：

```do
watch user.name, user.avatar {
    render_profile(user.name, user.avatar)
}
```

### 触发规则

1. watcher 默认在注册后执行一次，用于建立初始 UI；
2. 后续只在依赖的新旧值不相等时触发；
3. 同一 scheduler 批次内多个依赖连续变化时只调度一次，handler 读取最终值；
4. `watch` 监听赋值提交或明确的状态更新，不监听普通读取；
5. 字段路径只监听该字段，不隐式执行深度遍历；需要监听多个字段时显式列出；
6. handler 默认只读依赖，不允许直接替换被监听值；状态更新应通过普通赋值或专门的状态 API 完成。

### 生命周期

UI watcher/effect 的订阅属于 runtime `Scope`, 而不是 `do` 函数返回后仍然存在的词法闭包:

```do
render_panel(state PanelState) {
    watch state.title, state.items {
        render_panel_body(state.title, state.items)
    }
}
```

组件 Scope 卸载时, watcher/effect、Derived、事件和 child Scope 一起取消。watcher 不创建脱离 Scope 的后台任务; 如果副作用需要继续运行, 必须显式转移到更长生命周期的 owner。当前语言没有捕获闭包, JS runtime 的 Effect closure 只存在于 host owner 内部。

## `monitor` 函数完成监视

监视函数调用完成后的参数和结果：

```do
add(a i8, b i8) -> i8 {
    return @add(a, b)
}

monitor result = add(a i8, b i8) -> i8 {
    log_call(a, b, result)
}
```

这里的 `result =` 是 monitor 声明语法，不是普通赋值。`a`、`b` 是调用时参数的只读快照，`result` 是函数完成时的只读结果。monitor 不能替换返回值，也不能改变函数的控制流。

带业务错误的函数：

```do
save(path text, data [u8]) -> nil | IOError {
    ...
}

monitor result = save(path text, data [u8]) -> nil | IOError {
    record_save(path, result)
}
```

### 异步函数

对 async 函数，monitor 观察的是最终完成结果，而不是 Future 创建：

```do
async fetch(url text) -> [u8] | IOError {
    data [u8] | IOError = await(host_http_get(url))
    return data
}

monitor result = fetch(url text) -> [u8] | IOError {
    update_ui(result)
}
```

async monitor 的结果上下文还包括 runtime 控制错误：`FutureError` 按异步设计中的隐式传播规则加入完成结果。Wasm trap、panic 和不可捕获的安全终止不进入 monitor。

`monitor result = f(...)` 的默认语义是函数完成监视；它不表示函数刚被调用，也不表示 Future 已经创建。Future 创建和最终完成是两个不同事件，不能混用。

## 调度与副作用

watcher 和 monitor 不在赋值或函数返回点同步重入，而是进入 scheduler 的 ready queue：

```text
状态提交 / 函数完成
        |
        v
收集受影响的 watcher / monitor
        |
        v
按 scheduler 批次去重
        |
        v
进入 ready queue
        |
        v
执行 UI 副作用
```

默认规则：

1. 一个状态在同一批次内多次变更，只保留一次 watcher 调度；
2. 同一个 handler 同一时刻只能有一个实例运行；
3. handler 中包含 `await` 时，它会被编译成普通 async frame；重复触发默认排队，不隐式并行；
4. 需要取消旧渲染任务时，UI 层可以显式保存 Future 并调用 `@cancel`；
5. watcher/monitor 不保证跨线程原子性，跨线程状态仍需使用 runtime 提供的同步或消息机制。

## 与 Stream 的关系

`watch` 适合只关心最新状态：

```do
watch selected_item {
    render_selection(selected_item)
}
```

如果每一次变化都必须保留并按顺序处理，应使用 `Stream<T>`：

```do
reader, writer = newStream<Event>(capacity: 16)
```

可以把两者概括为：

```text
watch  -> latest-value semantics
Stream -> every-event semantics
```

## 非目标

- `watch` 不负责创建线程或实现异步 I/O；
- `monitor` 不替代错误处理、Future 等待或取消；
- 不隐式深度观察所有结构体字段；
- 不把 watcher 自动提升为 detached task；
- 不为 UI 设计引入 `try`、指针或引用语义。
