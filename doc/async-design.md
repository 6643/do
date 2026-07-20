# 异步、Future 与 Host ABI 设计

## 设计原则

- **显式异步**：同步函数、异步函数和显式 `Future<T>` 返回值有清晰边界
- **ABI 对齐**：异步函数 ABI 与 `future<T>` 值 ABI 独立建模，不互相伪装
- 控制流用关键字，操作用函数
- 控制流使用关键字；需要编译器/运行时参与的内建操作使用 `@` 前缀

---

## 命名规则

| 大小写       | 类型                    | 例子                                                                  |
| :----------- | :---------------------- | :-------------------------------------------------------------------- |
| **小写**     | 基础内置类型 / 类型语法 | `i8`, `u32`, `text`, `bool`, `[u8]`                                   |
| **大写开头** | 源码层命名类型          | `Tuple<T, U>`, `Future<T>`, `Stream<T>`, `InputStream`, `StreamError` |

`Tuple<T, U>`、`Future<T>`、`Stream<T>` 跟 `i8`、`text` 一样都是编译器认识的内建类型，不需要通过声明来引入。它们使用大写，是因为它们是源码层的命名泛型类型；WIT/host ABI 中的 `future<...>`、`stream<...>`、`tuple<...>` 仍然只作为宿主类型名使用，不能泄漏为普通 do 源码类型。

`InputStream`、`StreamError` 等通过 `@wasi_resource`、`@host` 声明的类型用大写开头，跟用户定义的类型一致。

---

## 函数形式

do 语言保留两种异步函数形式。它们都可以通过 `await` 使用，但用途和 ABI 不同：

```do
// 编译器管理异步调用边界；对应 async function ABI
async fetch(url text) -> [u8] | IOError { ... }

// 普通函数显式返回一个 Future 值；对应 future value ABI
make_fetch(url text) -> Future<[u8] | IOError> { ... }
```

两种形式的外部调用结果都可表示为 `Future<T>`，但编译器内部必须保留独立的函数效果标记：

```do
async foo() -> i8 { return 42 }

f Future<i8> = foo()
x i8 = await(f)
```

约束：

```text
async foo() -> T          // async function ABI
foo() -> Future<T>        // future value ABI
async foo() -> Future<T>  // 禁止，避免 Future<Future<T>> 歧义
```

`async foo() -> T` 适合包含异步调用和挂起点的函数；`foo() -> Future<T>` 适合转发、组合或构造一个已有 Future。普通异步调用是 eager 的：调用即提交执行，不需要额外的启动操作。

---

## 并发内建操作

以下操作需要编译器和运行时参与，属于内建 special form，不参与普通函数重载：

```do
await(f)
await_all(f1, f2, ...)
await_any(f1, f2, ...)
@cancel(f1, f2, ...)
```

`await`、`await_all` 和 `await_any` 是编译器 special form；`@cancel` 是运行时协作取消操作。

---

## Future 等待

### `await(f)` / `await(f, timeout_ms)`

等待一个 Future 结束。它只挂起当前协程，不阻塞 OS 线程。

```do
// 无限等
r i8 = await(f)

// 带超时，timeout 作为 IO 错误分支返回
r i8 | IOError = await(f, 5000)
```

签名：

```
await:       Future<T>                         → T
await:       Future<T>, u64                    → T | IOError
```

### `await_all(fs...)` / `await_all(fs..., timeout_ms)`

等待所有 Future 结束，不因某一个 Future 失败而提前返回。每个位置保留自己的成功或错误结果；带 timeout 时，未完成项以 `IOError.Timeout` 返回，不再等待它们的底层操作真正结束。

```do
// 等全部结束，成功和错误都保留
x i8, y text | FileError = await_all(f1, f2)

// 超时属于各个 IO 结果的错误分支
x i8 | IOError, y text | FileError | IOError = await_all(f1, f2, 5000)
```

签名：

```
await_all:   (Future<A | E1>, Future<B | E2>, ...)          → (A | E1, B | E2, ...)
await_all:   (Future<A | E1>, Future<B | E2>, ..., u64)     → (A | E1 | IOError, B | E2 | IOError, ...)
```

返回值按参数顺序对应。

### `await_any(fs...)` / `await_any(fs..., timeout_ms)`

等待任意一个 Future 结束。成功或错误都算结束；第一个结束的结果立即返回，并取消其他未完成 Future。

```do
idx usize, val i8 | text = await_any(f1, f2)

// 超时前没有 Future 结束时，取消全部 Future
idx usize, val i8 | text | IOError = await_any(f1, f2, 5000)
```

签名：

```
await_any:   (Future<A>, Future<B>, ...)             → (usize, A | B | ...)
await_any:   (Future<A>, Future<B>, ..., u64)        → (usize, A | B | ... | IOError)
```

返回 `(idx, result)`，`idx` 指示哪个 Future 先完成，`result` 保留该 Future 的成功或错误分支。

---

### 参数总结

| 函数        | 参数                        | 返回值     |
| :---------- | :-------------------------- | :--------- |
| `await`     | `(f)`                       | `T`        |
| `await`     | `(f, timeout_ms)`           | `T | IOError` |
| `await_all` | `(f1, f2, ...)`             | `(A | E1, B | E2, ...)`  |
| `await_all` | `(f1, f2, ..., timeout_ms)` | `(A | E1 | IOError, B | E2 | IOError, ...)` |
| `await_any` | `(f1, f2, ...)`             | `(usize, A | B | ...)`      |
| `await_any` | `(f1, f2, ..., timeout_ms)` | `(usize, A | B | ... | IOError)` |

---

## `Future<T>` 类型

`Future<T>` 是源码层一等类型，主要由以下机制产生或消费：

1. `async` 函数调用的源码层结果；
2. 显式返回 `Future<T>` 的用户函数；
3. host 函数返回的 WIT `future<T>` 值。

`async` 函数和显式 `Future<T>` 函数在源码层都可被 `await`，但 ABI 绑定不能混淆：前者使用 async function ABI，后者使用 future value ABI。普通同步函数不能在其调用边界上阻塞；需要异步调用时必须显式声明为 `async` 或返回 `Future<T>`。

### 源码到 WIT/ABI 的映射

| do 源码形式 | WIT 形式 | ABI 含义 |
| :---------- | :------- | :------- |
| `async foo() -> T` | `async func() -> T` | 异步函数调用效果；调用可能挂起，结果通过 async function ABI 交付 |
| `foo() -> Future<T>` | `func() -> future<T>` | 普通函数返回显式 future 值；Future 句柄通过 future value ABI 交付 |
| `foo() -> T` | `func() -> T` | 同步函数调用，不允许在调用边界阻塞 |

第一行和第二行的 ABI 不可直接互换。语言绑定可以提供 adapter，但 adapter 必须显式承担调度、Future 创建或结果转发成本。

```do
// async function ABI
async foo() -> i8 { return 42 }

// future value ABI
make_foo() -> Future<i8> { return Future.completed(42) }

x i8 = await(foo())
y i8 = await(make_foo())
```

### Future 所有权

`Future<T>` 是一次性消费句柄，不是可复制的普通值：

1. `await`、`await_all`、`await_any` 消费传入的 Future；
2. 同一个 Future 不能被两个等待操作同时消费；
3. `await_any` 返回后，落选 Future 由组合操作负责请求取消和最终释放；
4. `@cancel` 幂等，但不会让已消费的 Future 重新可用；
5. Future 完成、取消或错误后，底层结果只能交付一次。

编译器必须对 Future 句柄执行 move/use-after-wait 检查；runtime 仍需用原子状态转换保护跨线程竞争。

### `Future`/`Stream` 与 Go channel 的对比

|           | Go channel              | do future / stream                   |
| :-------- | :---------------------- | :----------------------------------- |
| 方向      | 收发成对                | 只消费一次（future）或多次（stream） |
| 同步/异步 | 阻塞式 channel 通信     | 通过 `await` 挂起协程                |
| 超时      | `select` + `time.After` | `await(f, timeout_ms)` 内建          |
| 取消      | 关闭 channel + 传播     | `@cancel(fs...)` 内建                |
| 多路复用  | `select` 语句           | `await_all` / `await_any`            |
| 底层模型  | CSP（通信顺序进程）     | Future/Promise（一次性结果）         |

Go 的 `chan T` 是双向通信管道，适合生产者-消费者场景。`Future<T>` 是一次性结果的容器，适合 RPC、IO 等单次异步操作。两者不冲突。

### `Stream<T>` 生命周期

`Stream<T>` 是可多次消费的异步序列，但不等同于 `InputStream` / `OutputStream` 字节资源：

1. `recv(stream)` 在没有数据但 stream 未结束时挂起当前协程；
2. `nil` 表示正常结束，不进入消费循环体；
3. stream 结束后不能再次 receive；
4. consumer 被取消或离开而不再消费时，必须请求取消 producer 并释放底层 host handle；
5. v1 只允许单 consumer，背压和缓冲上限由 stream 实现定义，不能无限制积累数据。

---

## 外部声明

`@host_func`、`@host_resource`、`@host_type`、`@host_variant`、`@host_const` 和 `@lib` 是单行声明。

WIT 的 `async func(...) -> T` 与 `func(...) -> future<T>` 是两种独立 ABI。前者在 do 中写成 `async (...) -> T`，后者写成 `(...) -> Future<T>`；二者不能直接互换。编译器必须从 WIT registry 校验声明的函数效果和结果类型。

下面的异步 host 形态是目标语法，不表示当前 `do build` 已经能够 lower 所有 WASI async/future/stream 签名。当前实现仍需按已登记 ABI 白名单拒绝未知复杂签名。

设计依据：WebAssembly Component Model 当前 WIT/Canonical ABI 文档将 `async` function effect 与 `future<T>` asynchronous value 分开定义；当前 `wasi-io` 主线的 `input-stream.read` 仍是非阻塞 `func`，通过 `pollable` 等待，不应未经版本确认就假设它是 `async func` 或返回 `future<T>`。

- Component Model: <https://github.com/WebAssembly/component-model/blob/main/design/mvp/Explainer.md#asynchronous-value-types>
- WIT function types: <https://github.com/WebAssembly/component-model/blob/main/design/mvp/WIT.md>
- Canonical ABI: <https://github.com/WebAssembly/component-model/blob/main/design/mvp/CanonicalABI.md>
- WASI IO streams: <https://github.com/WebAssembly/wasi-io/blob/main/wit/streams.wit>

语法：

```
名称 = @host_func("包路径", "原名称", 签名)
名称 = @host_resource("包路径", "原名称", 定义)
名称 = @host_variant("包路径", "原名称", 定义)
名称 = @host_const("包路径", "原名称", 类型)
名称 = @lib("文件名.do", 原名)
```

### 宿主函数 `@host_func`

以下以 `wasi:io` 包为例，展示完整的 1:1 映射。

函数签名中的 `async` 与 `Future<T>` 分别对应两种 ABI：

```do
// WIT: async func(...) -> result<list<u8>, stream-error>
host_async_read = @host_func(
    "wasi:io/streams@0.3.0",
    "input-stream.read-async",
    async (InputStream, u64) -> [u8] | StreamError
)

// WIT: func(...) -> future<result<list<u8>, stream-error>>
host_future_read = @host_func(
    "wasi:io/streams@0.3.0",
    "input-stream.read-future",
    (InputStream, u64) -> Future<[u8] | StreamError>
)
```

二者都可以这样消费：

```do
data [u8] | StreamError = await(host_async_read(stream, 4096))
data [u8] | StreamError = await(host_future_read(stream, 4096))
```

但它们的组件类型和 Canonical ABI 不同，不能把一个声明直接替换成另一个。`@host_func` 只表示“声明一个 host 函数”；异步效果或 `Future<T>` 结果由签名决定。

#### 资源类型

```do
// wasi:io/error — 错误资源句柄
IOError = @host_resource("wasi:io/error@0.3.0", "error", { id i64 })

// wasi:io/poll — 轮询句柄
Pollable = @host_resource("wasi:io/poll@0.3.0", "pollable", { id i64 })

// wasi:io/streams — 流资源
InputStream = @host_resource("wasi:io/streams@0.3.0", "input-stream", { id i64 })
OutputStream = @host_resource("wasi:io/streams@0.3.0", "output-stream", { id i64 })
```

#### 错误变体

```wit
// WASI 原定义
variant stream-error {
    last-operation-failed(error),
    closed
}
```

```do
StreamError = @host_variant("wasi:io/streams@0.3.0", "stream-error",
    Closed | LastOperationFailed(IOError))
```

#### 资源方法

```do
// ——— wasi:io/error ———
host_error_debug = @host_func("wasi:io/error@0.3.0", "to-debug-string",
    (IOError) -> text)

// ——— wasi:io/poll ———
host_poll_ready = @host_func("wasi:io/poll@0.3.0", "ready",
    (Pollable) -> bool)
host_poll_block = @host_func("wasi:io/poll@0.3.0", "block",
    (Pollable) -> void)

// ——— wasi:io/streams (input-stream) ———
host_read = @host_func("wasi:io/streams@0.3.0", "input-stream.read",
    (InputStream, u64) -> [u8] | StreamError)
host_blocking_read = @host_func("wasi:io/streams@0.3.0", "input-stream.blocking-read",
    (InputStream, u64) -> [u8] | StreamError)
host_skip = @host_func("wasi:io/streams@0.3.0", "input-stream.skip",
    (InputStream, u64) -> u64 | StreamError)
host_blocking_skip = @host_func("wasi:io/streams@0.3.0", "input-stream.blocking-skip",
    (InputStream, u64) -> u64 | StreamError)
host_subscribe_input = @host_func("wasi:io/streams@0.3.0", "input-stream.subscribe",
    (InputStream) -> Pollable)

// ——— wasi:io/streams (output-stream) ———
host_check_write = @host_func("wasi:io/streams@0.3.0", "output-stream.check-write",
    (OutputStream) -> u64 | StreamError)
host_write = @host_func("wasi:io/streams@0.3.0", "output-stream.write",
    (OutputStream, [u8]) -> void | StreamError)
host_blocking_write_flush = @host_func("wasi:io/streams@0.3.0",
    "output-stream.blocking-write-and-flush",
    (OutputStream, [u8]) -> void | StreamError)
host_flush = @host_func("wasi:io/streams@0.3.0", "output-stream.flush",
    (OutputStream) -> void | StreamError)
host_blocking_flush = @host_func("wasi:io/streams@0.3.0", "output-stream.blocking-flush",
    (OutputStream) -> void | StreamError)
host_subscribe_output = @host_func("wasi:io/streams@0.3.0", "output-stream.subscribe",
    (OutputStream) -> Pollable)
host_write_zeroes = @host_func("wasi:io/streams@0.3.0", "output-stream.write-zeroes",
    (OutputStream, u64) -> void | StreamError)
host_blocking_write_zeroes_flush = @host_func("wasi:io/streams@0.3.0",
    "output-stream.blocking-write-zeroes-and-flush",
    (OutputStream, u64) -> void | StreamError)
host_splice = @host_func("wasi:io/streams@0.3.0", "output-stream.splice",
    (OutputStream, InputStream, u64) -> u64 | StreamError)
host_blocking_splice = @host_func("wasi:io/streams@0.3.0",
    "output-stream.blocking-splice",
    (OutputStream, InputStream, u64) -> u64 | StreamError)
```

### 常量/全局变量

```do
_pi = @host_const("wasi:cli/environment@0.3.0", "PI", f64)
```

### 库导入 `@lib`

```do
sha256 = @lib("sha256.do", sha256)
utf8_count = @lib("utf8.do", utf8_count)
```

---

## 取消

### `@cancel(fs...)`

取消一个或多个 future。支持多参数。

```do
@cancel(f)              // 请求取消一个
@cancel(f1, f2, f3)     // 请求取消多个
```

签名：

```
@cancel: (Future<A>, Future<B>, ...) → void
```

取消是 cooperative cancellation：只发出取消请求，不承诺立即终止底层 host I/O。Future 必须最终进入 `completed`、`canceled` 或错误状态；取消操作幂等。

### 超时与取消的关系

`await(f, timeout_ms)` 的超时会发出取消请求；底层 I/O 的超时结果通过 `IOError` 分支返回。未完成的 host 操作可能在稍后才真正结束，但其结果不能再交付给已超时的等待者。

### 完成、取消与超时的竞态

Future 的完成、取消和 timeout 必须通过一次原子状态转换决定 winner：

```text
pending -> completed          // Future 结果先提交
pending -> cancel_requested   // await_any/cancel/timeout 发出请求
cancel_requested -> canceled  // 可取消边界确认取消
cancel_requested -> completed // host 已完成，结果仍可按规则交付
pending -> failed             // Future 自身失败
```

若 Future 完成和 timeout 同时发生，先成功提交状态的一方生效；另一方只能观察最终状态，不能重复交付结果或覆盖错误。超时返回后，迟到的 host 结果必须丢弃或进入 runtime 日志，不能重新唤醒已返回的等待者。

```do
// 带超时的 wait
r i8 | IOError = await(f, 5000)
// 超时后发出 cancel 请求
```

---

## 对照 JS Promise

| JS                   | do                 | 语义                 |
| :------------------- | :----------------- | :------------------- |
| `Promise.allSettled` | `await_all(fs...)` | 等所有完成，收集结果 |
| `Promise.race`       | `await_any(fs...)` | 第一个完成，取消其余 |
| —                    | `await(f)`         | 等单个 Future        |
| —                    | `await(f, ms)`     | 等单个，超时请求取消 |
| —                    | `@cancel(fs...)`   | 主动请求取消         |

---

## 内置类型 `Timeout`

超时属于 `IOError` 的变体。Future 的取消或 panic 仍属于 Future 生命周期错误；普通 I/O 超时不另建第二条结果通道。

```do
IOError error = NotFound | PermissionDenied | Timeout | ...
```

用户不需要显式导入或声明 `Timeout`——它默认出现在 `IOError` 中。

---

### 分层架构

```
┌──────────────────────────────────────────────────┐
│  源码层内建泛型（大写）                              │
│  ───────────────                                  │
│  Future<T>    // 显式 Future 值 ABI                 │
│  async func   // async function ABI                 │
│  Stream<T>    // loop/recv 需要编译器参与          │
│  Timeout      // IOError 的变体              │
│  FutureError  // Canceled | Panicked          │
└──────────────────────┬───────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────┐
│  标准库 / IO 库（大写开头）                        │
│  ─────────────────────                            │
│  ReadableStream  = Stream<[u8]>  // 读字节流      │
│  WritableStream                  // 写字节流      │
│  TransformStream<I, O>          // 转换流         │
│                                                   │
│  open(path) -> ReadableStream | FileError         │
│  create(path) -> WritableStream | FileError       │
│  pipe(src, dest) -> void | IOError               │
│                                                   │
│  map(s, f) -> Stream<U>                          │
│  filter(s, f) -> Stream<T>                       │
│  take(s, n) -> Stream<T>                         │
│  collect(s) -> [T]                               │
│  recv(s) -> T | nil                              │
└──────────────────────┬───────────────────────────┘
                       │ @host_func 映射
┌──────────────────────▼───────────────────────────┐
│  WASI 实现层                                     │
│  ──────────────                                   │
│  InputStream     → ReadableStream<[u8]>          │
│  OutputStream    → WritableStream<[u8]>          │
│  IOError         → 标准库 IOError                │
│  wasi:io/poll    → 调度器集成                     │
└──────────────────────────────────────────────────┘
```

核心类型（`Future<T>`、`Stream<T>`）是编译器认识的源码层内建泛型，IO 库的类型和函数是标准库提供的。WASI 绑定中的 WIT `future<...>` / `stream<...>` 只在 host ABI 边界出现；WIT 的 `async` 函数效果则映射为 do 函数签名中的 `async` 标记。WASI 只是 IO 库的一种实现来源——同一套接口也可以对接浏览器文件、原生文件系统。

---

## 完整示例

```do
// async function ABI
async foo() -> i8 {
    return 42
}

// future value ABI
make_bar() -> Future<text> {
    return Future.completed("hello")
}

// 异步调用立即提交
a Future<i8> = foo()
b Future<text> = make_bar()

// 等其中一个先完成，5 秒超时
idx usize, val i8 | text | IOError = await_any(a, b, 5000)

// 或者等全部完成，分别保留成功或错误
x i8, y text = await_all(a, b)

// 或者主动取消
@cancel(a, b)
```

---

## 运行时设计

### 设计目标

- 用户不需要手动管理线程/协程
- 异步函数调用立即提交一个协程，`await` 只挂起当前协程但不阻塞 OS 线程
- 单线程模式仍然支持异步 I/O；等待期间把控制权交还 host event loop，不是无异步能力的降级模式
- **支持两种运行模式：**
    - **单线程模式**：浏览器、WASI 无线程支持、`THREADS=1`
    - **多线程模式（M:N）**：原生、WASI with threads，N = CPU 核心数
- 编译到 WASM + WASI 0.3，以及浏览器和原生平台

### 无栈协程方案

Go 的 goroutine 是 runtime 管理的、带可增长独立栈的 stackful goroutine。这里的异步任务不是 fiber，而是由编译器生成 frame 的 stackless coroutine；它只能在 `await` 等已知挂起点暂停。

这里采用 **无栈协程（stackless coroutine）**——编译器将含异步调用/`await` 的函数编译成状态机：

```
含有 async 调用/await 的函数 → 编译器拆成状态机
                        每个 yield 点是一个状态
                        运行时维护协程的唤醒队列
```

```do
// 用户代码——看起来像 goroutine
async fetch(url text) -> [u8] | IOError {
    data [u8] = await(host_http_get(url))  // yield 点
    return data
}

run() {
    f1 Future<[u8] | IOError> = fetch("/a")
    f2 Future<[u8] | IOError> = fetch("/b")
    r1 = await(f1)   // yield 点
    r2 = await(f2)
}
```

编译器把 `run` 翻译成状态机：

```
状态 0: 调用 fetch("/a") → 创建第一个协程，跳到状态 1
状态 1: 调用 fetch("/b") → 创建第二个协程，跳到状态 2
状态 2: await(f1) → 如果 f1 未完成，注册唤醒回调，让出
状态 3: await(f2) → 如果 f2 未完成，注册唤醒回调，让出
状态 4: 完成
```

无栈协程的好处：在所有平台上编译方案一致，区别只在于底层的调度器实现。

### 单线程异步边界

单线程模式可以并发推进多个异步 I/O，但不能并行执行 CPU 代码：

```do
f1 Future<Data> = read_async(file_a)
f2 Future<Data> = read_async(file_b)
a Data = await(f1)
b Data = await(f2)
```

两个 I/O 操作可以同时交给 host，scheduler 在 `await` 处交还 event loop。相反，未包含 `await` 的 CPU 密集协程会一直运行到结束，可能独占单线程 scheduler。v1 不承诺自动抢占；需要拆分 CPU 工作或显式引入后续 safepoint/yield 机制。

### THREADS

`THREADS` 决定使用多少个 OS 线程执行协程。

| 平台       | 检测方式                             |
| :--------- | :----------------------------------- |
| **浏览器** | `navigator.hardwareConcurrency`      |
| **WASI**   | 编译期常量或 `wasi:threads` 的线程数 |
| **原生**   | `std:thread.availableCores()`        |

默认值为 CPU 逻辑核心数。设为 1 则强制单线程模式。

## 运行模式对比

|                 | 单线程异步模式             | 多线程模式（M:N）                  |
| :-------------- | :------------------------- | :--------------------------------- |
| OS 线程数       | 1                          | N（默认 CPU 核心数）               |
| 协程队列        | 1 个全局队列               | 每线程 1 个本地队列 + 1 个全局队列 |
| 负载均衡        | 不需要                     | work-stealing                      |
| 线程同步        | 无需锁                     | atomics / mutex                    |
| 异步等待        | host poll/callback + yield | host poll + worker park/unpark     |
| `wait32/notify` | 不使用                     | 只用于 OS 线程 park/unpark         |
| 适用场景        | 浏览器、无线程 WASI        | 原生、WASI with threads            |
| 设置方式        | `THREADS=1`                | 默认（自动检测 CPU 核心数）        |

### 平台适配

| 平台                         | 线程支持                     | 默认模式                            |
| :--------------------------- | :--------------------------- | :---------------------------------- |
| **WASI（无 threads）**       | ❌ OS 多线程                 | 单线程异步                          |
| **WASI with threads**        | ✅ `wasi:threads` + 共享内存 | 多线程 M:N                          |
| **浏览器**                   | ✅ Web Worker                | 单线程 host event loop 或多线程 M:N |
| **原生 Linux/macOS/Windows** | ✅ pthread / Win32           | 多线程 M:N                          |

### 核心数据结构

```
// 每个异步调用分配一个，存跨 yield 需要的所有状态
struct coroutine_frame {
    state: u32,              // 当前执行到哪一段
    // 跨 yield 存活的局部变量
    url_ptr: i32,            // fetch 的参数
    url_len: i32,
    data_ptr: i32,           // future 结果
    data_len: i32,
    future_id: i32,          // 正在等的 future
}


// future——底层 i32 句柄；状态通过原子 CAS 转换
struct future_handle {
    id: i32,
    coroutine_id: i32,       // 等待此 future 的协程
    pollable: i32,           // WASI pollable 句柄
    state: atomic<FutureState>,
}

enum FutureState {
    pending,
    cancel_requested,
    completed,
    canceled,
    failed,
}

// 线程调度上下文
struct processor {
    local_queue: lock_free_queue,
    wait_table: hash_table,
    poll_set: wasi_poll_set,
    timer_heap: min_heap,
}
```

### 调度器设计（M:P:G 模型）

跟 Go 一样，一套调度器通吃单线程和多线程。区别只在 P 的数量。

```
G (coroutine) = 协程
P (processor) = 调度上下文，持有本地队列
M (machine)   = OS 线程

THREADS = N  → 创建 N 个 P，每个 P 绑定一个 M
THREADS = 1  → 1 个 P + 1 个 M，没有 work-stealing
```

```
THREADS=1:               THREADS=N:

 M ── P ── 本地队列          M1 ── P1 ── 本地队列1 ──┐
       │                    M2 ── P2 ── 本地队列2 ──┤── steal
       wait_table           M3 ── P3 ── 本地队列3 ──┘
       host poll/callback         │
                                  wait_table
                                  poll.block / park
```

**同一个调度循环，同一个代码路径：**

```
fn scheduler(pid) {
    loop {
        // 1. 从本地队列取就绪协程
        g = local_queue.pop()
        if g != null { g.resume(); continue }

        // 2. 尝试 steal（N=1 时 steal 总是空，快速跳过）
        for other in processors {
            g = steal(other.local_queue)
            if g != null { g.resume(); continue }
        }

        // 3. 全局队列
        g = global_queue.pop()
        if g != null { g.resume(); continue }

        // 4. 都没有 → 是否还有协程在等待？
        if wait_table.not_empty() {
            if N == 1 {
                // 单线程：不能 block（会卡死自己），先检查一次 ready()
                ready = wasi_poll.ready(poll_set)
                if ready != null { wake(ready); continue }
                // 仍在等待外部事件：注册宿主回调并把控制权交还宿主
                register_host_resume(poll_set, timer_heap)
                return yield_to_host()
            } else {
                // 多线程：可以放心 block，其他线程还在跑
                ready = wasi_poll.block(poll_set)   // ← 线程休眠，零 CPU
                wake(ready)
                continue
            }
        }

        // 5. 没任何事情可做了
        if N == 1 {
            return runtime_idle()  // 无就绪任务、无外部等待；由入口决定是否结束
        } else {
            // 多线程 → park（休眠后被 unpark 唤醒）
            if all_parked() && wait_table.empty() {
                return runtime_idle()  // 由入口决定是否结束
            }
            park()
        }
    }
}
```

启动时：

```
fn main() {
    n = THREADS
    processors = create_n_processors(n)

    for i in 1..n {
        create_thread(scheduler, i)  // 先启动其余线程
    }
    scheduler(0)  // 主线程最后进入调度
}
```

### async / await / await_all / await_any / @cancel 实现

```
async foo() -> T
├── 分配一个协程控制块
├── 初始状态设为 0
├── 立即放入本地队列（多线程）或全局队列（单线程）
└── 调用方得到一个 Future<T> 句柄
```

显式 Future 函数可以转发已有 Future，而不创建第二层 Future：

```
foo() -> Future<T>
└── 返回 host 或其他函数产生的 Future<T>
```

```
await(f) → T
├── 检查 f 是否已完成
│   ├── 已完成 → 直接取结果返回
│   └── 未完成 →
│       ├── 当前协程注册到 f 的等待列表
│       ├── 保存当前状态机的下一个状态
│       └── yield（让出执行权给调度器）
├── 被唤醒后 → 取结果返回
```

```
await_all(f1, f2, ...) → (T1 | E1, T2 | E2, ...)
├── 为每个 future 注册唤醒回调
├── 计数器 = future 数量
├── 每完成一个 → 原子操作减 1
│   └── 计数器到 0 → 唤醒调用者
└── yield
```

```
await_any(f1, f2, ...) → (usize, A | B | ...)
├── 为每个 future 注册唤醒回调
├── 第一个完成的 → 原子选择 winner
├── 请求取消其他未完成 future
└── 返回 (index, value/error)
```

```
@cancel(fs...) → void
├── 标记 future 为 cancel_requested
├── 唤醒等待者，让协程在可取消边界观察取消状态
├── 底层 host I/O 可能稍后才真正结束
└── Future 最终进入 completed/canceled/error 状态
```

```
await_all(f1, f2, ..., timeout_ms)
├── 注册统一的单调时钟 deadline
├── 已完成项保留原结果
├── deadline 到期 → 对未完成项发出 cancel 请求
└── 未完成项以 IOError 中的 Timeout 分支返回
```

```
await_any(f1, f2, ..., timeout_ms)
├── 注册统一的单调时钟 deadline
├── deadline 前有 Future 完成 → 取消其他并返回 winner
├── deadline 到期 → 取消全部未完成 Future
└── yield
```

### 多线程线程休眠：`wait32` / `notify`

`wait32` / `notify` 只用于多线程 scheduler 的 OS 线程 park/unpark，不负责保存或恢复 Wasm 调用栈，也不直接实现 Future 或协程。Future 的挂起和恢复由编译器生成的 stackless frame/state machine 实现；单线程模式使用 host poll/callback，把控制权交还宿主。

```
memory.atomic.wait32(addr, expected, timeout)    // 线程休眠，等通知
memory.atomic.notify(addr, count)                 // 唤醒等待线程
```

它们提供类似 Linux futex 的等待/通知能力：

| 操作         | 实现                                        |
| :----------- | :------------------------------------------ |
| `park()`     | `memory.atomic.wait32(&park_flag, 0, -1)`   |
| `unpark()`   | `memory.atomic.notify(&park_flag, 1)`       |
| `@cancel(f)` | 设置取消请求，并通过 scheduler 唤醒相关线程 |

```
// park——当前线程休眠
fn park() {
    park_flag.store(0, release)
    // 如果没有其他工作要做，线程在此休眠
    memory.atomic.wait32(&park_flag, 0, -1)
    // 被 unpark 唤醒后继续
}

// unpark——唤醒指定线程
fn unpark(thread_id) {
    park_flag.store(1, release)
    memory.atomic.notify(&park_flag, 1)
}
```

**不会空转。** 多线程 scheduler 没有可运行协程时，OS 线程通过 `wait32` 休眠；新任务或取消请求到达时，通过 `notify` 唤醒线程。单线程 scheduler 不调用 `wait32`，而是返回宿主事件循环。

当前设计不依赖 Wasm Stack Switching Proposal 的 `cont.new`、`suspend`、`resume` 等指令；如果未来需要 stackful coroutine/fiber，可作为独立 backend，不改变 Future/await 语义。

### 无栈协程切换原理

无栈协程的核心：**编译器把含 async 调用/`await` 的函数拆成状态机，每个 yield 点之间的片段是一个状态。**

#### 协程控制块（线性内存中）

```
// 每个异步调用分配一个，存跨 yield 需要的所有状态
struct coroutine_frame {
    state: u32,              // 当前执行到哪一段
    // 跨 yield 存活的局部变量
    url_ptr: i32,            // fetch 的参数
    url_len: i32,
    data_ptr: i32,           // future 结果
    data_len: i32,
    future_id: i32,          // 正在等的 future
}
```

#### 编译产物（WAT 伪代码）

```wat
;; 用户代码：
;;   async fetch(url) { data = await(host_http_get(url)); return data }
;;
;; 编译成三段状态：

;; 状态 0：启动异步操作
(func $fetch_state_0 (param $frame i32))
    ;; 调用 host_http_get，拿到 future
    local.get $frame
    call $host_http_get
    ;; 结果写入 frame.future_id

    ;; 检查是否已就绪
    frame.future_id  call $future_is_ready
    if (i32.eqz)
        ;; 未就绪 → 存帧状态，yield
        frame.state = 1
        yield  ;; ← 回到调度器
    end
    ;; 已就绪 → 直接走 state_1
    fallthrough

;; 状态 1：取 future 结果
(func $fetch_state_1 (param $frame i32))
    frame.future_id  call $future_take_result
    ;; 结果写入 frame.data_ptr / frame.data_len
    frame.state = 2
    yield  ;; ← 回到调度器，让调用者拿结果

;; 状态 2：返回给调用者
(func $fetch_state_2 (param $frame i32))
    return frame.data_ptr, frame.data_len
    frame.state = 3  ;; 结束
    yield
```

#### 切换流程

```
调度器                        fetch 协程
 │                              │
 ├─ resume(frame) ──────────►  state=0：调 host_http_get
 │                              │ future 未完成
 │                              │ frame.state = 1
 │  ◄── yield ───────────────  │ ← 回到调度器
 │                              │ 帧在线性内存里，状态=1
 │  ... 调度其他协程 ...
 │  poll.block 等到了 future
 │
 ├─ resume(frame) ──────────►  查 state=1
 │                              │ 跳 state_1，取 future 结果
 │                              │ frame.state = 2
 │  ◄── yield ───────────────  │
 │
 ├─ resume(frame) ──────────►  state=2：返回结果
 │                              │ frame.state = 3（结束）
 │  ◄── yield ───────────────  │
```

#### yield 时做了什么

```
yield 三件事：
  1. frame.state = 下一段的编号    ← 记住从哪继续
  2. 跨 yield 的变量写回 frame     ← 保存局部变量
  3. return 到调度器               ← 交出控制权

resume 时：
  1. 读 frame.state              ← 知道从哪继续
  2. 跳到对应的 state_N           ← 继续执行
  3. 从 frame 恢复局部变量         ← 数据还在
```

#### 跟栈式协程的对比

|            | 栈式（Go goroutine）     | 无栈协程                |
| :--------- | :----------------------- | :---------------------- |
| 协程内存   | 2-8KB 栈空间             | 几十字节的 frame        |
| 切换代价   | 保存/恢复寄存器 + 栈指针 | 改一个 state 字段       |
| 栈深度限制 | 无（动态增长）           | 不能跨 yield 深调用     |
| 编译器分析 | 不需要                   | 需分析跨 yield 存活变量 |
| 实现复杂度 | 运行时管理栈             | 编译器静态分析          |

### WASM 导出结构

```
// 编译产物
(func (export "_start"))
    call runtime_init
    call main              // main 根据 THREADS 启动调度器

// 调度器让出点（编译器在 async/await 边界插入）
(func (export "yield"))
    // 保存当前状态机状态
    // 将当前协程放回队列或 wait_table
    // 返回调度器
```
