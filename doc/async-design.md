# do 并发设计

**状态:** 公开契约已冻结。编译器已落地一个受限的 colorless async vertical
slice；本文不宣称当前 `bin/do` 已完成任意 Future/Stream runtime、通用 WIT
async lowering 或完整 WASI P3 host execution。

## 公开源码模型

do 的并发源码是无色的：所有用户函数都使用普通声明，任务创建、等待和取消
都显式使用带 `@` 前缀的 compiler intrinsic。语言不公开 `async` 函数颜色，
也不公开 task spawn keyword、`Channel<T>`、fiber、指针、引用、闭包或
`funcref`。

```do
work() -> nil { return }

run() -> nil {
    ready Future<nil> = @async(work())
    @await(ready)
    middle Future<nil> = @async(work())
    @await(middle)
    pending Future<nil> = @async(work())
    @cancel(pending)
}
```

当前普通 Core lowering 只接受上述固定的三个 `Future<nil>` 顺序：前两个必须
`@await`，第三个必须终态 `@cancel`。对应的 Component probe 还验证了
pending、immediate-ready 和取消路径的 exactly-once cleanup；payload Future、
Stream、resource、分支、循环、回调和任意 async 函数仍返回
`AsyncLoweringUnavailable`。

已登记的 WIT `async func` host binding 本身就产生 `Future<T>`，因此直接调用：

```do
work = @host_async_func("do:generic-async-runtime-probe/host@0.1.0", "work", () -> nil)

run() -> nil {
    ready Future<nil> = work()
    @await(ready)
}
```

`@host_async_func` 只允许登记为 WIT `async func` 的目标；它的源签名写异步
payload 类型，不额外包一层 `Future<...>`。相反，`@host_func` 只允许普通
WIT `func`，包括返回 `future<T>` 的普通函数；这类普通 WIT future 仍在源签名
中明确写成 `Future<T>`。

不要把这种调用再包成 `@async(work())`，否则会形成未定义的
`Future<Future<T>>` 语义。`async name(...) -> T` 已弃用，不是公共函数模型；
parser 不再把它登记为函数，正常编译会报告 `DeprecatedAsyncFunctionDecl`。
本文后续若出现 `async ...` 片段，仅属于旧的 descriptor-specific 负例或历史记录，
不应作为新源码模板。

因此，以下边界是固定的：

- 普通 Do 函数调用必须显式写成 `Future<T> = @async(work())`；裸的
  `Future<T> = work()` 不再隐式创建任务。
- 已登记的 WIT `async func` 是唯一例外。它的生成 host binding 已经返回
  `Future<T>`，调用时保持 `Future<T> = work()`，不能再包 `@async`。
- `async run(...) -> T` 与普通函数对 `Future<T> = work()` 的组合属于同一套旧
  隐式语义。前者在正常编译中发出弃用诊断，后者在普通 Do 函数中拒绝；两者都
  不是公共源码形式。

## Future 与 Stream

`Future<T>` 是 affine 的一次性结果句柄。`await`、`await_all`、`await_any` 和
`@cancel` 都消费其所有权；未消费 Future 不能静默离开作用域。`@cancel` 是任务
生命周期操作，不产生源码可见的 `Cancelled` 结果分支。

G6.2 现已增加一个仅限登记 descriptor 的 resource Result 取消切片。源码必须显式
保存并消费 `Future<Result<HttpResponse, HttpError>>`：

```do
cancel_request(request HttpRequest) -> nil {
    completion Future<Result<HttpResponse, HttpError>> = send(request)
    @cancel(completion)
}
```

该切片是一个没有后续 `await` 的 nil-returning root，因此不分配 result frame；它直接生成
Component 的 `subtask.cancel` -> `subtask.drop` -> `task-return` 顺序，并覆盖 pending host
future drop、request 消费和空 `ResourceTable`。隐式 scope-drop、重复
取消、终态后取消、任意 descriptor 仍被拒绝；取消不回滚已发出的外部副作用。对应的 Do
lowering、Component assembly 和 Rust/Wasmtime gate 是
`test_do_resource_cancellation_shape.sh` 与 `test_rust_resource_cancellation_shape.sh`。

同一 private resource descriptor 的 `result<response, error-resource>`
切片还验证了 ready `Err(error-resource)` 的 owned error transfer：错误终态只
创建并释放 error resource，不创建 response；`Ok`、`Err` 与 cancel 都复用
exactly-once request/frame/subtask cleanup。该验证仍不开放任意 Result payload、
公共 `own<T>`/`borrow<T>` 或通用 resource cancellation。

Async frame 和 canonical buffer 的 generated Core runtime 还维护一个 instance-local
byte counter。它默认使用 `-1` 表示 unlimited；runtime 可以在第一次 admission 前通过
Core-only `[async-config]byte-budget-limit(i64) -> i32` 设置非负上限，低于当前 live
usage 的新上限会被拒绝且不改变状态。这个 hook 不进入 Do source syntax，也不等于
Component scheduler 已经提供 quota admission；Component host adapter 和其他动态
allocation call sites 仍需单独接入。

`Stream<T>` 是不透明的异步序列。`new_stream<T>(capacity)` 创建单 consumer 的
`StreamReader<T>` 和带 producer lease 的 `StreamWriter<T>`。`writer(value)` 的源码
结果是 `Future<Result<nil, E>>`，且 value 必须与 `T` 相同；reader/writer 调用各自
返回 Future；容量为零时是 rendezvous，正容量时是有界 FIFO buffer。`close(writer)`
关闭一个 lease；所有 lease 结束并排空 buffer 后 reader 收到 `Done`。`abort(writer, err)`
使后续和等待写入失败，但不会撤销已接受的 buffer 项。

导入的 WIT `stream<T>` 在 Do 源码中是 `Stream<T>` reader。`@next(reader)` 保留
reader owner 并产生 `Future<Result<T, nil>>`；`await` 该 Future 后，`Ok(value)` 表示
一个元素，`Err(nil)` 表示 EOF。reader 的 Scope cleanup 负责释放可读端。WIT 同时
返回的 completion `future<result<_, E>>` 是独立的 `Future<Result<nil, E>>`，调用者
必须显式 await 或 cancel；它不合并进 EOF。当前已用 pinned
`wasi:cli/stdin.read-via-stream` `u8` fixture 验证 canonical
stream/future lowering、取消和 Wasmtime 执行；同一 descriptor-driven 路径还由
私有 `do:stream-probe@0.1.0` source fixture 验证了显式 module/import 元数据、
三次 item/item/EOF 读取、未 poll 的 completion future，以及 stream/future 各一次
drop。通用 payload 和任意 WIT stream producer lowering 仍未完成。内部 writer
FIFO/lease 状态模型已经验证；pinned `wasi:cli/stdout.write-via-stream` 的 async
canonical import 也已由 `wasm-tools 1.254.0` 生成复核并登记为 Do descriptor。
当前有两条固定 `u8` 验证路径：forwarding wrapper 的 pending/immediate/host
`Err(pipe)` 回调，以及 `guest-producer` wrapper 在容量 1 的内部 stream 中写入
`[65, 66, 67]`，并覆盖 consumer early-drop；正常、early-drop、host `Err(pipe)`
三种 Rust/Wasmtime 矩阵均要求 FIFO、一次 host callback、一次 pending write、
exactly-once close/drop。它们证明固定 descriptor 和终态清理，不等于通用
queue-to-stream pump、任意 producer endpoint 或 `abort` 到外部 WIT 错误值的映射。
当前 guest producer 的受限 `u8` fixture 允许先绑定 `name u8 = literal`，
再以 `writer(name)` 写入；另有一个参数化 countdown checkpoint 接受
`(count u64, value u8)`，把同一个 value 保存在 frame slot 60，并在每次 admission
前复制到一字节 source buffer。这只是注册 descriptor 的动态值覆盖，不扩大 payload、
endpoint 或一般 async-call 边界。只有带 `@` 前缀的 `@next` 是 intrinsic；裸 `next` 仍可作为普通用户
名称。内部 `StreamWriterQueuePump` 模型已覆盖有限源序列、容量 0 rendezvous、FIFO
pending 和延迟 close；固定 guest-producer Component emitter 现在通过统一的
`$writer-pump-step` resumable helper 消费这些状态。它仍不代表任意 source-level
queue-to-stream lowering 已开放；当前 B1 只接受注册表明确登记、并有对应
Component/Rust gate 的 `stream<u8>` descriptor（包括 pinned stdout、私有
`do:stream-probe` 和 HTTP body producer slices）以及编译期有界源序列。动态迭代、
任意 payload、外部 writable endpoint、abort 错误映射留到后续阶段。

G6.2 另有一个更窄的 helper-mediated lease gate：根级 producer 可以把
`StreamWriter<u8>` 一次性传给一个只有同类型 writer 参数的迁移期 `async` helper。基础 helper
形状最多允许一个私有 forwarding helper 把仍未关闭的 lease 转给最终 helper；最终 helper 可以直接
调用已登记的 stream-writer host descriptor，或先执行有界的线性 `u8` 写序列再调用
descriptor，并负责 `defer close(writer)`。Component emitter 将这个固定 helper body
合并到 producer root，WIT 只导出 root；pending/ready/`Err(pipe)` 的 Rust/Wasmtime gate
验证 `[65, 66]`、单次 host callback和单次 stream drop。随后同一 descriptor 增加了
一个严格的参数化 helper 形状：helper 只能接收 `(StreamWriter<u8>, u64, u8)`，参数化链最多允许五个私有 forwarding helper，root 只能
按 `(writer, count, value)` 原样转移；它复用 countdown 的 frame offset 52/60，运行
`count=0/1/3`、`value=90` 的 pending/ready/`Err(pipe)` 矩阵。第六跳、一般 async
helper lowering、动态 producer、任意元素布局或 payload-bearing producer error 仍被拒绝。

参数化 producer 还允许一个严格的一跳 forwarding 形状：`produce` 将
`(writer, count, value)` 原样传给私有 `forward_stream`，后者再将同名同序参数传给
已验证的 countdown helper；forwarder 不写、不 close、不创建 stream，也不能继续转发。
Component 仍只导出 `produce`，并复用 frame offset 52/60。该形状的
Component/Rust/Wasmtime gate 覆盖 `count=0/1/3`、`value=90`、pending/ready/`Err(pipe)`、
单次 callback 和单次 stream drop；参数错位、一般 async call 与任意 producer
expression 继续拒绝。

在一跳形状之上，当前还允许严格的两跳 forwarding 链：
`produce -> forward_stream -> middle_stream -> finish_stream`。两个 forwarder
都只能把 `(writer, count, value)` 原样传给下一个同类型 helper 并 await 结果；最终
helper 仍负责 countdown、sink 调用和 `defer close(writer)`。Component 仍只导出 root，
并复用 frame offset 52/60；`count=0/1/3`、`value=90` 的 pending/ready/`Err(pipe)`
矩阵验证一次 callback 和一次 stream drop。第六个 forwarding edge、参数错位、一般
async call、任意 producer expression 与资源字段扩展继续拒绝。

两跳形状之上，当前还允许一个严格的三跳 forwarding 链（历史切片）：
`produce -> entry_stream -> forward_stream -> middle_stream -> finish_stream`。
三个 forwarder 都只能把 `(writer, count, value)` 原样传给下一个同类型 helper 并
await 结果；最终 helper 仍负责 countdown、sink 调用和 `defer close(writer)`。Component
仍只导出 root，并复用 frame offset 52/60；`count=0/1/3`、`value=90` 的
pending/ready/`Err(pipe)` 矩阵验证一次 callback 和一次 stream drop。第六个 forwarding
edge、参数错位、一般 async call、任意 producer expression 与资源字段扩展继续拒绝。

在三跳形状之上，当前还允许一个严格的四跳 forwarding 链：
`produce -> outer_stream -> entry_stream -> forward_stream -> middle_stream -> finish_stream`。
四个 forwarder 都只能把 `(writer, count, value)` 原样传给下一个同类型 helper 并
await 结果；最终 helper 仍负责 countdown、sink 调用和 `defer close(writer)`。Component
仍只导出 root，并复用 frame offset 52/60；`count=0/1/3`、`value=90` 的
pending/ready/`Err(pipe)` 矩阵验证一次 callback 和一次 stream drop。第六个 forwarding
edge、参数错位、一般 async call、任意 producer expression 与资源字段扩展继续拒绝。

在四跳形状之上，当前还允许一个严格的五跳 forwarding 链：
`produce -> outer_stream -> entry_stream -> forward_stream -> middle_stream -> inner_stream -> finish_stream`。
五个 forwarder 都只能把 `(writer, count, value)` 原样传给下一个同类型 helper 并
await 结果；最终 helper 仍负责 countdown、sink 调用和 `defer close(writer)`。Component
仍只导出 root，并复用 frame offset 52/60；`count=0/1/3`、`value=90` 的
pending/ready/`Err(pipe)` 矩阵验证一次 callback 和一次 stream drop。第六个 forwarding
edge、参数错位、一般 async call、任意 producer expression 与资源字段扩展继续拒绝。

G6.2.3 的语义基础现在采用路径敏感的 `StreamWriter<T>` lease 分析：if/else 合流、loop
`break`/`continue`、词法 `defer`、同类型 transfer、helper transfer、writer write、
close/abort 终结和 async exit 都必须在每条可达路径上保持一致。合流状态不一致时拒绝
`maybe` lease，并使用稳定的 `StreamWriterLeasePathConflict`；带着当前 defer cleanup
转移 writer 时使用 `StreamWriterDeferredTransfer`。这只改变前端语义检查，不扩大已有
descriptor-specific Component emitter 或 runtime ABI；一般 producer lease、任意 async-call
composition、任意 producer expression 和公开 `own<T>`/`borrow<T>`/`ref<T>` 仍是后续独立
设计边界。

G6.2 的 record-stream consumer 另有一条独立的六层 nested owned-resource
checkpoint：`resource-entry.inner -> deep-entry -> deeper-entry ->
deepest-entry -> ultra-entry -> hyper-entry -> own<ticket>`。manifest 只允许单子节点容器，递归 WIT 声明、Core
decode/release 和 frame-owned handle slot 复用同一 descriptor-driven emitter；六层
Component/Rust/Wasmtime pending/ready/error gate 都观察 `[111,222]`、两次资源创建与
释放、一次 stream drop、一次 future drop 和空的 resource table。第七层、borrow/list/
variant、多个子节点、混合 scalar/nested 与资源逃逸仍拒绝；这不引入公开
`own<T>`、`borrow<T>` 或 `ref<T>` 语法。对应 gate 见
`test_do_record_resource_stream_nested_six_level_probe_lowering.sh` 和
`test_rust_record_resource_stream_nested_six_level_probe.sh`。

在此基础上，注册的 `do:stream-probe` sink 还有一个独立的 bounded dynamic
gate：root 只能是 `(count u64) -> Result<nil, ProbeError>`，容量固定为 1，循环必须是
zero-pre-guarded countdown，每次只写 literal `65`、await、discard 并减一；sink
在第一次 pump 前启动，`count=0` 产生空 stream。该形状将 `remaining` 存在 frame offset
52 的 `i64` 槽，并在 pending write 完成时递减。`test_rust_stream_writer_guest_producer_dynamic.sh`
覆盖 `count=0/1/3` 的 pending/ready/`Err(pipe)` 运行矩阵。它不开放一般循环、动态 byte、
一般 async call、`own<T>`/`borrow<T>`/`ref<T>` 或任意 writable endpoint。

G6.2 还闭合了一个独立的 descriptor-bounded `StreamMirror` runtime slice：注册的
`do:stream-probe/source.read-via-stream` 提供 `Stream<u8>` 与 completion future，guest
最多读取三项并写入容量一的 `StreamWriter<u8>`，随后把 readable endpoint 转移给注册的
sink。`pending`、`ready`、source EOF、sink `Err(pipe)`、sink early-drop 和 guest
cancel 六种 Rust/Wasmtime 模式都验证了有序 payload、一次 source stream drop、一次
source future drop、一次 sink callback/drop 和 `table-empty=true`。终态 emitter 在丢弃
waitable-set 前先丢弃已完成的 sink subtask，并清零 frame 槽位；这修复了原先的
`resource has children` 错误。该 gate 仍只接受固定 descriptor 和 bounded source shape，
不开放一般 producer lease、任意 async call、borrow/list/variant resource fields 或公开
`own<T>`/`borrow<T>`/`ref<T>`。

## WASI HTTP 资源图边界

编译器校验 pinned `wasi-http@0.3.0-rc-2025-09-16` 的 nominal 资源图：
`http/types/fields`（headers/trailers 的底层资源）、
`http/types/request-options`、`http/types/request` 和
`http/types/response`。`request.new` 的 headers、可选 `stream<u8>` body、
trailers future 和可选 request-options 参数，以及 request/response 的
`consume-body` 签名，都由 pinned WIT 快照的 hash 与结构检查共同约束。

Do source 只能用对应的 `@wasi_resource` shell（当前 HTTP probe 使用
`HttpHeaders`、`HttpRequestOptions`、`HttpRequest`、`HttpResponse`）；这些 shell
不是公开的 `own<T>`/`borrow<T>` 语法，也不把 HTTP response 复制成 `{status, body}`
记录。`wasi:http/client.send` 的 service WIT sidecar 可以生成并引用这些 nominal
类型。统一 Component 目标另外支持一个固定的 `response.consume-body` probe：
它只接受编译期线性的最多三次 `@next(reader)` -> `await` -> discard；body
可以显式 `@cancel(completion)`，也可以在 body 终止后执行一次
`await(completion)` 并丢弃结果。两条路径及 terminal `Err(nil)`、pending/ready
的 `future.read` 都已经通过 WAT、Component assembly 和 Rust/Wasmtime 执行验证。
当前仍不 lift trailers 的 `option<trailers>` payload。已增加一个受限的空请求构造
路径：`request.new` 只接受空 `fields`、`none` body、立即完成为 `Ok(None)` 的
trailers future 和 `none` options；构造出的 request 只允许一次性转移给固定的
`client.send` probe。该路径只在 `--p3-async-component` 下可用，普通 `do build`
以及动态 body/trailers、未登记 payload error-code 和通用 `client.send` lowering 继续保持
显式的 `AsyncLoweringUnavailable` 边界。对应的 Core/Component 和 Rust/Wasmtime
证据见 `examples/p3-runtime/test_do_http_request_empty_lowering.sh`、
`test_rust_http_request_empty.sh` 和 `test_rust_http_service_empty_request.sh`。

在同一 pinned HTTP 资源图上，另有一个更窄的 payload cancellation checkpoint：
`http-payload-cancel.do` 只允许把 `Future<Result<HttpResponse, HttpError>>`
保存到局部后显式执行 `@cancel(completion)`，并要求根函数返回 `nil`。该路径
使用临时 private service world，不修改 pinned WIT 包；生成的 Core/Component
导入精确的 versioned `send` 与 request/response drop，Rust/Wasmtime 观察到一次
request consumption、一次 pending future drop、零 response create/drop 与空
`ResourceTable`。已登记的 immediate `Ok(response)`、`DnsTimeout`、
`DNS-error` optional `rcode`（`Some(nonempty)` / `None`）和 `InternalError`
optional string（`Some(nonempty)` / `None`）也各有 ready poll/drop 与 payload
discard 证据；`None` 不读取或释放 pointer/length。它不把取消变成 rollback，也不
扩展到 cancel-after-terminal、double/implicit cancellation、未登记 payload、动态
HTTP 形状或通用 resource cancellation。非空 payload 槽位在精确释放后可由同一实例
的下一次顺序调用复用，但任何时刻仍只允许一个该 private string allocation。
证据入口是 `examples/p3-runtime/test_do_http_payload_cancellation.sh`。

manifest 同时保留 operation facts：`request.new` 返回新的 request 与传输
future，不移动 receiver；request/response 的 `consume-body` 都移动对应
resource，并返回独立的 `Stream<u8>` 与 trailers future；`future.read-2` 仅在
显式 await probe 中启用。这些 facts 供后续 canonical emitter 使用；固定 body
probe 不构成公开的 HTTP convenience API，
也不改变 `own<T>`/`borrow<T>` 只在 WIT/manifest 内部表达的决定。

请求 body 目前增加了一个更窄的固定切片：`wasi:cli/stdin.read-via-stream`
返回的 `Stream<u8>` 可以作为 `request.new` 的 `option<stream<u8>>` body。
源码必须按 acquisition -> `request.new(reader)` -> `client.send` 的线性顺序，
不能公开 `own<T>`、`borrow<T>`、`ref<T>`，也不能创建动态 producer 或 source-level
循环。reader 在构造时转移，独立的 source completion future 留在 async frame，
在 send 的终态回调中 exactly-once drop；取消不回滚已发生的 host/网络副作用。
对应证据是 `test_do_http_request_body_abi.sh`、
`test_do_http_request_body_lowering.sh` 和 `test_rust_http_request_body.sh`。
同一切片现在另有一个顺序化 await 变体：fixture 先对 source completion
执行一次 `await(source_done)`，成功后才调用 `request.new(reader)`；emitter
使用 pinned `future-read-1`，对 pending/ready 两种 host future 都通过实际
Component callback 完成，随后复用同一 request/send cleanup。该变体不引入
send 与 source completion 同时挂起的并发状态机，也只接受无 payload 的成功
completion；证据是 `test_do_http_request_body_await_completion_lowering.sh`
和 `test_rust_http_request_body_await_completion.sh`。

## Scope 与取消

每个包含异步操作的 root 创建一个 Scope；async frame、Future、Stream endpoint、defer payload 和
host resource 都由它统一拥有。对已 pinned 的 Component async lowering，`@cancel(future)`
直接调用该 Future 的 `subtask.cancel`，等待 ABI 终态后执行 `subtask.drop`。它不创建 Do
operation ID、取消确认事件或 host broker。

任务取消不承诺撤销已经对数据库、网络或其他外部系统提交的副作用。该类补偿、幂等和
结果协调由 host API 与业务协议定义；编译器只遵循 Component 的任务/subtask 生命周期。

## 后端边界

编译器将 await 链 lower 为可恢复 frame/state machine。Wasm GC 只管理 guest frame/object；
resource drop、取消、`defer` 和 host buffer 清理由 Scope 显式执行。新功能不得增加 ARC
lowering，也不得让 `__arc_inc`/`__arc_dec` 出现在 GC target 的 async path。

WIT `async func` 由 binding metadata 和 Component target 描述，不对应源码中的
`async` 函数声明；host 的 WIT `future<T>`/`stream<T>` 分别映射为不透明的 do
`Future<T>`/`Stream<T>`。编译器经 WIT metadata 和 `wasm-tools` 产出 Component，
不链接或依赖 Wasmtime。Wasmtime 或其他 runtime 的实际执行能力另列为运行时兼容矩阵，
且不等于完整 WASI 或浏览器支持。

## 非目标

- 不公开 `Scope`、task callback 或 host callback 类型。
- 不支持匿名任务、捕获、retained guest callback、抢占或 guest 内部多线程。
- 不以 GC 回收时机替代 resource cleanup。
- 浏览器 event pump、DOM/UI 组件和 retained JS callback 另行设计；它们只能消费
  通用 Scope/Future/Stream 能力，不能反向加入 UI compiler special case。

实施顺序见 [async-future-stream.md](../docs/superpowers/plans/2026-07-29-async-future-stream.md)，
阻断证据见 [host_abi_blockers.md](host_abi_blockers.md)。
