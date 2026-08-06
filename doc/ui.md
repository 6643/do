# UI 与响应式状态设计

**状态:** UI host-binding 设计草案 + 可执行 TypeScript runtime 参考。compiler 已提供通用 `--host-export --host-manifest` Core Wasm 函数导出清单，但尚未提供 UI host imports 或 JS 值 ABI；`examples/ui-signal/` 仍用普通 TypeScript 函数验证运行时语义，浏览器加载构建产物 `dist/demo.js`。

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

当前方案采用 **普通函数组件 + JS State runtime**。`do` 只提供组件函数、事件动作和派生计算函数; JavaScript 负责 State、Derived、Effect、DOM binding、事件监听、scheduler 和生命周期。

```text
State<T>        状态单元, 保存值和 subscribers
Derived<T>      派生值, 保存依赖和缓存
Effect          副作用, 例如更新 text/class/style
Action          事件动作, 例如 increment(ctx)
Binding         DOM 节点与 Effect 的关联
Context         do-facing 生命周期句柄, 只包含自动分配的 id
Scope record    JS 内部 owner, 保存资源和父子关系
```

`do` 不创建组件结构体, 不保存捕获闭包, 也不手写 runtime 数字 ID。`scope_id`、`state_id`、`derived_id` 和 binding id 都由 JS runtime 自动分配; 源码只需要提供组件/状态/事件的稳定 key。Wasm 边界可以把 Context 表示为不透明整数句柄, 但它不是组件业务数据的快照。

Context 与内部 Scope record 的关系是:

```text
Context { id }
    |
    +-- Scope record
        +-- states / derived / effects
        +-- resources / cleanups / refs
        +-- parent / children
```

Context 只负责标识和生命周期查找, 不复制 State、Derived 或 Effect。JS runtime
用普通数据记录保存这些对象, 再用 `create_state`、`state_get`、
`create_effect`、`scope_dispose` 等自由函数操作它们; runtime 内部不依赖
`class State`、`class Effect` 或 `class ScopeRecord`。

Context 相关的 JS 参考 API 是:

```text
runtime.getContext(scope) -> Context
runtime.getParentContext(ctx) -> Context | undefined
runtime.getMeta(ctx, key, initial) -> value | undefined
runtime.setMeta(ctx, key, value)
runtime.disposeScope(ctx)
```

### JS runtime 与 do 的边界

目标方案中, JS 先 instantiate Wasm, 注入 `do:ui` host imports, 读取 compiler
生成的通用 host-export manifest。组件首次 mount 时, JS 创建内部 Scope 和对应
Context, 再调用 entry module 的公开 render export:

```text
JS: scope = mount("counter_render", key)
JS: wasm.exports.counter_render(scope.context)
do: counter_render(ctx Context) { ... }
do: ui_bind_text(node, ctx, "counter_text")
do: ui_on_click(button, ctx, "counter_increment")
```

`ui_bind_*` 中的函数名由 JS runtime 通过通用 manifest 查找公开 Wasm export,
并按 binding 需要的 ABI 校验签名。例如 text binding 要求 `(Context) -> text`。
compiler 不认识 UI 库函数, 不 lower UI 字符串, 也不生成 `ui_dispatch`。私有
`.function` 不出现在 host-export manifest, 因而不能成为 JS callback 目标。

当前可执行的通用构建命令是:

```text
do build app.do --host-export --host-manifest app.host.json -o app.wat
```

它导出 entry module 的公开、非泛型函数，并记录 source name、稳定的 WAT export
name，以及分开的 `source_params`/`source_results` 和
`wasm_params`/`wasm_results`。此版本的 `core-wasm-v1` manifest 只描述已有
Core Wasm ABI; `text` 当前作为 `i32` managed handle 出现。tuple、unmanaged
struct、union 与 callback 参数的完整展开仍须与 WAT emitter 共享一套 ABI 规则;
list/struct 的 JS 值表示和 ARC 所有权协议也尚未定义，因此 runtime 不能据此宣称
完整的 JS/Wasm UI bridge。

事件和响应式回调分工不同:

```text
click event -> counter_increment(ctx) -> set_state(ctx, "count", value)
set_state -> runtime.setState -> scheduler -> text/class/style Effects
```

### 动态依赖追踪

JS runtime 的 `effect` 在执行期间设置当前 observer。`do` 函数通过 `ui_read_*` 读取 state 时, host binding 调用 `get_state(ctx, key, initial)` 对应的 `runtime.getState(ctx, key, initial)` 并登记依赖:

```text
effect(counter_class, ctx)
        |
        +-- ui_read_i32(ctx, "count")
                |
                +-- count.subscribers.add(class_effect)
```

一个 state 可以有多个订阅者, 一个 Effect 也可以读取多个 state。Effect 每次重新执行前, runtime 先删除旧依赖; 条件分支改变后, 依赖边会按本次读取结果重新建立。

### compute 与 apply 分相

借鉴 Solid 2 的 compute/apply 分相, 但不照搬 `createEffect` 的源码 API。
JS runtime 内部为每个 binding 建立两个阶段:

```text
compute:
    activeObserver = binding
    value = wasm export / do derived function(Context)
    activeObserver = null

apply:
    若 value 与上次结果相等则跳过
    否则只写 DOM 或执行用户副作用
```

compute 是唯一允许自动追踪 `ui_read_*` 的阶段。它在开始前删除 binding 的旧
依赖, 本轮读取重新建立依赖边; 因此条件分支可以自然切换订阅。apply 不进入
observer, 不读取或写入 State, 只消费 compute 已经返回的普通值。事件 action
可以读写 State, 但不建立 effect 依赖。开发模式必须在 compute 写 State 或
apply 读写 State 时报告错误。

例如 `ui_bind_text(node, ctx, "counter_text")` 的内部模型是:

```text
compute -> wasm.exports.counter_text(ctx) -> text
apply(text) -> node.textContent = text
```

它仍是细粒度更新: 只有读取到同一 State 的 binding 会 compute; compute 输出
未变化时, 对应 DOM apply 也不会执行。

因此 `increment` 只修改状态, 不调用 render, 不手写 class 或 style 更新:

```do
counter_increment(ctx Context) -> nil {
    value = ui_read_i32(ctx, "count")
    ui_write_i32(ctx, "count", @add(value, 1))
}
```

### 文本、class、style 和组合派生

每个 DOM 输出建立独立的 Effect, 以保持细粒度更新:

```do
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
```

```text
bind_text(node, counter_text)       -> textContent Effect
bind_attr(node, "class", counter_class) -> class Effect
bind_style(node, "color", counter_color) -> style Effect
```

多个状态的组合函数会自动依赖所有读取到的 state。文本拼接不是数值
`@add` 的职责; `+` 也不是当前语言语法。下面是规划中的
`text_concat` 库 API 具备后应有的写法, 不是当前 compiler 已支持的调用:

```do
counter_summary(ctx Context) -> text {
    name = ui_read_text(ctx, "name")
    count = ui_read_i32(ctx, "count")
    enabled = ui_read_bool(ctx, "enabled")

    if !enabled return "disabled"
    return text_concat(name, ": ", to_text(count))
}
```

如果 class 或 style 包含多个独立属性, 应为每个属性建立独立 binding; 如果返回一个完整 style 字符串, 则该字符串是一个整体更新单元。

### `ui_each` keyed 列表

`ui_each` 对齐 keyed `{#each}` 和 Solid `<For>` 的语义。它接收列表函数、key 函数和 item render 函数的静态导出名:

```do
ui_each(list_node, ctx, "list_items", "list_item_key", "list_item_render")
```

JS runtime 对每个稳定 key 建立一个 child Scope。item render 函数只在 key 首次出现时调用; 插入、删除和重排由 runtime reconciliation 处理:

```text
list state -> each Effect -> key map reconciliation
                              ├── reuse item Scope/root
                              ├── create item Scope/root
                              └── dispose removed item Scope
```

key 只能是稳定的 primitive 值。重复 key、`null`、对象和函数 key 都在 host boundary 报错。index 不是 identity; item 重排时, runtime 只更新 item/index context state, 因此读取它们的 binding 会更新, item render 不会重新执行。

item 函数通过 runtime context 读取当前值, 不需要闭包或手写数字 ID:

```do
list_item_text(ctx Context) -> text {
    item = ui_each_item(ctx)
    index = ui_each_index(ctx)
    return text_concat(item, ":", to_text(index))
}
```

删除 item 时, item Scope 递归取消它的 Effect、Derived、事件、ref 和 DOM cleanup; sibling item 的 Scope 和 state 不受影响。

JavaScript reference module 的 UI 事件动作使用普通的 `list_add` 导出名;
它通过模拟 UI module dispatch table 解析。标准库的
`list_add(xs, value, ...)` 仍然是返回新 `List<T>` 的纯集合函数, 两者属于
不同命名空间, 不共用参数语义。未来的 `do` host binding 草案可以继续使用
`ui_list_add` 这类显式名字。

### 嵌套 struct/list 的深层更新原型

完整的 `struct/list` 不应该作为一个巨大的响应式 State 交给所有 binding。未来的 host binding 将结构状态和叶子状态拆开:

```text
orders.structure
order:<key>.customer.name
order:<key>.shipping.city
order:<key>.lines.structure
line:<key>.product.name
line:<key>.quantity
```

订单列表和明细列表分别由 `ui_each` 的 keyed child Scope 管理。修改
`customer.name` 只触发姓名 binding; 修改一个明细的 `quantity` 只触发该
明细的数量 binding; 添加或删除明细只触发 `lines.structure` 的
reconciliation。父级派生值如果读取整个列表, 才订阅列表结构或显式读取到的
叶子值。

`examples/ui-signal/deep-do.ts` 是这套规则的可运行原型。它使用 dotted
path 作为稳定 State key, 不使用 Proxy, 不把指针、引用或 ARC handle 暴露给
`do`。数字 state/binding ID 仍由 JS runtime 自动分配。

`do` 的 struct、`[T]` 和 `List<T>` 继续保持值语义; WASI record/list 在
canonical ABI 边界先解码为快照, 再由 host adapter 写入路径 State。WASI
`list<u8>` 可以保持 blob 语义, 只有需要 UI 逐项观察的 record/list 才需要
应用级稳定 key。当前 compiler 的 WASI lowering 仍只覆盖已登记的 record、
`list<u8>` 和固定子集, 这段原型不表示任意嵌套 WIT 类型已经可调用。

### `_ui_show` 条件分支

`_ui_show` 对齐 Svelte `{#if}`/`{:else}` 和 Solid `<Show>`:

```do
_ui_show(details_node, ctx, "show_details", "details_on", "details_off")
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
ui_ref(button_node, ctx, "increment_button")
```

JS runtime 将 node 存入内部 Scope record 的 `refs`; action 可以通过 `getRef(ctx, "increment_button")` 读取。ref 替换时旧 registration 会先清理; Context 对应的 Scope 卸载时自动删除 ref。callback ref 不进入 `do`, 因为它会重新引入函数值或闭包 ABI。

三种 host binding 的 JS 参考 API 是:

```text
runtime.each(ctx, container, items_fn, key_fn, render_fn)
runtime.show(ctx, container, condition_fn, then_fn, else_fn)
runtime.ref(ctx, node, key)
runtime.getRef(ctx, key)
```

它们都是 Context 对应 Scope-owned 的 runtime resource。scheduler 在执行排队 Effect 前再次检查 `disposed`, 因此 list 删除、branch 切换和父 Scope 卸载不会更新已经脱离 DOM 的节点。

### Context 与 owner tree 卸载

Scope record 是所有 runtime 资源的 owner, Context 只作为 do-facing 生命周期句柄:

```text
AppScope
└── CounterScope
    ├── state
    ├── derived values
    ├── effects/subscriptions
    ├── DOM bindings
    ├── event listeners
    └── child scopes
```

子组件使用 `parent Context + stable key` 建立 child Scope。子组件可以读取父级 State, 但不取得父级资源的 ownership。卸载时按 owner tree 递归清理:

1. 将 Scope 标记为 `disposed`, scheduler 跳过其中的待执行 Effect;
2. 递归卸载所有 child Scope;
3. 取消事件监听和 DOM bindings;
4. 从 state 的 subscribers 中删除 Effect;
5. Derived 取消对 source state 的订阅, 并删除缓存;
6. 删除该 Scope 自己创建的 state;
7. 执行用户注册的 cleanup;
8. 从父 Scope 和 runtime registry 中移除。

依赖边必须双向可移除:

```text
state.subscribers -> effects
effect.dependencies -> state
```

子组件使用父组件共享 state 时, 卸载子组件只删除子组件的订阅, 不销毁父组件拥有的 state。Effect 已经排入 ready queue 但组件随后卸载时, 执行前必须再次检查 `disposed`。

正常状态更新不会销毁 Scope; keyed child 被替换或组件明确卸载时才销毁 Scope。Context 被销毁后从 runtime registry 移除, 通过该 Context 的 `getMeta`/`getParentContext` 返回 `undefined`; 父级 State 不会因子级卸载而销毁。`examples/ui-signal/` 提供文本、class、style、派生值和子 Scope 清理的可执行参考。

### 选择这套模型的原因

1. 不需要完整闭包、捕获分析或结构式组件。
2. JS runtime 可以使用闭包保存内部 Effect 和事件 listener, 但这些闭包不进入 `do`。
3. State 读取自动建立依赖, 不要求用户手写依赖数组或数字 ID。
4. 每个文本、属性和 style binding 都可以独立更新。
5. Scope 统一拥有子组件、订阅、事件、Derived、DOM binding 和 cleanup。
6. UI API 可以作为普通 host binding 扩展, 不要求每个 DOM 操作成为 compiler special form。

## `watch` 状态监听

`watch` 是响应式语义的概念名称, 不是已采纳的 `do` 块语法。当前方案不引入
`watch x, y { ... }`, 也不要求 `do` 传递函数值。`ui_bind_*` 已经是 DOM
渲染 effect; 后续的用户副作用使用三组静态函数名:

```do
ui_watch(ctx, "profile_compute", "profile_apply", "profile_cleanup")
```

`profile_compute(ctx)` 通过 `ui_read_*` 动态建立依赖并返回普通值;
`profile_apply(ctx, value)` 只消费该值并执行用户副作用, 不能调用 `ui_read_*`
或 `ui_write_*`; `profile_cleanup(ctx, value)` 在下一次 apply 前和 Scope 销毁时
执行, 同样不读写 State。函数名由 JS runtime 在 host-export manifest 中按 ABI
解析; JS runtime 创建真正的 observer、订阅和 closure, 它们不进入 `do` 的 ABI。

组件 Scope 卸载时, watcher/effect、Derived、事件和 child Scope 一起取消。
watcher 不创建脱离 Scope 的后台任务; 如果副作用需要继续运行, 必须显式转移到
更长生命周期的 owner。当前语言没有捕获闭包, JS runtime 的 Effect closure
只存在于 host owner 内部。

## 下一阶段改进列表

以下按依赖顺序排列。第 6 至第 8 项借鉴 TC39 Signals Stage 1: 它只定义
反应图和低层 watcher, 不标准化 effect、scheduler、owner、渲染或销毁。这些
框架责任归 JS runtime 和 Scope 所有。清单不引入 UI compiler special case、
`ui_dispatch` 或正式 `js_eval` API。

1. **通用 host-export 构建目标。** 普通 CLI/WASI 构建保持现有入口; host-export 构建把 entry module 直接声明的非私有函数变成可调用的 Wasm export。`.private` 函数不导出。这个规则服务所有 host, 不属于 UI 语法。
2. **通用 export manifest。** 与 Wasm 一同输出公开函数的 source name、实际 Wasm export name、参数 ABI 和返回 ABI。重载使用稳定 ABI mangling; host 按名字和期待签名解析, 不猜内部符号或内存布局。
3. **通用 JS/Wasm ABI wrapper。** 实现标量、`Context`、`Node` handle、`text`、`[T]` 和 struct 的参数/返回值 wrapper, 明确分配、读取、释放和所有权。该层也为后续 Component/WIT export 服务。
4. **`lib/ui.do`。** 建立 do-facing UI host import 库, 只声明 Context/Node handle、State、DOM、binding、event、each/show/ref API。`State`、`Computed`、`Watcher`、Scope 留在 JS runtime。`examples/` 中的文件不作为标准库权威接口。
5. **初始化和挂载协议。** JS 创建 runtime imports 后 instantiate Wasm, 读取 manifest 并 attach exports; mount 创建 Scope/Context, 调用公开 render export, render 返回后统一执行首轮 binding。JS runtime 通过 manifest 解析 binding/action 的函数名和 ABI, compiler 不认识 `ui_bind_*`。
6. **`State` 与 `Computed` 图。** `State.get/set` 保存源值; `Computed.get` 动态追踪同步读取的 source, 保持惰性重算和缓存。Computed 在通知下游前以 `Object.is` 门控; compute 异常缓存并重抛, 或交给明确的 UI error boundary 策略。compute/derived 上下文禁止写 State。
7. **低层 `Watcher` 通知。** Watcher 只订阅 graph dirty 通知; `notify` 同步且不允许读写 State 或 Computed。它不等于 user effect, 只把后续工作交给框架 scheduler; do 不暴露 `Watcher`、`untrack` 或 root effect API。
8. **执行模式、effect 与调度。** 借鉴 Solid compute/apply 分相, 但不复制其 API。区分 structural render、compute、render apply、event action 与 user-effect apply。`ui_bind_*` 的 compute 调用 do 派生 export 并动态收集依赖, apply 只更新 DOM; `ui_watch` 使用 compute/apply/cleanup 函数, apply/cleanup 不追踪或读写 State。graph dirty 同步传播, JS scheduler 默认 microtask 批处理, 先完成 compute 和 DOM apply, 再执行 user-effect apply。flush 仅为 JS runtime 内部测试和命令式边界, 不提供 do API。
9. **所有权和异步清理。** Scope 统一拥有 binding、watcher 订阅、user-effect cleanup、事件、ref 和 child Scope。cleanup 在 rerun 前和 dispose 时执行; 异步任务带 Scope revision 或 abort token, 防止卸载后写入 DOM。
10. **struct/list 细粒度状态。** 使用结构 State 与叶子路径 State: `orders.structure`、`order:<id>.customer.name`、`line:<id>.quantity`。keyed child Scope 使用实体稳定 key, 不以 index 为 identity。先由 runtime 生成和校验路径, 后续才考虑通用 compiler 辅助。
11. **文本源能力。** 标准库增加 `text_concat(a text, b text, rest ...text) -> text`。禁止把 `@add` 用作字符串拼接; `to_text` 继续是普通函数名, 不使用 `@to_text`。
12. **错误、开发工具、测试和文档。** JS devtools 显示 graph、pending queue 与 Scope owner tree; 覆盖 host export、ABI wrapper、动态依赖、相等跳过、销毁、列表重排和跨 Wasm/JS mount。同步删除过时的 dispatcher/UI compiler special-case 文档。

当前 `examples/ui-signal/runtime.ts` 仍是第一版参考实现: 调度立即 flush、effect
单阶段执行, 没有 Wasm host ABI。上述清单是后续实现计划, 不应误读为已经具备的行为。

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

### 含异步操作的函数

对包含异步操作的函数，monitor 观察的是最终完成结果，而不是 Future 创建：

```do
fetch(url text) -> [u8] | IOError {
    data [u8] | IOError = @await(host_http_get(url))
    return data
}

monitor result = fetch(url text) -> [u8] | IOError {
    update_ui(result)
}
```

异步 monitor 的结果上下文还包括 runtime 控制错误：`FutureError` 按异步设计中的隐式传播规则加入完成结果。Wasm trap、panic 和不可捕获的安全终止不进入 monitor。

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
