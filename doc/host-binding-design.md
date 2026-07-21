# Host Binding 设计

**状态:** 未来设计计划 / 未授权实现。本文定义通用 host 声明和 WIT 类型映射，不表示当前 compiler、codegen 或 runtime 已实现。

## 范围

本文负责通用 host binding：资源、类型、variant、常量、同步函数和模块导入。异步函数 ABI、`Future<T>`、`Stream<T>`、`await` 和取消语义见 [async-design.md](async-design.md)。

所有类型参数都必须是合法类型。`nil` 是空值/无值返回标记，不是类型；禁止任何泛型参数中的 `nil`，包括 `Future<T | nil>` 和 `Stream<T | nil>`。函数可以用 `() -> nil` 表示无返回值或返回空；host ABI 的无值结果使用对应的 unit/result 约定。

## 声明形式

```text
名称 = @host_func("包路径", "原名称", 签名)
名称 = @host_const("包路径", "原名称", 类型)
名称 = @host_global("包路径", "原名称", 类型)
名称 = @host_record("包路径", "原名称", 定义)
名称 = @host_resource("包路径", "原名称", 定义)
名称 = @host_variant("包路径", "原名称", 定义)
名称 = @lib("文件名.do", 原名)
```

每种声明只承担一种语义。单行形式中的 `=` 是把 host binding descriptor 绑定到源码名，不是普通运行时赋值；host 函数声明没有函数体。locator、member、签名和类型定义必须是编译期常量；compiler 根据 WIT registry 校验名称、参数、结果、字段和资源所有权。

## WIT 类型映射

```text
resource             -> opaque do resource shell
record               -> do record/type declaration
variant              -> do variant/union
enum                 -> do enum
flags                -> do flags
list<T>              -> do [T]
tuple<...>           -> do Tuple<...>
result<T, E>         -> do T | E
future<T>            -> do Future<T>       // 详见 async-design.md
stream<T>            -> do Stream<T>       // 详见 async-design.md
```

`future<T>` 和 `stream<T>` 只在 WIT/host ABI 边界出现；do 源码使用大写的 `Future<T>` 和 `Stream<T>`。`nil` 不用于表示 WIT 的空结果，WIT 无值结果映射为 `void`。

异步 stream 的源码消费使用 endpoint 形式：`newStream<T>(capacity)` 返回 compiler-managed opaque `StreamReader<T>` 和 `StreamWriter<T>`，调用结果分别通过 `await(reader())` 与 `await(writer(value))` 消费。常见的顺序读取可以使用 `loop value, err = reader() { ... }` 语法糖；它由 compiler lower 为重复的 `await(reader())`，不改变 host ABI。它们不是捕获闭包；`Stream<T>` 表示底层异步序列能力，不要求用户直接调用 `recv(stream)`；EOF、错误和无值结果的具体布局见 [async-design.md](async-design.md)。

## 资源和类型

```do
IOError = @host_resource("wasi:io/error@0.3.0", "error", { id i64 })

Pollable = @host_resource("wasi:io/poll@0.3.0", "pollable", { id i64 })

InputStream = @host_resource("wasi:io/streams@0.3.0", "input-stream", { id i64 })

OutputStream = @host_resource("wasi:io/streams@0.3.0", "output-stream", { id i64 })
```

资源值是 opaque handle。源码不能算术运算、伪造或读取内部句柄；生命周期由 host binding 和 resource ownership 规则管理。

WIT variant 示例：

```wit
variant stream-error {
    last-operation-failed(error),
    closed
}
```

```do
StreamError = @host_variant(
    "wasi:io/streams@0.3.0",
    "stream-error",
    Closed | LastOperationFailed(IOError)
)
```

## 同步 host 函数

```do
host_error_debug = @host_func(
    "wasi:io/error@0.3.0",
    "to-debug-string",
    (IOError) -> text
)

host_poll_ready = @host_func(
    "wasi:io/poll@0.3.0",
    "ready",
    (Pollable) -> bool
)

host_read = @host_func(
    "wasi:io/streams@0.3.0",
    "input-stream.read",
    (InputStream, u64) -> [u8] | StreamError
)

host_write = @host_func(
    "wasi:io/streams@0.3.0",
    "output-stream.write",
    (OutputStream, [u8]) -> void | StreamError
)
```

当前 `wasi-io` 主线的 `input-stream.read` 是非阻塞函数，数据不可用时返回空列表，并通过 `pollable` 表示后续可读状态。不要仅凭函数名把它声明为 async host 函数；正式版本的 WIT 定义是唯一依据。

## 异步函数入口

异步 host 函数仍然使用 `@host_func`，异步性由签名表达：

```do
host_read_async = @host_func(
    "package",
    "async-member",
    async (InputStream, u64) -> [u8] | StreamError
)

host_read_future = @host_func(
    "package",
    "future-member",
    (InputStream, u64) -> Future<[u8] | StreamError>
)
```

这两种签名对应不同的 Component Model ABI，不能直接互换。具体的 do Future wrapper、取消、等待和超时协议见 [async-design.md](async-design.md)。上例 member 名称是 ABI 形态占位符，不代表正式 WASI 接口名称。

## 常量和库

```do
_pi = @host_const("wasi:cli/environment@0.3.0", "PI", f64)

global_counter = @host_global("env", "global_counter", i32)

sha256 = @lib("sha256.do", sha256)
utf8_count = @lib("utf8.do", utf8_count)
```

`@host_const` 绑定只读 host/registry 常量；`@host_global` 只绑定明确支持 global ABI 的 Wasm/host 全局，不表示 WIT 普通接口中的可变状态。Component Model/WIT 的可变状态应优先建模为 host 函数或 resource 方法，避免公开共享全局变量。

## 实现边界

目标 compiler 应自动完成 resource handle、list、record、variant、tuple、result 和异步值的 ABI lift/lower，不生成一组暴露 raw pointer 的公共绑定函数。用户代码只负责声明 locator、使用高层 do 类型和编写业务包装。

当前实现仍按已登记 ABI 白名单拒绝未知复杂签名；本文和 async-design.md 都是未来设计计划，不授权直接开始 codegen 或 runtime 实现。

## 规范依据

- WIT: <https://github.com/WebAssembly/component-model/blob/main/design/mvp/WIT.md>
- Canonical ABI: <https://github.com/WebAssembly/component-model/blob/main/design/mvp/CanonicalABI.md>
- WASI IO streams: <https://github.com/WebAssembly/wasi-io/blob/main/wit/streams.wit>
