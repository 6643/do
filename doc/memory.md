# do v1 内存模型

**当前契约**: Do v1 采用 GC-first 内存模型。普通 Do 对象由 Wasm GC 按可达性回收；
词法块退出不释放普通对象，也不向源码暴露释放时刻。函数参数默认只读借用，不转移
GC 管理责任。普通赋值产生逻辑独立值，不可变存储可以共享，可变动态字段可以使用 COW。
`@set` 作为赋值值时产生新逻辑值，单独作为语句时只修改当前作用域中的可变变量；参数
不能通过语句形式 `@set` 修改。外部资源仍需显式 close/drop，Future 仍需显式 await/cancel。

**实现状态**: 当前编译器生产路径和 v1 源码契约均使用 Wasm GC。ARC emitter、ARC
allocator 和 ownership release plan 只保留为显式 test-only equivalence oracle。WASI/
Component 外部 resource 仍需按 API 和 ABI 显式 close/drop，不能由 GC 回收替代。

**目标**: 在不向用户暴露指针或引用的前提下, 为 Wasm lowering、`[T]`、`text`、
结构体、host ABI、Future/Stream 和 Component/WIT 资源提供统一边界。

**关系**: `doc/spec.md` 是规范入口, `doc/spec_rules.md` 定义源码语义, 本文定义
GC-first 生命周期和当前 Wasm/WASI 实现边界。旧 Region 讨论保留在带日期的历史决策文档中。

## 1. 源码契约

1. 普通对象由 Wasm GC 按可达性回收。编译器负责在局部、frame、table 和 continuation
   中保持必要 root, 不承诺源码可观察的回收时刻。
2. 函数参数默认只读借用；调用不转移 GC 对象的管理责任。当前不设计 owner 接管普通参数。
3. 词法块只决定绑定的可见性和控制流 cleanup, 不决定普通 GC 对象的释放时刻。
4. `_ = value` 是表达式丢弃，不是释放操作。
5. `a = b` 是通用赋值语法，不另设 `copy`/`clone` 操作。普通 Do 值赋值产生逻辑独立副本；
   编译器可以共享不可变存储，或对可变动态字段使用 COW，只要修改一份不影响另一份。
   结构体的动态字段在语义上递归复制；外部资源句柄赋值共享同一资源，
   不复制底层资源；函数参数默认只读借用。
   字面量和编译器生成的只读常量可使用全局只读存储；无法证明共享安全时复制，不使用
   引用计数堆。
6. `@set` 作为赋值值时产生新值，作为语句时原地修改当前作用域中的可变变量；实现采用
   路径复制，目标存储唯一且未逃逸时可以原地复用。存在仍可观察的旧值时，只复制从对象
   根到被修改字段的路径，未修改字段继续共享；数组写入复制可变 backing storage。
   函数参数是只读借用，只能读取并返回新值；调用方取得结果后可以显式执行 `@set`。不提供 `mut`
   参数、`ref<T>` 或核心库特权来绕过只读规则。
7. 函数返回值和其动态字段由 GC tracing 维持对象图可达性。含动态字段的返回值可以通过
   runtime-private result carrier 传递，但不涉及源码可见的显式销毁。标量和纯
   inline 结构体使用普通返回值；构造失败不得留下可达的半成品对象。
8. WASI/Component 外部资源有独立生命周期；返回的 `File` 等句柄由调用方显式
   close/drop，GC 回收不会自动关闭外部资源。
   每次 `close` 都调用资源 API；返回签名、重复关闭和错误行为由具体 API 决定，Do 不统一
   拦截或改写。
9. 异步 Future 必须由 `@await` 或 `@cancel` 消费；Future 绑定的词法作用域结束时仍有未消费的
   Future 必须编译报错，不隐式取消。此检查约束 Future 句柄消费，不管理普通 GC 对象生命周期。
   Future 依赖的 GC roots 和 Component handles 必须保持有效，
   直到异步 ABI 到达终态；显式取消和 await 超时都会等异步 ABI 到达终态；
   无 timeout 的 await 返回任务的 `T | E`，带 timeout 时返回
   `T | E | FutureTimeoutError`；该类型为含 `FutureTimedOut` 分支的标准错误枚举。
   `E` 只包含函数签名显式声明的业务错误；trap、ABI 违规等未声明运行时故障先完成终态
   清理，然后直接终止当前任务或程序，不转换为 `FutureRuntimeError`。
   `defer` cleanup 函数必须返回 `nil`；可能失败的 `close`/析构操作须在注册 `defer` 前
   显式调用并处理，`defer` 不隐式传播清理错误。普通 GC 对象不需要逐个析构。
   未声明运行时故障的报告包含故障类别/原因、发生位置、任务创建位置、`@await` 位置和
   清理状态；该报告不改变 Future 的错误类型。
10. Wasm GC 对象分配遵循目标 runtime 的分配失败行为；当前不定义源码可见的
    `AllocationError`、零值哨兵或隐式错误传播。若未来提供可恢复的显式分配 API，需单独
    定义其返回类型和失败契约。词法作用域退出按 LIFO 执行 `defer` 和必要的外部资源清理；
    普通对象继续由 GC 管理。

## 2. 值表示

### 2.1 Inline 值

以下值可作为 Core Wasm 标量或小型 inline aggregate 传递:

1. `bool`、整数、浮点和 `usize`。
2. `nil`。
3. enum/error 分支值和值枚举分支值。
4. 不含 managed 字段且静态大小不超过 `64B` 的结构体。
5. 命名函数值和无捕获 lambda 的静态函数符号。

### 2.2 Wasm GC 表示

当前生产实现中，`text`、`[T]`、大结构体和包含 managed 字段的结构体使用 runtime-private
Wasm GC references 表示。变量、参数和返回传递的是内部 reference, 不复制
payload。

这些 reference 不可被源码观察、比较、算术运算、转成整数或直接传给 host。
内部 null/sentinel 只用于 lowering, 不构成源码 zero value。

### 2.3 GC 生命周期

当前 GC backend 根据可达性回收 Do object。编译器负责在局部、frame、table 和 continuation
中保持必要 root, 但不为普通赋值、调用、分支或作用域退出生成 source-value
`inc/dec`。

GC 回收没有确定的源码可见时刻。因此 host resource、文件、socket、stream endpoint
和任何需要确定性关闭的外部能力都必须通过显式 close/drop 或 Component ABI terminal
cleanup 处理。

同步 Do 调用发生 Wasm runtime trap 时，该调用终止；Do 代码不能从 trap 处恢复，普通
`defer` 不执行，trap 前完成的内存写入和 host side effect 不回滚。trap 不要求删除编译
产物，也不强制宿主销毁 Wasm instance。宿主可自行决定是否保留或再次调用该 instance；Do
不保证 trap 后的业务状态仍一致。异步任务未声明故障的终态清理另按 `doc/async-design.md`
执行。

## 3. `[T]` 与 copy-on-write 实现约束

本节记录当前实现证据和 GC-first 模型允许的表示优化。COW 不改变值语义：共享值发生写入时，
必须先隔离将要修改的存储。

`[T]` 是有运行时长度的连续值序列, 源码不暴露 backing pointer。

```do
xs [u8] = .{1, 2, 3}
n usize = @len(xs)
v u8 = @get(xs, 0)
ys [u8] = @set(xs, 1, 9)
zs [u8] = @put(xs, 4)
```

规则如下:

1. `@get(xs, i)` 和 `@set(xs, i, value)` 要求 `i < @len(xs)`。直接可知长度的聚合字面量配
   非负十进制整数字面量索引、以及 Tuple 的整数字面量索引若越界，编译报错；不追踪普通变量、
   函数返回或更新后的长度。
   其他越界是 safety failure/trap。
2. `@set` 和 `@put` 产生新逻辑值, 不能修改仍可观察的旧值。
3. 只读传参、赋值和返回不复制 list payload。
4. 写路径采用路径复制；在唯一、未逃逸且容量/布局允许时复用内部 object，否则只复制
   从根到修改位置的路径并共享未修改字段。数组写入复制可变 backing storage。
5. 含 managed child 的 list clone 或重建由 GC tracing 负责 child reachability;
   compiler 不生成 child retain/release。
6. 当前并不承诺 public mutable list、builder 或 reserve API。循环追加的大数据
   场景应先通过专门的 builder/preallocation 设计解决, 不能改变值语义。

## 4. `text` 和结构体

`text` 是有效 UTF-8 值, 不等同于任意 `[u8]`。字符串字面量产生 `text`; 非法
UTF-8 原始数据必须使用 `[u8]`。文本拼接、切片和替换返回新逻辑值。

当前 GC backend 使用 runtime-private UTF-8 byte sequence 表示 `text`, 使用 typed
struct/array 表示 managed struct 和 list。具体 Wasm GC type、字段布局、array
element type 和 nullability 是 codegen 细节, 不属于源码 ABI。

```do
User {
    id u64
    name text
}
```

当前 GC backend 将含 managed 字段或超过 inline 阈值的 struct 作为 GC-managed value。
私有字段只影响源码可见性、构造权限和不变量, 不改变当前 GC 的可达性规则。

当前 GC 同步切片另外准入直接局部对象的一层嵌套 managed-struct 路径:
`@get(outer, .inner, .leaf)` 读取子结构标量叶子, `@set(outer, .inner, .leaf, value)`
重建子结构和外层结构并保留旧值。动态路径、超过一层的路径、producer expression、
async、resource 和 host/WIT 形状仍不在此准入范围。

```do
File {
    .id i64
}
```

`File` 离开作用域不会自动 close host resource。定义模块必须提供显式 close/drop
操作, 并按 API 契约处理其错误。

## 5. 函数、Future 和 Stream

1. 命名函数值和无捕获 lambda 不需要 GC allocation。
2. Do v1 不支持捕获外层局部绑定；lambda 可访问模块级名字，因为它们不是闭包捕获。需要
   外部上下文时通过显式 `env` 参数传入。闭包环境对象和闭包捕获语义不属于 v1。
3. `Future<T>`、`Stream<T>` 的 source contract 不变。其 frame、waitable、buffer
   和 continuation storage 必须在任务借用期间保持有效, 并在 terminal cleanup
   时解除 Component/WIT resource ownership。当前已有 bounded
   `Future<nil>` sequential-await 与 private resource `Result` terminal slices:
   `--p3-wait-for-component` 和 `--p3-async-component` 当前使用 GC-traced
   frame/table；该 bounded `two-await` Future slice 另以同一 WIT、同一
   Rust/Wasmtime host 比较生成的 GC Component 与 hand-authored linear
   frame Component, 四项 pending/wake/completion 统计一致。资源 drop 仍由
   Component boundary 负责。资源取消 slice 也使用同一 backend-neutral 终态
   观测。上述证据不等同于普通 GC sync async admission, 也不覆盖
   `Stream<T>`、通用 async-call 或一般 resource shapes。Future 完成/取消前必须保持其
   frame、buffer 和 Component resource state 可达；这由 GC roots 和 Component ABI 保证。
4. 取消只清理 guest/Component state, 不回滚已发出的 host side effect。

## 6. Linear Memory 和 Component Boundary

Wasm linear memory 是 runtime implementation detail。源码不暴露地址。

1. `@load_*([u8], offset)` 是 checked `[u8]` value operation, 不是裸 pointer
   load。对直接可知长度的聚合字面量和非负十进制整数字面量 offset，若读取宽度静态越界则编译报错；不
   追踪普通变量、函数返回或更新后的长度，其他越界在运行期 trap。
2. `@store_*`、可见 shared memory、公开 atomic pointer API 都不属于 v1。
3. `text`、`[u8]`、list 和 struct 进入 host 时由 compiler 或 std wrapper 做
   explicit ABI marshaling。
4. 当前 Wasm GC references 不跨 Component/WIT boundary。canonical ABI values 在边界
   copied 或 marshaled；不得泄漏内部 GC reference 或线性内存地址。
5. resource handle 不等同于 Do GC object。其 close/drop 和 async liveness 继续由
   Component/WIT ABI 契约处理，不由 GC 回收替代。

## 7. Public Non-goals

1. 不引入 general pointer、reference、`ref<T>`、`own<T>`、`borrow<T>` 或
   lifetime syntax。
2. 不用 GC finalizer 替代 resource close/drop。
3. 不承诺任意 WIT nested borrow 在 list、record、future 或 stream 中可用; 每个
   shape 必须经过 pinned Component capability gate。
4. 不把 Wasm GC typed references 暴露为 Do source values。
5. COW 是 GC-first 模型允许的内部表示优化，不是源码可观察的引用语义；字符串、数组和复杂
   对象都可以共享不可变存储，但写入必须保持逻辑值独立。

## 8. Implementation State

普通 `do build` 当前通过 `codegen_runtime_api.zig` 进入 GC-only production route；
ARC 不再作为默认 fallback。`runtime_arc_wat.zig`、`runtime_prelude_wat.zig` 及
相关 legacy emitters 仅由显式 `src/build/test/gc_arc_equivalence_oracle.zig`
测试入口引用，用于保留 26 行等价快照。WIT resource 的 ownership/drop 计划仍是
独立的 Component/ABI 生命周期，不由 GC 接管。

以上同时是当前生产代码事实和 v1 源码内存契约。Region allocator 不属于 v1 实现计划。

历史 ARC object layout、allocator、`rc == 1` reuse 和 `inc/dec` 规则不再是
v1 规范；它们保留在源码、changelog 和 dated plans 中作为迁移证据。通用
async/map/producer/resource lowering 仍需各自的 design/gate，不能以现有 GC
cutover 证据替代。公开 `own<T>`/`borrow<T>`/`ref<T>` 不是当前选择的源码模型。

## 9. Verification Boundaries

当前 GC backend 的历史验证至少证明：

1. Read-only passing of large managed values does not copy payload.
2. Shared value update preserves the old logical value.
3. Unique local update may reuse storage only without observable mutation.
4. GC roots keep managed values alive across branches, loops, `Future` and
   `Stream` suspension.
5. GC collection never substitutes for WIT resource drop or cancellation
   terminal cleanup.
6. Component ABI lift/lower never leaks a GC reference across the boundary.
7. Full compiler regression, Component assembly and host execution pass on the
   selected toolchain.

GC-first 仍需验证：所有 GC managed roots 在分支、循环、Future 和 Stream suspension 期间
保持可达；普通赋值产生逻辑独立值并允许共享不可变存储和 COW；`@set` 语句只修改当前
可变绑定，赋值接收时产生新逻辑值；`defer` 按注册逆序执行并完成外部 resource cleanup；
WASI resource cleanup 与 GC 对象回收保持独立且各自遵循对应契约。
