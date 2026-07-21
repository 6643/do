# UI 与响应式状态设计

**状态:** 未来设计计划 / 未授权实现。本文定义 UI 状态、副作用监听和函数完成监视的目标语义，不表示当前 compiler、UI runtime 或渲染器已实现。

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

当前草案不采用完整可逃逸闭包作为 UI 基础。组件函数可以继续是普通函数, 但长期存活的状态和回调上下文必须显式保存。

```text
Signal<T> / State<T>       状态单元
Derived<T>                 从状态派生的值
Action                     function + context + payload
Scope                      组件 owner 和清理边界
```

事件绑定不保存隐式闭包, 而保存函数入口和显式组件上下文:

```do
bind_click(button, counter_click, counter)
```

runtime 调用时等价于:

```text
counter_click(counter, event)
```

派生文本、class 和属性使用 `Derived<T>`:

```do
count = state<i32>(0)
label = text(derived(count, counter_text))
class = derived(count, counter_class)
```

`derived` 的 mapper 只接收状态当前值; 组件上下文不通过隐式捕获传入。需要额外上下文的长期回调使用显式 `context` 参数。

组件 scope 负责订阅、事件和资源清理。组件卸载时, scope 按注册顺序的逆序取消订阅并释放绑定, 不要求用户为每个 DOM 操作手写 `unbind`。

这套模型借鉴了显式 signal、derived value、action context、scope cleanup 和 keyed list 的组合, 但不要求 `do` 暴露指针、`anyopaque`、allocator 或 Zig 的 comptime 泛型实现。

### 假设案例

以下仅是未来 API 草稿, 不是当前语法或实现测试:

```do
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
```

这里的 `bind_click`, `text`, `button`, `div` 和 `derived` 都是未来 UI library/runtime API 的候选形态; 不要求它们成为每个 HTML 操作对应的 compiler special form。`Counter` 参数表示 runtime owner 管理的组件上下文, 不是可复制后独立运行的普通值。

### 选择这套模型的原因

1. 不需要完整闭包、捕获分析或通用函数字段。
2. 事件回调和异步任务可以复用同一套 `function + context` ABI。
3. signal 依赖在 `Derived<T>` 上显式表达, 不需要 `watch = .{...}` 和 `inject = .{...}` 两套字段。
4. 组件清理集中在 `Scope`, 与事件取消、订阅取消和资源释放保持同一 owner 边界。
5. UI API 可以作为普通库/host binding 扩展, 新增 `focus`, `get_rect`, `scroll_into_view` 等操作不要求修改 compiler。

## `watch` 状态监听

监听一个或多个状态值：

```do
x i32 = 0
y i32 = 0

watch x, y {
    render_counter(x, y)
}
```

`watch x, y` 表示对列表中的每个依赖建立监听；任意一个依赖发生有效变化时，handler 被调度一次。handler 执行时读取到所有依赖的最新值。

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

`watch` 的订阅属于当前词法作用域：

```do
render_panel(state PanelState) {
    watch state.title, state.items {
        render_panel_body(state.title, state.items)
    }
}
```

作用域离开时，订阅自动取消。watcher 不创建脱离作用域的后台任务；如果副作用需要继续运行，必须显式使用已有的 `detach` 语义。

当前语言没有捕获闭包。compiler 应把 watcher 的依赖和 handler 所需状态显式放入响应式订阅记录或 UI frame，不隐式生成普通可逃逸闭包。

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
