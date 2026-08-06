# Host Binding 设计

**状态:** 部分实现。`do wit check/bind`、WIT 到 Do 声明的翻译、manifest/lock 输出和普通 custom locator checker 已落地；本文仍不表示通用 custom host 的 codegen/runtime 已实现。

## 已落地的 WIT 翻译入口

生产实现位于 `src/wit/`，固定上游 `wit-bindgen v0.60.0` checkout 位于
`.deps/wit-bindgen/`，只用于 Go/Rust 差分 probe。项目级生成输出放在根目录
`wit/`，源文件可以放在 `wit/src/`；生成器会保留该源树和项目 README。

```bash
do wit check <wit-input> [--world <world>] [--manifest <manifest.json>]
do wit bind <wit-input> --world <world> --out <project>/wit
```

生成的 `*.do` 使用普通 `@host` 声明。locator 语法接受任意合法 WIT
`<namespace>:<package>/<interface>@<semver>`；只有已登记的 WASI/P3 locator
才进入现有 lowering。Go/Rust 生成代码不是生产输入，custom host 的 WAT/
Component lowering、runtime 调度和可执行异步 binding 仍需独立 gate。

生成输出的 `manifest.json` 可通过显式的 `--manifest` 参数校验 package/world、
WIT 内容哈希、生成模块路径、规范化 member 签名和每个 member 的
async/future/stream/resource effect。manifest 同时保存每个生成 `.do` 模块的
内容哈希；模块签名被手工改动或缺失时，校验失败并返回
`ManifestGeneratedModuleMismatch`，不能降级为同步 host import。

## 范围

本文负责通用 host binding：资源、类型、variant、常量、同步函数和模块导入。P3 async ABI、waitable、WIT `future<T>` / `stream<T>` 和取消协议映射到公开的 do `Future<T>`、`Stream<T>` 以及 `@async`、`@await`、`@cancel` intrinsic，并发契约见 [async-design.md](async-design.md)。源码不再使用 `async` 函数声明；旧声明仅在迁移窗口兼容。

所有类型参数都必须是合法类型。`nil` 是空值/无值返回标记；它只允许作为 `Future<nil>`、`Stream<nil>` 等异步容器的唯一类型参数，或作为 `Result<T, nil>` / `Result<nil, E>` 的 unit 分支。函数可以用 `() -> nil` 表示无返回值或返回空；其他泛型参数位置仍禁止 `nil`。

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
future<T>            -> opaque do Future<T>
stream<T>            -> opaque do Stream<T>
```

WIT `future<T>` 和 `stream<T>` 在 host ABI 边界分别映射为不透明的 do `Future<T>` 和 `Stream<T>`；其具体 waitable、frame 与 cleanup record 仍是后端实现细节。WIT `async func` 由 binding manifest 描述，生成的 do 源码不再声明 `async name(...) -> T`；普通 Do 函数调用必须用 `Future<T> = @async(call(...))` 显式创建任务，异步 host binding 已直接产生 `Future<T>`，不能再次包 `@async`。WIT 的无结果操作映射为 do `nil`；无值异步操作的源码形态是 `first Future<nil> = wait_for(delay)`，其中 `wait_for` 必须是已登记的 WIT async host binding。

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
    (OutputStream, [u8]) -> nil | StreamError
)
```

当前 `wasi-io` 主线的 `input-stream.read` 是非阻塞函数，数据不可用时返回空列表，并通过 `pollable` 表示后续可读状态。不要仅凭函数名把它声明为 async host 函数；正式版本的 WIT 定义是唯一依据。

## P3 async backend 边界

异步 `@host_func` descriptor 的 locator、member、WIT effect、resource ownership、直接 Component task/subtask lifecycle 与 canonical ABI 必须从 pinned WIT world/interface/member manifest 解析。do 函数签名或 member 文本不能猜测这些属性。当前 compiler 的 `do check` 已读取 `src/build/p3_async_registry.json`，登记 `wasi:clocks@0.3.0` 的 `monotonic-clock.wait-for` / `wait-until` 和 `wasi:cli@0.3.0` 的 `run.run`，并要求各自的精确签名；descriptor 保留其已验证的 Core ABI、`task-return` completion、显式 Core import module/name 与 WIT package/interface/operation/world/parameter。manifest 不含 operation token 或 per-descriptor cancellation capability；`@cancel(Future<T>)` 直接遵循 pinned Component task/subtask ABI，且不承诺外部副作用回滚。Core import 和 WIT sidecar 名称只能取 manifest 字段，不能由 locator/member 或源码局部名拼接。默认 build 只验证 descriptor identity 和 metadata，不生成 import、不会使该 binding 可调用，也不改变 async build gate。descriptor 不是函数值；后续唯一调用入口为 `@host_call<HostFunc>(...)`，它会进入内部 `may_suspend`/TaskFrame/P3 resume path，但不把 `future`、`stream`、callback 或 `task.return` 暴露给源码。

## 常量和库

```do
_pi = @host_const("wasi:cli/environment@0.3.0", "PI", f64)

global_counter = @host_global("env", "global_counter", i32)

sha256 = @lib("sha256.do", sha256)
utf8_count = @lib("utf8.do", utf8_count)
```

`@host_const` 绑定只读 host/registry 常量；`@host_global` 只绑定明确支持 global ABI 的 Wasm/host 全局，不表示 WIT 普通接口中的可变状态。Component Model/WIT 的可变状态应优先建模为 host 函数或 resource 方法，避免公开共享全局变量。

## 实现边界

目标 compiler 应自动完成 resource handle、list、record、variant、tuple、result 和 backend async record 的 ABI lift/lower，不生成一组暴露 raw pointer 的公共绑定函数。用户代码只负责声明 locator、使用高层 do 类型和编写业务包装。

当前实现仍按已登记 ABI 白名单拒绝未知复杂签名；本文和 async-design.md 都是未来设计计划，不授权直接开始 codegen 或 runtime 实现。

## 规范依据

- WIT: <https://github.com/WebAssembly/component-model/blob/main/design/mvp/WIT.md>
- Canonical ABI: <https://github.com/WebAssembly/component-model/blob/main/design/mvp/CanonicalABI.md>
- WASI IO streams: <https://github.com/WebAssembly/wasi-io/blob/main/wit/streams.wit>
